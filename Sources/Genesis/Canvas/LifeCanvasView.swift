import AppKit
import QuartzCore
import SwiftUI

/// Native (layer-hosting) view that shows the world and handles zoom, panning, drawing and selection.
///
/// Cells are drawn as a bitmap (one pixel per cell) assigned to a CALayer with "nearest"
/// filtering: the GPU does the scaling, so zooming stays smooth even on huge grids.
final class LifeCanvasView: NSView {
    let model: LifeModel

    private let rootLayer = CALayer()
    private let worldLayer = CALayer()
    private let cellsLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let ghostLayer = CALayer()
    private let hoverLayer = CAShapeLayer()

    static let minZoom: CGFloat = 0.08
    static let maxZoom: CGFloat = 90

    private(set) var zoom: CGFloat = 1
    private var offset = CGPoint.zero
    private var didInitialFit = false
    /// Until the user moves the camera, every resize re-fits the world.
    private var userMovedCamera = false
    private var frameLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var trackingArea: NSTrackingArea?

    private struct CameraAnimation {
        var fromZoom: CGFloat
        var toZoom: CGFloat
        var fromCenter: CGPoint
        var toCenter: CGPoint
        var start: CFTimeInterval
        var duration: CFTimeInterval
    }
    private var cameraAnimation: CameraAnimation?

    // Already-drawn state (so only what changed gets redrawn).
    private var layoutDirty = true
    private var renderedVersion = -1
    private var renderedPlacingVersion = -1
    private var renderedWidth = -1
    private var lastPaletteID = ""
    private var lastSelection: GridRect?
    private var lastShowGrid = true
    private var lastGlow = false
    private var lastTool: Tool = .draw
    private var hoverCell: CellPoint?

    private enum DragMode {
        case none
        case pan
        case paint(alive: Bool)
        case select(anchor: CellPoint)
    }
    private var drag: DragMode = .none
    private var lastDragPoint = CGPoint.zero
    private var lastPaintCell: CellPoint?

