import Foundation

/// Keys and/or a caption an agent asks Keyray to show (CLI, `keyray://` URL or MCP). Everything is
/// sanitized and length-limited on construction, so the HUD never sees raw input.
public struct Announcement: Codable, Equatable, Sendable {
    public private(set) var keys: String?
    public private(set) var caption: String?
    public private(set) var source: String

    public static let maxKeys = 32
    public static let maxCaption = 120
    public static let maxSource = 24
    public static let defaultSource = "agent"
    /// The distributed notification the CLI and MCP server post; `object` is `json`.
    public static let notificationName = "com.s3onghyun.keyray.announce"

    /// Nil when there is nothing to show.
    public init?(keys: String?, caption: String?, source: String? = nil) {
        self.keys = Self.clean(keys, max: Self.maxKeys).map(Self.keyLabel)
        self.caption = Self.clean(caption, max: Self.maxCaption)
        self.source = Self.clean(source, max: Self.maxSource) ?? Self.defaultSource
        if self.keys == nil && self.caption == nil { return nil }
    }

    /// `keyray://show?keys=⌘K&caption=…&source=…` or `keyray://caption?text=…&source=…`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "keyray",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host?.lowercased() {
        case "show": self.init(keys: q("keys"), caption: q("caption"), source: q("source"))
        case "caption": self.init(keys: nil, caption: q("text") ?? q("caption"), source: q("source"))
        default: return nil
        }
    }

    /// The JSON a notification carries; decoding re-sanitizes, so a forged payload gets no further.
    public var json: String { String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }

    public init?(json: String) {
        struct Raw: Decodable { var keys: String?; var caption: String?; var source: String? }
        guard json.utf8.count <= 4096, let raw = try? JSONDecoder().decode(Raw.self, from: Data(json.utf8)) else { return nil }
        self.init(keys: raw.keys, caption: raw.caption, source: raw.source)
    }

    /// `keyray://` form of this announcement, for launching the app when it is not running.
    public var url: URL {
        var c = URLComponents()
        c.scheme = "keyray"
        c.host = "show"
        c.queryItems = [URLQueryItem(name: "keys", value: keys), URLQueryItem(name: "caption", value: caption),
                        URLQueryItem(name: "source", value: source)].filter { $0.value != nil }
        return c.url!
    }

    /// Drops control and invisible formatting characters (bidi overrides could spoof text), folds
    /// whitespace runs to one space, trims, and cuts to `max` characters with "…".
    static func clean(_ s: String?, max: Int) -> String? {
        guard let s else { return nil }
        var out = ""
        var space = false
        for scalar in s.unicodeScalars {
            if scalar.properties.isWhitespace { space = !out.isEmpty; continue }
            let cat = scalar.properties.generalCategory
            if cat == .control || (cat == .format && scalar.value != 0x200D) { continue }
            if space { out.unicodeScalars.append(" "); space = false }
            out.unicodeScalars.append(scalar)
        }
        if out.isEmpty { return nil }
        return out.count > max ? String(out.prefix(max - 1)) + "…" : out
    }

    private static let keyWords: [String: String] = [
        "cmd": "⌘", "command": "⌘", "meta": "⌘", "super": "⌘", "ctrl": "⌃", "control": "⌃",
        "alt": "⌥", "opt": "⌥", "option": "⌥", "shift": "⇧",
        "enter": "↩", "return": "↩", "esc": "⎋", "escape": "⎋", "tab": "⇥", "space": "Space",
        "backspace": "⌫", "delete": "⌫", "up": "↑", "down": "↓", "left": "←", "right": "→",
    ]
    private static let modifierOrder = ["⌃", "⌥", "⇧", "⌘"]

    /// "cmd+shift+p" → "⇧⌘P"; anything else is shown as given.
    static func keyLabel(_ s: String) -> String {
        let parts = s.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count > 1, !parts.contains(where: \.isEmpty) else { return s }
        let mapped = parts.map { keyWords[$0.lowercased()] ?? ($0.count == 1 ? $0.uppercased() : $0) }
        let mods = modifierOrder.filter(mapped.contains)
        return mods.joined() + mapped.filter { !modifierOrder.contains($0) }.joined(separator: " ")
    }

    /// `show <keys> [--caption <text>] [--source <name>]` or `caption <text> [--source <name>]`.
    public static func parse(arguments args: [String]) -> Result<Announcement, ArgumentError> {
        guard let command = args.first, command == "show" || command == "caption" else { return .failure(.usage) }
        var positional: [String] = []
        var caption: String?
        var source: String?
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--caption", "--source":
                guard i + 1 < args.count else { return .failure(.missingValue(args[i])) }
                if args[i] == "--caption" { caption = args[i + 1] } else { source = args[i + 1] }
                i += 2
            default:
                positional.append(args[i])
                i += 1
            }
        }
        let text = positional.isEmpty ? nil : positional.joined(separator: " ")
        let a = command == "show" ? Announcement(keys: text, caption: caption, source: source)
                                  : Announcement(keys: nil, caption: text ?? caption, source: source)
        return a.map { .success($0) } ?? .failure(.empty)
    }

    public enum ArgumentError: Error, Equatable {
        case usage, empty, missingValue(String)
    }
}

