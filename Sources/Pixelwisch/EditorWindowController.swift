import AppKit
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let original: CGImage
    private(set) var image: CGImage
    let pointSize: CGSize
    private let baseName: String

    private var version = 0
    private var effectCache: (key: String, image: CGImage)?
    private let undo = UndoManager()
    private var tempFolder: URL?
    private var statusTimer: Timer?

    var onClose: ((EditorWindowController) -> Void)?
    var onOpenFiles: (([URL]) -> Void)?

    private let canvas: CanvasView
    private let toolSeg = NSSegmentedControl()
    private let effectSeg = NSSegmentedControl()
    private let sizeSlider = NSSlider(value: 40, minValue: 6, maxValue: 220, target: nil, action: nil)
    private let strengthSlider = NSSlider(value: 22, minValue: 6, maxValue: 90, target: nil, action: nil)
    private let strengthLabel = NSTextField(labelWithString: "Stärke")
    private let statusLabel = NSTextField(labelWithString: "")

    private static let hint = "⌥ halten: Original zeigen  ·  ⇧ ziehen: Rechteck  ·  + / −: Pinselgröße  ·  1 2 3: Effekt  ·  ⌘ ziehen: Bild herausziehen"

    init(image: CGImage, pointSize: CGSize, title: String, baseName: String) {
        self.original = image
        self.image = image
        self.pointSize = pointSize
        self.baseName = baseName
        self.canvas = CanvasView(image: image, original: image, pointSize: pointSize)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self

        buildUI()
        sizeWindow()
        syncControls()
        showStatus(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    // MARK: Oberfläche

    private func symbol(_ name: String, _ label: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: label) ?? NSImage()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        toolSeg.segmentCount = 2
        toolSeg.trackingMode = .selectOne
        toolSeg.setImage(symbol("paintbrush.pointed", "Pinsel"), forSegment: 0)
        toolSeg.setImage(symbol("rectangle.dashed", "Rechteck"), forSegment: 1)
        toolSeg.setToolTip("Pinsel – über Bereiche wischen (B)", forSegment: 0)
        toolSeg.setToolTip("Rechteck aufziehen (R, oder ⇧ gedrückt halten)", forSegment: 1)
        toolSeg.target = self
        toolSeg.action = #selector(toolChanged(_:))

        effectSeg.segmentCount = 3
        effectSeg.trackingMode = .selectOne
        for (i, (label, icon, tip)) in [
            ("Verpixeln", "square.grid.3x3.fill", "Mosaik (1)"),
            ("Unscharf", "drop.fill", "Weichzeichnen (2)"),
            ("Schwärzen", "rectangle.fill", "Schwarzer Balken – am sichersten für Passwörter & Co. (3)")
        ].enumerated() {
            effectSeg.setLabel(label, forSegment: i)
            effectSeg.setImage(symbol(icon, label), forSegment: i)
            effectSeg.setImageScaling(.scaleProportionallyDown, forSegment: i)
            effectSeg.setToolTip(tip, forSegment: i)
        }
        effectSeg.target = self
        effectSeg.action = #selector(effectChanged(_:))

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged(_:))
        sizeSlider.toolTip = "Pinselgröße (+ / −)"
        strengthSlider.target = self
        strengthSlider.action = #selector(strengthChanged(_:))
        strengthSlider.toolTip = "Größe der Pixelblöcke bzw. Stärke der Unschärfe"
        sizeSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        strengthSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let auto = NSPopUpButton(frame: .zero, pullsDown: true)
        auto.addItem(withTitle: "Automatisch")
        auto.item(at: 0)?.image = symbol("wand.and.stars", "Automatisch")
        for (title, sel) in [
            ("Gesichter unkenntlich machen", #selector(detectFaces(_:))),
            ("Sensible Daten (E-Mail, Telefon, IBAN, Tokens …)", #selector(detectSensitive(_:))),
            ("Allen Text unkenntlich machen", #selector(detectAllText(_:)))
        ] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            auto.menu?.addItem(item)
        }
        auto.toolTip = "Findet Gesichter oder Text automatisch (läuft lokal auf dem Mac)"

        let copyButton = NSButton(image: symbol("doc.on.doc", "Kopieren"), target: self, action: #selector(copyImage(_:)))
        copyButton.toolTip = "In die Zwischenablage kopieren (⌘C)"
        let saveButton = NSButton(image: symbol("square.and.arrow.down", "Sichern"), target: self, action: #selector(saveImage(_:)))
        saveButton.toolTip = "Als PNG oder JPEG sichern (⌘S)"
        let doneButton = NSButton(title: "Fertig", target: self, action: #selector(copyAndClose(_:)))
        doneButton.keyEquivalent = "\r"
        doneButton.keyEquivalentModifierMask = [.command]
        doneButton.toolTip = "Kopieren und Fenster schließen (⌘↩)"

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        bar.translatesAutoresizingMaskIntoConstraints = false
        for v in [toolSeg, effectSeg, NSTextField(labelWithString: "Größe"), sizeSlider, strengthLabel, strengthSlider] as [NSView] {
            bar.addView(v, in: .leading)
        }
        for v in [auto, copyButton, saveButton, doneButton] as [NSView] {
            bar.addView(v, in: .trailing)
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.effectProvider = { [weak self] in self?.currentEffectImage() }
        canvas.onCommit = { [weak self] mask, fx in self?.apply(mask: mask, effect: fx) }
        canvas.onSettingsChangedByKeyboard = { [weak self] in self?.syncControls() }
        canvas.onDropFiles = { [weak self] urls in self?.onOpenFiles?(urls) }
        canvas.dragFileProvider = { [weak self] in self?.writeTempFile() }

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        content.addSubview(bar)
        content.addSubview(separator)
        content.addSubview(canvas)
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: separator.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6)
        ])
    }

    private func sizeWindow() {
        guard let window else { return }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let chrome: CGFloat = 52 + 26 + 40
        let w = min(max(pointSize.width + 40, 920), screen.width * 0.92)
        let h = min(max(pointSize.height + chrome, 460), screen.height * 0.92)
        window.contentMinSize = NSSize(width: 900, height: 400)
        window.setContentSize(NSSize(width: w, height: h))
        window.center()
    }

    func present() {
        showWindow(nil)
        window?.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func syncControls() {
        let s = Settings.shared
        toolSeg.selectedSegment = s.tool.rawValue
        effectSeg.selectedSegment = s.effect.rawValue
        sizeSlider.doubleValue = s.brushSize
        strengthSlider.doubleValue = s.strength
        strengthSlider.isEnabled = s.effect != .blackout
        strengthLabel.textColor = s.effect == .blackout ? .tertiaryLabelColor : .labelColor
        canvas.needsDisplay = true
    }

    private func showStatus(_ text: String?, sticky: Bool = false) {
        statusTimer?.invalidate()
        statusLabel.stringValue = text ?? Self.hint
        statusLabel.textColor = text == nil ? .tertiaryLabelColor : .secondaryLabelColor
        guard text != nil, !sticky else { return }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.showStatus(nil)
        }
    }

    // MARK: Einstellungen

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        Settings.shared.tool = Tool(rawValue: sender.selectedSegment) ?? .brush
        syncControls()
    }

    @objc private func effectChanged(_ sender: NSSegmentedControl) {
        Settings.shared.effect = Effect(rawValue: sender.selectedSegment) ?? .pixelate
        syncControls()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        Settings.shared.brushSize = sender.doubleValue
        canvas.needsDisplay = true
    }

    @objc private func strengthChanged(_ sender: NSSlider) {
        Settings.shared.strength = sender.doubleValue.rounded()
    }

    // MARK: Bearbeiten

    private func currentEffectImage() -> CGImage? {
        let s = Settings.shared
        let key = "\(s.effect.rawValue)|\(Int(s.strength))|\(version)"
        if let cache = effectCache, cache.key == key { return cache.image }
        guard let fx = EffectRenderer.render(s.effect, strength: s.strength, on: image) else { return nil }
        effectCache = (key, fx)
        return fx
    }

    private func apply(mask: CGImage, effect: CGImage) {
        guard let result = Compositor.composite(base: image, effect: effect, mask: mask) else { return }
        setImage(result, actionName: Settings.shared.effect.actionName)
    }

    private func setImage(_ newImage: CGImage, actionName: String) {
        let previous = image
        undo.registerUndo(withTarget: self) { target in
            target.setImage(previous, actionName: actionName)
        }
        undo.setActionName(actionName)
        image = newImage
        version += 1
        effectCache = nil
        canvas.image = newImage
    }

    private func runDetection(_ kind: Detector.Kind) {
        showStatus(kind.searching, sticky: true)
        Detector.detect(kind, in: image) { [weak self] rects in
            guard let self else { return }
            guard !rects.isEmpty else {
                self.showStatus(kind.nothingFound)
                return
            }
            guard let mask = Compositor.mask(width: self.image.width, height: self.image.height, rects: rects),
                  let fx = self.currentEffectImage() else { return }
            self.apply(mask: mask, effect: fx)
            self.showStatus(kind.found(rects.count) + "  (⌘Z macht es rückgängig)")
        }
    }

    @objc func detectFaces(_ sender: Any?) { runDetection(.faces) }
    @objc func detectSensitive(_ sender: Any?) { runDetection(.sensitive) }
    @objc func detectAllText(_ sender: Any?) { runDetection(.allText) }

    // MARK: Ausgabe

    @objc(copy:) func copyImage(_ sender: Any?) {
        Clipboard.write(image, pointSize: pointSize)
        showStatus("In die Zwischenablage kopiert ✓")
    }

    @objc func copyAndClose(_ sender: Any?) {
        Clipboard.write(image, pointSize: pointSize)
        window?.performClose(nil)
    }

    @objc func saveImage(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = baseName + ".png"
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.message = "Tipp: Endung .jpg wählen für kleinere Dateien."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let type = UTType(filenameExtension: url.pathExtension) ?? .png
            if ImageFiles.write(self.image, pointSize: self.pointSize, to: url, type: type == .jpeg ? .jpeg : .png) {
                self.showStatus("Gesichert: \(url.lastPathComponent) ✓")
            } else {
                NSSound.beep()
                self.showStatus("Konnte die Datei nicht sichern.")
            }
        }
    }

    private func writeTempFile() -> URL? {
        let folder = tempFolder ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Pixelwisch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        tempFolder = folder
        let url = folder.appendingPathComponent(baseName + ".png")
        return ImageFiles.write(image, pointSize: pointSize, to: url, type: .png) ? url : nil
    }

    // MARK: NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }

    func windowDidBecomeKey(_ notification: Notification) { syncControls() }

    func windowDidResignKey(_ notification: Notification) { canvas.showOriginal = false }

    func windowWillClose(_ notification: Notification) {
        statusTimer?.invalidate()
        if let tempFolder { try? FileManager.default.removeItem(at: tempFolder) }
        onClose?(self)
    }
}
