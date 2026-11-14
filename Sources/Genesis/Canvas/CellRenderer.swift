import Foundation
import CoreGraphics

/// Turns the engine state into images (one pixel per cell) using the palette's color tables.
final class CellRenderer {
    struct Style: Hashable {
        var paletteID: String
        var ageColoring: Bool
        var trails: Bool
    }

    private(set) var style: Style?
    private var aliveLUT = [UInt32](repeating: 0, count: 256)
    private var trailLUT = [UInt32](repeating: 0, count: 256)
    private var pixels: [UInt32] = []
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

    /// Updates the style; returns true if it changed.
    @discardableResult
    func update(palette: Palette, ageColoring: Bool, trails: Bool) -> Bool {
        let s = Style(paletteID: palette.id, ageColoring: ageColoring, trails: trails)
        guard s != style else { return false }
        style = s
        let luts = palette.makeLUTs(ageColoring: ageColoring, trailsEnabled: trails)
        aliveLUT = luts.alive
        trailLUT = luts.trail
        return true
    }

    /// Image of the whole grid (or part of it). Dead cells are transparent.
    func image(of engine: LifeEngine, rect: GridRect? = nil) -> CGImage? {
        let r = (rect ?? GridRect(x: 0, y: 0, width: engine.width, height: engine.height))
            .clamped(width: engine.width, height: engine.height)
        guard !r.isEmpty else { return nil }
        let count = r.width * r.height
        if pixels.count != count {
            pixels = [UInt32](repeating: 0, count: count)
        }
        let w = engine.width
        let cells = UnsafePointer(engine.cells)
        let age = UnsafePointer(engine.age)
        let trail = UnsafePointer(engine.trail)
        let rows = r.height
        let cols = r.width
        let chunks = count > 65_536 ? max(1, min(rows, ProcessInfo.processInfo.activeProcessorCount * 2)) : 1

        aliveLUT.withUnsafeBufferPointer { la in
            trailLUT.withUnsafeBufferPointer { lt in
                pixels.withUnsafeMutableBufferPointer { px in
                    let a = la.baseAddress!
                    let t = lt.baseAddress!
                    let out = px.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                        let y0 = ci * rows / chunks
                        let y1 = (ci + 1) * rows / chunks
                        for ry in y0..<y1 {
                            let src = (r.y + ry) * w + r.x
                            let dst = out + ry * cols
                            for rx in 0..<cols {
                                let i = src + rx
                                dst[rx] = cells[i] != 0 ? a[Int(age[i])] : t[Int(trail[i])]
                            }
                        }
                    }
                }
            }
        }
        return makeImage(width: cols, height: rows)
    }

    /// Single-color image of a pattern (placement preview).
    func ghostImage(of pattern: Pattern, color: RGB) -> CGImage? {
        guard pattern.width > 0, pattern.height > 0 else { return nil }
        let count = pattern.width * pattern.height
        pixels = [UInt32](repeating: 0, count: count)
        let on = color.pixel()
        for c in pattern.cells where c.x >= 0 && c.y >= 0 && c.x < pattern.width && c.y < pattern.height {
            pixels[c.y * pattern.width + c.x] = on
        }
        return makeImage(width: pattern.width, height: pattern.height)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: colorSpace,
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
