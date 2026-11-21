import AppKit
import ScreenCaptureKit

/// The README images come from here (scripts/screenshots.sh has the exact commands). For example
///
///     Genesis --snapshot rules.png --grid 256 --symmetry quad --density 0.5 --rule B3678/S34678
///     Genesis --snapshot gun.png --pattern gosper --palette ember --zoom 0.7 --frames 30
///
/// sets the world up, runs it, saves a PNG of the window and quits. Other options: --seed,
/// --generations, --size 1400x880, --inspector on|off, --dark. With --frames N it saves N
/// consecutive generations of the canvas alone (gun-000.png, gun-001.png, ...). Soups use a fixed
/// seed, so the same options give the same picture. The window is captured as content of this
/// process, which needs no Screen Recording permission.
@available(macOS 14.4, *)
struct Snapshot {
    var output: URL
    var pattern: String?
    var grid: Int?
    var symmetry: Symmetry?
    var density: Double?
    var seed: UInt64 = 1
    var rule: Rule?
    var palette: String?
    var generations = 0
    var zoom: CGFloat = 1
    var size = CGSize(width: 1400, height: 880)
    var inspector: Bool?
    var dark = false
    var frames = 0

    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let path = value("--snapshot") else { return nil }
        output = URL(fileURLWithPath: path)
        pattern = value("--pattern")
        grid = value("--grid").flatMap(Int.init)
        symmetry = value("--symmetry").flatMap(Symmetry.init)
        density = value("--density").flatMap(Double.init)
        seed = value("--seed").flatMap { UInt64($0) } ?? 1
        rule = value("--rule").flatMap(Rule.init)
        palette = value("--palette")
        generations = value("--generations").flatMap(Int.init) ?? 0
        zoom = value("--zoom").flatMap(Double.init).map { CGFloat($0) } ?? 1
        if let s = value("--size")?.split(separator: "x").compactMap({ Double($0) }), s.count == 2 {
            size = CGSize(width: s[0], height: s[1])
        }
        inspector = value("--inspector").map { $0 == "on" }
        dark = arguments.contains("--dark")
        frames = value("--frames").flatMap(Int.init) ?? 0
    }

    @MainActor
    func run() async {
        let model = LifeModel.shared
        while model.canvas?.window == nil { try? await Task.sleep(for: .milliseconds(50)) }
        guard let window = model.canvas?.window, let canvas = model.canvas else { return }
        if dark { NSApp.appearance = NSAppearance(named: .darkAqua) }
        window.setContentSize(size)
        window.center()
        if let inspector { model.showInspector = inspector }
        if let palette { model.paletteID = palette }
        model.autoPause = false
        try? await Task.sleep(for: .milliseconds(500))

        if let name = pattern, let item = PatternLibrary.items.first(where: { $0.id == name }) {
            model.loadPattern(item.pattern, name: item.name)
            if let rule { model.setRule(rule) }
        } else {
            if let grid { model.gridSize = grid }
            if let symmetry { model.symmetry = symmetry }
            if let density { model.density = density }
            if let rule { model.setRule(rule) }
            model.randomFill(seed: seed)
        }
        model.syncSettings()

        do {
            if frames > 0 {
                // Framed on the starting pattern, so the camera doesn't follow what it sends away.
                frame(canvas)
                for _ in 0..<generations { model.engine.step() }
                model.pause()
                try? await Task.sleep(for: .seconds(4))
                let base = output.deletingPathExtension().path
                for i in 0..<frames {
                    let url = URL(fileURLWithPath: base + String(format: "-%03d.png", i))
                    try await capture(window, canvasOnly: true, to: url)
                    model.step()
                    try? await Task.sleep(for: .milliseconds(150))
                }
            } else {
                for _ in 0..<generations { model.engine.step() }
                model.play()
                try? await Task.sleep(for: .seconds(3.5))
                frame(canvas)
                try? await Task.sleep(for: .milliseconds(200))
                try await capture(window, canvasOnly: false, to: output)
            }
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            exit(1)
        }
        NSApp.terminate(nil)
    }

    @MainActor
    private func frame(_ canvas: LifeCanvasView) {
        canvas.zoomToFit(contentOnly: pattern != nil, animated: false)
        // Zooming out around the top-left corner leaves room for whatever the pattern sends
        // down and to the right (the gun's gliders).
        if zoom != 1 { canvas.zoom(by: zoom, around: CGPoint(x: 0, y: canvas.bounds.height)) }
    }

    @MainActor
    private func capture(_ window: NSWindow, canvasOnly: Bool, to url: URL) async throws {
        let content = try await SCShareableContent.currentProcess
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        if canvasOnly, let canvas = LifeModel.shared.canvas {
            // The canvas without the toolbar above it and the dock floating over its bottom edge.
            var rect = canvas.convert(canvas.bounds, to: nil).intersection(window.contentLayoutRect)
            rect.origin.y += 84
            rect.size.height -= 84 + 16
            let flipped = CGRect(x: rect.minX * scale, y: (window.frame.height - rect.maxY) * scale,
                                 width: rect.width * scale, height: rect.height * scale)
            if let cropped = image.cropping(to: flipped.integral) { image = cropped }
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
