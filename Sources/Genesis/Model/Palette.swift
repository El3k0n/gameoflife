import SwiftUI
import CoreGraphics

/// RGB color in [0, 1].
struct RGB: Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha))
    }

    /// Premultiplied BGRA pixel (0xAARRGGBB, little-endian).
    func pixel(alpha: Double = 1) -> UInt32 {
        let a = max(0, min(1, alpha))
        let rr = UInt32((r * a * 255).rounded())
        let gg = UInt32((g * a * 255).rounded())
        let bb = UInt32((b * a * 255).rounded())
        let aa = UInt32((a * 255).rounded())
        return (aa << 24) | (rr << 16) | (gg << 8) | bb
    }
}

struct Palette: Identifiable, Hashable {
    let id: String
    let name: String
    /// Background of dead cells inside the grid.
    let background: RGB
    /// Background outside the grid.
    let outside: RGB
    /// Grid lines.
    let grid: RGB
    /// Gradient from newborn cells to the oldest ones.
    let stops: [RGB]
    /// Trail color of dead cells.
    let trail: RGB
    let isLight: Bool

    var accent: RGB { stops.count > 1 ? stops[1] : stops[0] }

    func gradientColor(_ t: Double) -> RGB {
        guard stops.count > 1 else { return stops.first ?? RGB(0xFFFFFF) }
        let x = max(0, min(1, t)) * Double(stops.count - 1)
        let i = min(stops.count - 2, Int(x))
        return stops[i].mix(stops[i + 1], x - Double(i))
    }

    var swiftUIGradient: LinearGradient {
        LinearGradient(colors: stops.map { $0.color }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Lookup tables age → pixel and trail → pixel.
    func makeLUTs(ageColoring: Bool, trailsEnabled: Bool) -> (alive: [UInt32], trail: [UInt32]) {
        var alive = [UInt32](repeating: 0, count: 256)
        var trailLUT = [UInt32](repeating: 0, count: 256)
        let maxAge = log(110.0)
        for a in 0..<256 {
            if ageColoring {
                let t = a <= 1 ? 0 : min(1, log(Double(a)) / maxAge)
                alive[a] = gradientColor(t).pixel()
            } else {
                alive[a] = accent.pixel()
            }
            if trailsEnabled && a > 0 {
                let f = Double(a) / 255
                trailLUT[a] = trail.pixel(alpha: pow(f, 1.6) * (isLight ? 0.45 : 0.62))
            }
        }
        return (alive, trailLUT)
    }

    static let all: [Palette] = [
        Palette(id: "bio", name: "Bioluminescence",
                background: RGB(0x060A14), outside: RGB(0x020409), grid: RGB(0x1C2A44),
                stops: [RGB(0xE6FFFB), RGB(0x3CF2D0), RGB(0x1E90FF), RGB(0x6A3DF0), RGB(0x3B1E8F)],
                trail: RGB(0x1F5BFF), isLight: false),
        Palette(id: "ember", name: "Ember",
                background: RGB(0x0D0707), outside: RGB(0x050202), grid: RGB(0x3A1F1A),
                stops: [RGB(0xFFF6CF), RGB(0xFFC04D), RGB(0xFF6A3D), RGB(0xC2185B), RGB(0x5E0B3A)],
                trail: RGB(0xFF3D00), isLight: false),
        Palette(id: "aurora", name: "Aurora",
                background: RGB(0x04100E), outside: RGB(0x010605), grid: RGB(0x173A33),
                stops: [RGB(0xF0FFC2), RGB(0x6CF29A), RGB(0x1CC7B6), RGB(0x4E6BEB), RGB(0x7B3FD6)],
                trail: RGB(0x22D3A0), isLight: false),
        Palette(id: "synth", name: "Synthwave",
                background: RGB(0x130027), outside: RGB(0x08000F), grid: RGB(0x3A1460),
                stops: [RGB(0xFFFFFF), RGB(0xFF71CE), RGB(0xB967FF), RGB(0x01CDFE), RGB(0x05FFA1)],
                trail: RGB(0xFF00A0), isLight: false),
        Palette(id: "matrix", name: "Terminal",
                background: RGB(0x000A02), outside: RGB(0x000300), grid: RGB(0x0E2A12),
                stops: [RGB(0xD8FFD9), RGB(0x2CFF5A), RGB(0x00B32C), RGB(0x006B1A), RGB(0x003D0F)],
                trail: RGB(0x00FF41), isLight: false),
        Palette(id: "ink", name: "Ink & Paper",
                background: RGB(0xF5F1E8), outside: RGB(0xE4DED1), grid: RGB(0xD6CFBF),
                stops: [RGB(0xC0392B), RGB(0x1F2A44), RGB(0x2E4A7D), RGB(0x4F7CAC), RGB(0x7FA7C9)],
                trail: RGB(0xE5A44A), isLight: true),
        Palette(id: "mono", name: "Monochrome",
                background: RGB(0x0A0A0A), outside: RGB(0x000000), grid: RGB(0x262626),
                stops: [RGB(0xFFFFFF), RGB(0xF2F2F2), RGB(0xBDBDBD), RGB(0x8A8A8A)],
                trail: RGB(0x7A7A7A), isLight: false),
    ]

    static let `default` = all[0]
}