/// Token bucket: `capacity` announcements at once, refilled at `perSecond`.
public struct RateLimiter: Sendable {
    public var capacity: Double
    public var perSecond: Double
    private var tokens: Double
    private var last: Double?

    public init(capacity: Double = 8, perSecond: Double = 4) {
        self.capacity = capacity
        self.perSecond = perSecond
        tokens = capacity
    }

    public mutating func allow(now: Double) -> Bool {
        if let last { tokens = min(capacity, tokens + (now - last) * perSecond) }
        last = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

/// A minimal MCP (Model Context Protocol) server over newline-delimited JSON-RPC: tools
/// `show_keys` and `show_caption`. `handle` takes one request line and returns the response line
/// (nil for notifications).
public struct MCPServer {
    public let version: String
    public let announce: (Announcement) -> Void

    public init(version: String, announce: @escaping (Announcement) -> Void) {
        self.version = version
        self.announce = announce
    }

    static var tools: [[String: Any]] { [
        ["name": "show_keys",
         "description": "Show keys (e.g. \"cmd+shift+p\" or \"⌘K\") with an optional caption in Keyray's on-screen keycaps, marked as agent input.",
         "inputSchema": ["type": "object", "required": ["keys"], "properties": [
             "keys": ["type": "string", "description": "Keys to show"],
             "caption": ["type": "string", "description": "What the keys do, e.g. \"npm test\""],
             "source": ["type": "string", "description": "Agent name shown in the badge"]]]],
        ["name": "show_caption",
         "description": "Show a short caption in Keyray's on-screen keycaps, marked as agent input.",
         "inputSchema": ["type": "object", "required": ["caption"], "properties": [
             "caption": ["type": "string"], "source": ["type": "string"]]]],
    ] }

    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return reply(nil, error: (-32700, "Parse error"))
        }
        let id = req["id"]
        guard let method = req["method"] as? String else { return reply(id, error: (-32600, "Invalid request")) }
        if id == nil { return nil } // notification
        let params = req["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return reply(id, result: ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                                      "capabilities": ["tools": [:]],
                                      "serverInfo": ["name": "keyray", "version": version]])
        case "ping":
            return reply(id, result: [:])
        case "tools/list":
            return reply(id, result: ["tools": Self.tools])
        case "tools/call":
            let args = params["arguments"] as? [String: Any] ?? [:]
            let a: Announcement?
            switch params["name"] as? String {
            case "show_keys": a = Announcement(keys: args["keys"] as? String, caption: args["caption"] as? String, source: args["source"] as? String)
            case "show_caption": a = Announcement(keys: nil, caption: args["caption"] as? String, source: args["source"] as? String)
            default: return reply(id, error: (-32602, "Unknown tool"))
            }
            guard let a else { return reply(id, result: text("Nothing to show: give keys or a caption.", isError: true)) }
            announce(a)
            return reply(id, result: text("Shown: \([a.keys, a.caption].compactMap { $0 }.joined(separator: " — "))", isError: false))
        default:
            return reply(id, error: (-32601, "Method not found"))
        }
    }

    private func text(_ s: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": s]], "isError": isError]
    }

    private func reply(_ id: Any?, result: Any? = nil, error: (Int, String)? = nil) -> String {
        var r: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull()]
        if let error { r["error"] = ["code": error.0, "message": error.1] } else { r["result"] = result ?? [:] }
        let data = (try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
