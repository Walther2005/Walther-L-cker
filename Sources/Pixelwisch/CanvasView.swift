import AppKit
import UniformTypeIdentifiers

/// Zeigt das Bild und nimmt Pinselstriche bzw. Rechtecke entgegen.
/// Koordinaten: Ursprung unten links (wie Core Graphics und Vision).
final class CanvasView: NSView, NSDraggingSource {
    var image: CGImage { didSet { needsDisplay = true } }
    let original: CGImage
    let pointSize: CGSize

    var showOriginal = false {
        didSet { if oldValue != showOriginal { needsDisplay = true } }
    }

    /// Liefert das fertig berechnete Effektbild für den aktuellen Zustand.
    var effectProvider: (() -> CGImage?)?
    /// Wird nach jedem Strich mit Maske und Effektbild aufgerufen.
    var onCommit: ((CGImage, CGImage) -> Void)?
    var onSettingsChangedByKeyboard: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    /// Schreibt das aktuelle Bild in eine Datei, die man aus dem Fenster ziehen kann.
    var dragFileProvider: (() -> URL?)?

    private var maskContext: CGContext?
    private var liveEffect: CGImage?
    private var lastPoint: CGPoint?
    private var rectStart: CGPoint?
    private var rectCurrent: CGPoint?
    private var mouseLocation: CGPoint?
    private var hasPainted = false
    private var trackingArea: NSTrackingArea?

    init(image: CGImage, original: CGImage, pointSize: CGSize) {
        self.image = image
        self.original = original
        self.pointSize = pointSize
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometrie

    /// Bildfläche im View – eingepasst, nie größer als die natürliche Größe.
    var imageRect: CGRect {
        let avail = bounds.insetBy(dx: 20, dy: 20)
        guard avail.width > 0, avail.height > 0, pointSize.width > 0, pointSize.height > 0 else { return .zero }
        let s = min(1, avail.width / pointSize.width, avail.height / pointSize.height)
        let w = (pointSize.width * s).rounded()
        let h = (pointSize.height * s).rounded()
        return CGRect(x: (bounds.midX - w / 2).rounded(), y: (bounds.midY - h / 2).rounded(), width: w, height: h)
    }

    private var viewToImage: CGFloat { CGFloat(image.width) / max(imageRect.width, 1) }

    private func imagePoint(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: (p.x - r.minX) * viewToImage, y: (p.y - r.minY) * viewToImage)
    }

    private func viewRect(fromImage r: CGRect) -> CGRect {
        let ir = imageRect, s = 1 / viewToImage
        return CGRect(x: ir.minX + r.minX * s, y: ir.minY + r.minY * s, width: r.width * s, height: r.height * s)
    }

    private var brushPixels: CGFloat { CGFloat(Settings.shared.brushSize) * viewToImage }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    // MARK: Zeichnen

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()

        let r = imageRect
        guard r.width > 0 else { return }
        ctx.interpolationQuality = .high

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 14, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.draw(showOriginal ? original : image, in: r)
        ctx.restoreGState()

        // Live-Vorschau des aktuellen Strichs.
        if !showOriginal, let mc = maskContext, let fx = liveEffect, let mask = mc.makeImage() {
            ctx.saveGState()
            ctx.clip(to: r, mask: mask)
            ctx.draw(fx, in: r)
            ctx.restoreGState()
        }

        if let a = rectStart, let b = rectCurrent {
            let vr = viewRect(fromImage: CGRect(p1: a, p2: b))
            ctx.saveGState()
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            ctx.stroke(vr.insetBy(dx: -0.5, dy: -0.5))
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            ctx.stroke(vr.insetBy(dx: -0.5, dy: -0.5))
            ctx.restoreGState()
        }