    init(model: LifeModel) {
        self.model = model
        super.init(frame: .zero)
        layer = rootLayer
        wantsLayer = true
        setupLayers()
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupLayers() {
        let none = NSNull()
        let noActions: [String: CAAction] = [
            "position": none, "bounds": none, "frame": none, "contents": none, "path": none,
            "hidden": none, "opacity": none, "backgroundColor": none, "shadowOpacity": none,
            "shadowRadius": none, "shadowColor": none, "strokeColor": none, "fillColor": none,
            "borderColor": none, "transform": none, "sublayers": none, "onOrderIn": none, "onOrderOut": none,
        ]
        rootLayer.actions = noActions
        rootLayer.masksToBounds = true
        for l in [worldLayer, cellsLayer, gridLayer, selectionLayer, ghostLayer, hoverLayer] as [CALayer] {
            l.actions = noActions
            rootLayer.addSublayer(l)
        }
        cellsLayer.magnificationFilter = .nearest
        cellsLayer.minificationFilter = .trilinear
        cellsLayer.contentsGravity = .resize
        cellsLayer.shadowOffset = .zero
        cellsLayer.shadowOpacity = 0

        worldLayer.shadowOffset = .zero
        worldLayer.shadowRadius = 18
        worldLayer.shadowOpacity = 0.35
        worldLayer.shadowColor = CGColor(gray: 0, alpha: 1)

        gridLayer.fillColor = nil
        gridLayer.lineWidth = 1

        selectionLayer.lineWidth = 1.5
        selectionLayer.lineDashPattern = [6, 4]

        ghostLayer.magnificationFilter = .nearest
        ghostLayer.contentsGravity = .resize
        ghostLayer.opacity = 0.8
        ghostLayer.borderWidth = 1

        hoverLayer.fillColor = nil
        hoverLayer.lineWidth = 1.5
    }

    // MARK: - Lifecycle

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func focus() {
        window?.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frameLink?.invalidate()
        frameLink = nil
        guard let window else { return }
        updateBackingScale()
        let link = self.displayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        frameLink = link
        window.acceptsMouseMovedEvents = true
        DispatchQueue.main.async { [weak self] in self?.focus() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingScale()
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? 2
        for l in [rootLayer, worldLayer, cellsLayer, gridLayer, selectionLayer, ghostLayer, hoverLayer] {
            l.contentsScale = scale
        }
        gridLayer.lineWidth = 1 / scale
        layoutDirty = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let old = frame.size
        super.setFrameSize(newSize)
        if userMovedCamera {
            offset.x += (newSize.width - old.width) / 2
            offset.y += (newSize.height - old.height) / 2
        } else if newSize.width > 50 && newSize.height > 50 {
            zoomToFit(contentOnly: false, animated: false)
            didInitialFit = true
        }
        layoutDirty = true
        refresh()
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        let ts = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 : ts - lastTimestamp
        lastTimestamp = ts
        model.syncSettings()
        model.tick(dt: dt)
        advanceCameraAnimation()
        refresh()
    }

    // MARK: - Rendering

    private var gridW: Int { model.engine.width }
    private var gridH: Int { model.engine.height }

    func refresh() {
        let pal = model.palette
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if pal.id != lastPaletteID {
            lastPaletteID = pal.id
            rootLayer.backgroundColor = pal.outside.cgColor()
            worldLayer.backgroundColor = pal.background.cgColor()
            gridLayer.strokeColor = pal.grid.cgColor(alpha: pal.isLight ? 0.9 : 0.8)
            selectionLayer.strokeColor = pal.accent.cgColor()
            selectionLayer.fillColor = pal.accent.cgColor(alpha: 0.12)
            hoverLayer.strokeColor = pal.accent.cgColor(alpha: 0.9)
            ghostLayer.borderColor = pal.accent.cgColor(alpha: 0.55)
            cellsLayer.shadowColor = pal.accent.cgColor()
            renderedPlacingVersion = -1
        }

        let styleChanged = model.renderer.update(palette: pal, ageColoring: model.ageColoring, trails: model.trailLength >= 1)
        if styleChanged || renderedVersion != model.engine.version || renderedWidth != gridW {
            renderedVersion = model.engine.version
            if renderedWidth != gridW {
                renderedWidth = gridW
                layoutDirty = true
            }
            cellsLayer.contents = model.renderer.image(of: model.engine)
        }

        if renderedPlacingVersion != model.placingVersion {
            renderedPlacingVersion = model.placingVersion
            if let p = model.placing {
                ghostLayer.contents = model.renderer.ghostImage(of: p, color: pal.isLight ? pal.stops[1] : pal.stops[0])
                ghostLayer.backgroundColor = pal.accent.cgColor(alpha: 0.10)
            } else {
                ghostLayer.contents = nil
            }
            layoutDirty = true
            updateCursor()
        }

        if model.selection != lastSelection {
            lastSelection = model.selection
            layoutDirty = true
        }
        if model.showGrid != lastShowGrid {
            lastShowGrid = model.showGrid
            layoutDirty = true
        }
        if model.glow != lastGlow {
            lastGlow = model.glow
            layoutDirty = true
        }
        if model.tool != lastTool {
            lastTool = model.tool
            layoutDirty = true
            updateCursor()
        }

        if layoutDirty { layoutLayers() }
    }

    private func layoutLayers() {
        layoutDirty = false
        let W = gridW
        let H = gridH
        let world = CGRect(x: offset.x, y: offset.y, width: CGFloat(W) * zoom, height: CGFloat(H) * zoom)
        worldLayer.frame = world
        worldLayer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: world.size), transform: nil)
        cellsLayer.frame = world

        let glowOn = model.glow && world.width <= 5000 && world.height <= 5000
        cellsLayer.shadowOpacity = glowOn ? 0.95 : 0
        cellsLayer.shadowRadius = max(2, min(14, zoom * 1.6))

        // Grid
        gridLayer.frame = bounds
        let visible = bounds.intersection(world)
        if model.showGrid && zoom >= 5 && !visible.isNull && !visible.isEmpty {
            let path = CGMutablePath()
            let x0 = max(0, Int(floor((visible.minX - offset.x) / zoom)))
            let x1 = min(W, Int(ceil((visible.maxX - offset.x) / zoom)))
            let y0 = max(0, Int(floor((visible.minY - offset.y) / zoom)))
            let y1 = min(H, Int(ceil((visible.maxY - offset.y) / zoom)))
            for i in stride(from: x0, through: x1, by: 1) {
                let x = offset.x + CGFloat(i) * zoom
                path.move(to: CGPoint(x: x, y: visible.minY))
                path.addLine(to: CGPoint(x: x, y: visible.maxY))
            }
            for j in stride(from: y0, through: y1, by: 1) {
                let y = offset.y + CGFloat(j) * zoom
                path.move(to: CGPoint(x: visible.minX, y: y))
                path.addLine(to: CGPoint(x: visible.maxX, y: y))
            }
            gridLayer.path = path
            gridLayer.opacity = Float(min(1, max(0.15, (zoom - 5) / 8)))
            gridLayer.isHidden = false
        } else {
            gridLayer.isHidden = true
            gridLayer.path = nil
        }

        // Selection
        if let sel = model.selection {
            selectionLayer.frame = bounds
            selectionLayer.path = CGPath(rect: viewRect(for: sel), transform: nil)
            selectionLayer.isHidden = false
        } else {
            selectionLayer.isHidden = true
        }

        // Preview of the pattern being placed
        if let p = model.placing, let hc = hoverCell {
            ghostLayer.frame = viewRect(for: GridRect(x: hc.x - p.width / 2, y: hc.y - p.height / 2,
                                                      width: p.width, height: p.height))
            ghostLayer.isHidden = false
        } else {
            ghostLayer.isHidden = true
        }

        // Cell under the pointer
        if model.placing == nil, let hc = hoverCell, zoom >= 4,
           model.tool == .draw || model.tool == .erase,
           hc.x >= 0, hc.y >= 0, hc.x < W, hc.y < H {
            hoverLayer.frame = bounds
            hoverLayer.path = CGPath(rect: viewRect(for: GridRect(x: hc.x, y: hc.y, width: 1, height: 1)), transform: nil)
            hoverLayer.isHidden = false
        } else {
            hoverLayer.isHidden = true
        }
    }

