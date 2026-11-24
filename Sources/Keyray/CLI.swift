import AppKit
import KeyrayCore

/// `keyray show|caption|mcp`: the app binary run as a command (usually through a symlink named
/// `keyray`). It hands announcements to the running app as a per-user distributed notification
/// (local only, no network port), or opens a `keyray://` URL to launch the app first.
enum CLI {
    static let commands: Set<String> = ["show", "caption", "mcp", "help", "--help", "-h"]

    static let usage = """
    usage: keyray show <keys> [--caption <text>] [--source <agent-name>]
           keyray caption <text> [--source <agent-name>]
           keyray mcp      MCP server on stdio (tools: show_keys, show_caption)
    keys: "⌘K" as shown, or words like "cmd+shift+p". Limits: keys \(Announcement.maxKeys), caption \
    \(Announcement.maxCaption), source \(Announcement.maxSource) characters.
    """

    static func run(_ args: [String]) -> Int32 {
        switch args.first {
        case "mcp":
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let server = MCPServer(version: version) { send($0) }
            while let line = readLine() {
                if let out = server.handle(line) { print(out); fflush(stdout) }
            }
            return 0
        case "show", "caption":
            switch Announcement.parse(arguments: args) {
            case .success(let a): return send(a) ? 0 : 1
            case .failure(.missingValue(let flag)): return fail("\(flag) needs a value")
            case .failure(.empty): return fail("nothing to show")
            case .failure(.usage): return fail(usage)
            }
        default:
            print(usage)
            return args.first == "help" || args.first == "--help" || args.first == "-h" ? 0 : 2
        }
    }

    @discardableResult
    static func send(_ a: Announcement) -> Bool {
        let id = Bundle.main.bundleIdentifier ?? "com.s3onghyun.keyray"
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            return NSWorkspace.shared.open(a.url)
        }
        DistributedNotificationCenter.default().postNotificationName(
            .init(Announcement.notificationName), object: a.json, userInfo: nil, deliverImmediately: true)
        return true
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("keyray: \(message)\n".utf8))
        return 2
    }
}