        if showOriginal {
            drawBadge("Original (⌥ loslassen)", in: r)
        } else if Settings.shared.tool == .brush, rectStart == nil, let m = mouseLocation, r.contains(m) {
            let d = CGFloat(Settings.shared.brushSize)
            let circle = CGRect(x: m.x - d / 2, y: m.y - d / 2, width: d, height: d)
            ctx.saveGState()
            ctx.setLineWidth(3)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.strokeEllipse(in: circle)
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.strokeEllipse(in: circle)
            ctx.restoreGState()
        }
    }

    private func drawBadge(_ text: String, in r: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        let box = CGRect(x: r.minX + 10, y: r.maxY - size.height - 18, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        s.draw(at: CGPoint(x: box.minX + 8, y: box.minY + 4))
    }

    private func invalidateCursor(oldLocation: CGPoint?) {
        let d = CGFloat(Settings.shared.brushSize) + 10
        for p in [oldLocation, mouseLocation].compactMap({ $0 }) {
            setNeedsDisplay(CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
        }
    }

    // MARK: Maus

    override func mouseMoved(with event: NSEvent) {
        let old = mouseLocation
        mouseLocation = convert(event.locationInWindow, from: nil)
        invalidateCursor(oldLocation: old)
    }

    override func mouseExited(with event: NSEvent) {
        let old = mouseLocation
        mouseLocation = nil
        invalidateCursor(oldLocation: old)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.command) {
            beginImageDrag(event)
            return
        }

        guard let fx = effectProvider?(),
              let mc = Compositor.makeMask(width: image.width, height: image.height) else { return }
        liveEffect = fx
        maskContext = mc
        hasPainted = false

        let ip = imagePoint(p)
        if Settings.shared.tool == .rect || event.modifierFlags.contains(.shift) {
            rectStart = ip
            rectCurrent = ip
        } else {
            lastPoint = ip
            let d = brushPixels
            mc.fillEllipse(in: CGRect(x: ip.x - d / 2, y: ip.y - d / 2, width: d, height: d))
            hasPainted = true
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mc = maskContext else { return }
        let p = convert(event.locationInWindow, from: nil)
        mouseLocation = p
        let ip = imagePoint(p)

        if let start = rectStart {
            rectCurrent = ip
            let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let rect = CGRect(p1: start, p2: ip).intersection(full)
            mc.setFillColor(gray: 0, alpha: 1)
            mc.fill(full)
            mc.setFillColor(gray: 1, alpha: 1)
            if !rect.isNull { mc.fill(rect) }
            hasPainted = !rect.isNull && rect.width >= 2 && rect.height >= 2
        } else if let last = lastPoint {
            mc.setLineWidth(brushPixels)
            mc.setLineCap(.round)
            mc.setLineJoin(.round)
            mc.move(to: last)
            mc.addLine(to: ip)
            mc.strokePath()
            lastPoint = ip
            hasPainted = true
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let mc = maskContext, let fx = liveEffect, hasPainted, let mask = mc.makeImage() {
            onCommit?(mask, fx)
        }
        maskContext = nil
        liveEffect = nil
        lastPoint = nil
        rectStart = nil
        rectCurrent = nil
        hasPainted = false
        needsDisplay = true
    }

    // MARK: Tastatur

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control])
        let chars = (event.characters ?? "") + (event.charactersIgnoringModifiers ?? "")
        guard mods.isEmpty, let ch = chars.lowercased().first else {
            super.keyDown(with: event)
            return
        }
        let s = Settings.shared
        switch ch {
        case "+", "=", "]": s.brushSize = min(220, s.brushSize + 6)
        case "-", "[": s.brushSize = max(6, s.brushSize - 6)
        case "b", "p": s.tool = .brush
        case "r": s.tool = .rect
        case "1": s.effect = .pixelate
        case "2": s.effect = .blur
        case "3": s.effect = .blackout
        default:
            super.keyDown(with: event)
            return
        }
        onSettingsChangedByKeyboard?()
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        showOriginal = event.modifierFlags.contains(.option)
        super.flagsChanged(with: event)
    }

    // MARK: Bild herausziehen (⌘-Ziehen)

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func beginImageDrag(_ event: NSEvent) {
        guard let url = dragFileProvider?() else { return }
        let p = convert(event.locationInWindow, from: nil)
        let r = imageRect
        let s = min(1, 260 / max(r.width, r.height, 1))
        let size = CGSize(width: r.width * s, height: r.height * s)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2,
                                     width: size.width, height: size.height),
                              contents: NSImage(cgImage: image, size: size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: Bilder hineinziehen

    private func droppedImageURLs(_ info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if (sender.draggingSource as? CanvasView) === self { return [] }
        return droppedImageURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if (sender.draggingSource as? CanvasView) === self { return false }
        let urls = droppedImageURLs(sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }
}

extension CGRect {
    init(p1: CGPoint, p2: CGPoint) {
        self.init(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
    }
}