    // MARK: - Coordinates

    /// View-space rectangle (bottom-left origin) for a rectangle of cells.
    private func viewRect(for r: GridRect) -> CGRect {
        CGRect(x: offset.x + CGFloat(r.x) * zoom,
               y: offset.y + CGFloat(gridH - r.y - r.height) * zoom,
               width: CGFloat(r.width) * zoom,
               height: CGFloat(r.height) * zoom)
    }

    private func cell(at p: CGPoint) -> CellPoint {
        let gx = (p.x - offset.x) / zoom
        let gy = CGFloat(gridH) - (p.y - offset.y) / zoom
        return CellPoint(x: Int(floor(gx)), y: Int(floor(gy)))
    }

    private func clampCell(_ c: CellPoint) -> CellPoint {
        CellPoint(x: max(0, min(gridW - 1, c.x)), y: max(0, min(gridH - 1, c.y)))
    }

    private func point(_ e: NSEvent) -> CGPoint {
        convert(e.locationInWindow, from: nil)
    }

    // MARK: - Camera

    func zoom(by factor: CGFloat, around anchor: CGPoint? = nil) {
        cameraAnimation = nil
        userMovedCamera = true
        let a = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let newZoom = max(LifeCanvasView.minZoom, min(LifeCanvasView.maxZoom, zoom * factor))
        let k = newZoom / zoom
        offset = CGPoint(x: a.x - (a.x - offset.x) * k, y: a.y - (a.y - offset.y) * k)
        zoom = newZoom
        layoutDirty = true
    }

    func zoomToFit(contentOnly: Bool, animated: Bool = true) {
        guard bounds.width > 10, bounds.height > 10 else { return }
        let full = GridRect(x: 0, y: 0, width: gridW, height: gridH)
        var rect = full
        if contentOnly, let bb = model.engine.boundingBox() {
            rect = bb.expanded(by: max(3, max(bb.width, bb.height) / 10))
        }
        let margin: CGFloat = 36
        let zx = (bounds.width - margin * 2) / CGFloat(max(1, rect.width))
        let zy = (bounds.height - margin * 2) / CGFloat(max(1, rect.height))
        let z = max(LifeCanvasView.minZoom, min(contentOnly ? 36 : LifeCanvasView.maxZoom, min(zx, zy)))
        let center = CGPoint(x: CGFloat(rect.x) + CGFloat(rect.width) / 2,
                             y: CGFloat(gridH) - (CGFloat(rect.y) + CGFloat(rect.height) / 2))
        if animated && didInitialFit {
            userMovedCamera = true
            cameraAnimation = CameraAnimation(fromZoom: zoom, toZoom: z, fromCenter: gridCenter(),
                                              toCenter: center, start: CACurrentMediaTime(), duration: 0.45)
        } else {
            cameraAnimation = nil
            setCamera(zoom: z, center: center)
        }
    }

