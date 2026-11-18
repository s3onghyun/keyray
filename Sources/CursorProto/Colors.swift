import AppKit
import CursorProtoCore

extension RGBA {
    func cg(alpha: Double? = nil) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha ?? self.alpha)
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .white
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