    /// Center of the view in grid coordinates (y pointing up).
    private func gridCenter() -> CGPoint {
        CGPoint(x: (bounds.midX - offset.x) / zoom, y: (bounds.midY - offset.y) / zoom)
    }

    private func setCamera(zoom z: CGFloat, center c: CGPoint) {
        zoom = z
        offset = CGPoint(x: bounds.midX - c.x * z, y: bounds.midY - c.y * z)
        layoutDirty = true
    }

    private func advanceCameraAnimation() {
        guard let a = cameraAnimation else { return }
        let t = min(1, (CACurrentMediaTime() - a.start) / a.duration)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        let ce = CGFloat(e)
        let z = exp(log(a.fromZoom) + (log(a.toZoom) - log(a.fromZoom)) * ce)
        let c = CGPoint(x: a.fromCenter.x + (a.toCenter.x - a.fromCenter.x) * ce,
                        y: a.fromCenter.y + (a.toCenter.y - a.fromCenter.y) * ce)
        setCamera(zoom: z, center: c)
        if t >= 1 { cameraAnimation = nil }
    }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private var currentCursor: NSCursor {
        if model.placing != nil { return .crosshair }
        switch model.tool {
        case .pan: return .openHand
        case .draw, .erase, .select: return .crosshair
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor.set()
    }

    private func updateCursor() {
        guard let window else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(p) { currentCursor.set() }
    }

    // MARK: - Mouse

    private func updateHover(_ e: NSEvent) {
        let c = cell(at: point(e))
        let inside = c.x >= 0 && c.y >= 0 && c.x < gridW && c.y < gridH
        let newHover: CellPoint? = (inside || model.placing != nil) ? c : nil
        if newHover != hoverCell {
            hoverCell = newHover
            layoutDirty = true
        }
        let modelHover: CellPoint? = inside ? c : nil
        if model.hoverCell != modelHover { model.hoverCell = modelHover }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        hoverCell = nil
        model.hoverCell = nil
        layoutDirty = true
    }

    override func mouseDown(with event: NSEvent) {
        focus()
        let p = point(event)
        lastDragPoint = p
        let c = cell(at: p)
        if model.tool == .pan || event.modifierFlags.contains(.option) {
            drag = .pan
            cameraAnimation = nil
            NSCursor.closedHand.set()
            return
        }
        if model.placing != nil {
            model.placePattern(at: c)
            drag = .none
            return
        }
        switch model.tool {
        case .draw:
            let alive = !model.engine.isAlive(c.x, c.y)
            model.beginStroke()
            drag = .paint(alive: alive)
            model.paint([c], alive: alive)
            lastPaintCell = c
        case .erase:
            model.beginStroke()
            drag = .paint(alive: false)
            model.paint([c], alive: false)
            lastPaintCell = c
        case .select:
            drag = .select(anchor: clampCell(c))
            model.selection = nil
        case .pan:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case .pan:
            userMovedCamera = true
            offset.x += p.x - lastDragPoint.x
            offset.y += p.y - lastDragPoint.y
            layoutDirty = true
        case .paint(let alive):
            let c = cell(at: p)
            if let last = lastPaintCell, last != c {
                model.paint(LifeCanvasView.line(from: last, to: c), alive: alive)
            }
            lastPaintCell = c
        case .select(let anchor):
            model.selection = GridRect(corner: anchor, clampCell(cell(at: p)))
        case .none:
            break
        }
        lastDragPoint = p
        updateHover(event)
    }

    override func mouseUp(with event: NSEvent) {
        if case .paint = drag { model.endStroke() }
        drag = .none
        lastPaintCell = nil
        currentCursor.set()
    }

    override func otherMouseDown(with event: NSEvent) {
        drag = .pan
        cameraAnimation = nil
        lastDragPoint = point(event)
        NSCursor.closedHand.set()
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let p = point(event)
        let zoomModifier = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        if event.hasPreciseScrollingDeltas && !zoomModifier {
            cameraAnimation = nil
            userMovedCamera = true
            offset.x += event.scrollingDeltaX
            offset.y -= event.scrollingDeltaY
            layoutDirty = true
        } else {
            let d = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.12
            zoom(by: exp(d), around: p)
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: max(0.2, 1 + event.magnification), around: point(event))
    }

    override func smartMagnify(with event: NSEvent) {
        zoomToFit(contentOnly: true)
    }

    static func line(from a: CellPoint, to b: CellPoint) -> [CellPoint] {
        var pts: [CellPoint] = []
        var x0 = a.x
        var y0 = a.y
        let dx = abs(b.x - x0)
        let dy = -abs(b.y - y0)
        let sx = x0 < b.x ? 1 : -1
        let sy = y0 < b.y ? 1 : -1
        var err = dx + dy
        while true {
            pts.append(CellPoint(x: x0, y: y0))
            if x0 == b.x && y0 == b.y { break }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                x0 += sx
            }
            if e2 <= dx {
                err += dx
                y0 += sy
            }
        }
        return pts
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if !event.modifierFlags.intersection([.command, .control]).isEmpty {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 49: // space
            model.togglePlay()
            return
        case 124: // →
            model.step()
            return
        case 123: // ←
            model.stepBack()
            return
        case 53: // esc
            if model.placing != nil { model.cancelPlacing() } else { model.deselect() }
            return
        case 51, 117: // backspace / forward delete
            if model.selection != nil { model.deleteSelection() }
            return
        default:
            break
        }
        guard let ch = event.charactersIgnoringModifiers?.lowercased(), !ch.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch ch {
        case "r":
            if model.placing != nil { model.rotatePlacing() } else { model.randomFill() }
        case "f":
            if model.placing != nil { model.flipPlacing() } else { model.zoomToFit() }
        case "1": model.tool = .draw
        case "2": model.tool = .erase
        case "3": model.tool = .select
        case "4": model.tool = .pan
        case "g": model.showGrid.toggle()
        case "+", "=": zoom(by: 1.4)
        case "-": zoom(by: 1 / 1.4)
        case "0": zoomToFit(contentOnly: false)
        case "]": model.faster()
        case "[": model.slower()
        case "i": model.showInspector.toggle()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let hasSelection = model.selection != nil
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        if model.placing != nil {
            add("Rotate Pattern", #selector(ctxRotate))
            add("Flip Pattern", #selector(ctxFlip))
            add("Cancel Placement", #selector(ctxCancelPlacing))
            menu.addItem(.separator())
        }
        add("Copy Selection", #selector(ctxCopy), enabled: hasSelection)
        add("Cut Selection", #selector(ctxCut), enabled: hasSelection)
        add("Paste Pattern", #selector(ctxPaste))
        menu.addItem(.separator())
        add("Clear Selection", #selector(ctxDelete), enabled: hasSelection)
        add("Clear Outside Selection", #selector(ctxClearOutside), enabled: hasSelection)
        add(hasSelection ? "Randomize Selection" : "Randomize World", #selector(ctxRandom))
        add("Deselect", #selector(ctxDeselect), enabled: hasSelection)
        menu.addItem(.separator())
        add("Zoom to Content", #selector(ctxFit))
        add("Show Whole World", #selector(ctxWorld))
        return menu
    }

    @objc private func ctxRotate() { model.rotatePlacing() }
    @objc private func ctxFlip() { model.flipPlacing() }
    @objc private func ctxCancelPlacing() { model.cancelPlacing() }
    @objc private func ctxCopy() { model.copySelection() }
    @objc private func ctxCut() { model.copySelection(cut: true) }
    @objc private func ctxPaste() { model.paste() }
    @objc private func ctxDelete() { model.deleteSelection() }
    @objc private func ctxClearOutside() { model.clearOutsideSelection() }
    @objc private func ctxRandom() { model.randomFill() }
    @objc private func ctxDeselect() { model.deselect() }
    @objc private func ctxFit() { zoomToFit(contentOnly: true) }
    @objc private func ctxWorld() { zoomToFit(contentOnly: false) }

    // MARK: - File drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURL(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = fileURL(from: sender) else { return false }
        model.loadFile(url)
        return true
    }

    private func fileURL(from info: NSDraggingInfo) -> URL? {
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                          options: [.urlReadingFileURLsOnly: true])
        return objects?.first as? URL
    }
}

/// SwiftUI → AppKit bridge.
struct LifeCanvas: NSViewRepresentable {
    let model: LifeModel

    func makeNSView(context: Context) -> LifeCanvasView {
        let view = LifeCanvasView(model: model)
        model.canvas = view
        return view
    }

    func updateNSView(_ nsView: LifeCanvasView, context: Context) {}
}
