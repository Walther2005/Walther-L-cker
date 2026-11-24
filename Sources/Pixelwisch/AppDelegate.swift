import AppKit
import Carbon
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private var editors: [EditorWindowController] = []
    private var hotKey: HotKey?
    private var captureRunning = false

    private static let hotKeyLabel = "⌃⌥⌘P"

    // MARK: Start

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_P),
                        modifiers: UInt32(cmdKey | optionKey | controlKey)) { [weak self] in
            self?.captureRegion(nil)
        }

        if !Settings.shared.welcomeShown {
            Settings.shared.welcomeShown = true
            DispatchQueue.main.async { self.showHelp(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Klick aufs Dock-Symbol ohne offenes Fenster → gleich neuer Screenshot.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { captureRegion(nil) }
        return true
    }

    /// Bilder aufs Dock-Symbol ziehen oder „Öffnen mit …“.
    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls: urls)
    }

    // MARK: Menüs

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = target
        return item
    }

    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item("Über Pixelwisch", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(item("Kurzbefehle & Tipps …", #selector(showHelp(_:)), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Pixelwisch ausblenden", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Pixelwisch beenden", #selector(NSApplication.terminate(_:)), "q"))
        addSubmenu(appMenu, title: "Pixelwisch", to: main)

        let file = NSMenu(title: "Ablage")
        file.addItem(item("Bereich aufnehmen", #selector(captureRegion(_:)), "n", target: self))
        file.addItem(item("Fenster aufnehmen", #selector(captureWindow(_:)), "n", [.command, .shift], target: self))
        file.addItem(item("Ganzen Bildschirm aufnehmen", #selector(captureScreen(_:)), target: self))
        file.addItem(item("Bildschirm in 5 Sekunden aufnehmen", #selector(captureTimed(_:)), target: self))
        file.addItem(.separator())
        file.addItem(item("Bild öffnen …", #selector(openDocument(_:)), "o", target: self))
        file.addItem(item("Bild aus Zwischenablage", #selector(pasteImage(_:)), target: self))
        file.addItem(.separator())
        file.addItem(item("Sichern …", #selector(EditorWindowController.saveImage(_:)), "s"))
        file.addItem(item("Kopieren & schließen", #selector(EditorWindowController.copyAndClose(_:)), "\r"))
        file.addItem(item("Fenster schließen", #selector(NSWindow.performClose(_:)), "w"))
        addSubmenu(file, title: "Ablage", to: main)

        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(item("Widerrufen", Selector(("undo:")), "z"))
        edit.addItem(item("Wiederholen", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Kopieren", #selector(EditorWindowController.copyImage(_:)), "c"))
        edit.addItem(item("Einfügen", #selector(pasteImage(_:)), "v", target: self))
        edit.addItem(.separator())
        edit.addItem(item("Gesichter unkenntlich machen", #selector(EditorWindowController.detectFaces(_:)), "f", [.command, .shift]))
        edit.addItem(item("Sensible Daten unkenntlich machen", #selector(EditorWindowController.detectSensitive(_:)), "d", [.command, .shift]))
        edit.addItem(item("Allen Text unkenntlich machen", #selector(EditorWindowController.detectAllText(_:)), "t", [.command, .shift]))
        addSubmenu(edit, title: "Bearbeiten", to: main)

        let window = NSMenu(title: "Fenster")
        window.addItem(item("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoomen", #selector(NSWindow.performZoom(_:))))
        addSubmenu(window, title: "Fenster", to: main)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ menu: NSMenu, title: String, to main: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Pixelwisch")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Pixelwisch – Screenshot: \(Self.hotKeyLabel)"

        let menu = NSMenu()
        let region = self.item("Bereich aufnehmen  (\(Self.hotKeyLabel))", #selector(captureRegion(_:)), target: self)
        menu.addItem(region)
        menu.addItem(self.item("Fenster aufnehmen", #selector(captureWindow(_:)), target: self))
        menu.addItem(self.item("Ganzen Bildschirm aufnehmen", #selector(captureScreen(_:)), target: self))
        menu.addItem(self.item("Bildschirm in 5 Sekunden", #selector(captureTimed(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(self.item("Bild öffnen …", #selector(openDocument(_:)), target: self))
        menu.addItem(self.item("Bild aus Zwischenablage", #selector(pasteImage(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(self.item("Kurzbefehle & Tipps …", #selector(showHelp(_:)), target: self))
        menu.addItem(self.item("Pixelwisch beenden", #selector(NSApplication.terminate(_:)), "q"))
        item.menu = menu
        statusItem = item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(pasteImage(_:)) {
            return NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
        }
        return true
    }

    // MARK: Aufnehmen

    private enum CaptureMode { case region, window, screen, timed }

    @objc func captureRegion(_ sender: Any?) { capture(.region) }
    @objc func captureWindow(_ sender: Any?) { capture(.window) }
    @objc func captureScreen(_ sender: Any?) { capture(.screen) }
    @objc func captureTimed(_ sender: Any?) { capture(.timed) }

    private func capture(_ mode: CaptureMode) {
        guard !captureRunning else { return }
        captureRunning = true

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixelwisch-\(UUID().uuidString).png")
        var args: [String]
        switch mode {
        case .region: args = ["-i"]            // Leertaste wechselt in den Fenstermodus
        case .window: args = ["-i", "-W"]
        case .screen: args = ["-m"]
        case .timed: args = ["-T", "5", "-m"]
        }
        args.append(url.path)

        let wasHidden = NSApp.isHidden
        NSApp.hide(nil) // eigene Fenster aus dem Weg räumen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            process.terminationHandler = { _ in
                DispatchQueue.main.async { self.finishCapture(url, restore: !wasHidden) }
            }
            do {
                try process.run()
            } catch {
                self.captureRunning = false
                NSApp.unhide(nil)
                self.alert("Screenshot fehlgeschlagen", error.localizedDescription)
            }
        }
    }

    private func finishCapture(_ url: URL, restore: Bool) {
        captureRunning = false
        defer { try? FileManager.default.removeItem(at: url) }

        guard FileManager.default.fileExists(atPath: url.path), let loaded = ImageFiles.load(url: url) else {
            // Abgebrochen (Esc) – vorherigen Zustand wiederherstellen.
            if restore && !editors.isEmpty { NSApp.unhide(nil) }
            return
        }

        let now = Date()
        let title = "Screenshot " + DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .medium)
        let fileFormatter = DateFormatter()
        fileFormatter.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        openEditor(image: loaded.0, pointSize: loaded.1, title: title, baseName: "Screenshot " + fileFormatter.string(from: now))
    }

    // MARK: Öffnen

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { open(urls: panel.urls) }
    }

    @objc(paste:) func pasteImage(_ sender: Any?) {
        guard let nsImage = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let image = ImageFiles.cgImage(from: nsImage) else {
            NSSound.beep()
            return
        }
        openEditor(image: image, pointSize: nsImage.size, title: "Bild aus Zwischenablage", baseName: "Bild verpixelt")
    }

    private func open(urls: [URL]) {
        for url in urls {
            guard let loaded = ImageFiles.load(url: url) else {
                alert("Bild konnte nicht geöffnet werden", url.lastPathComponent)
                continue
            }
            let base = url.deletingPathExtension().lastPathComponent
            openEditor(image: loaded.0, pointSize: loaded.1, title: url.lastPathComponent, baseName: base + " (verpixelt)")
        }
    }

    private func openEditor(image: CGImage, pointSize: CGSize, title: String, baseName: String) {
        let editor = EditorWindowController(image: image, pointSize: pointSize, title: title, baseName: baseName)
        editor.onClose = { [weak self] closed in
            self?.editors.removeAll { $0 === closed }
        }
        editor.onOpenFiles = { [weak self] urls in self?.open(urls: urls) }
        editors.append(editor)
        editor.present()
    }

    // MARK: Hilfe

    @objc func showHelp(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Willkommen bei Pixelwisch"
        a.informativeText = """
        Screenshot: \(Self.hotKeyLabel) – überall, auch wenn Pixelwisch im Hintergrund ist. \
        Oder über das Raster-Symbol in der Menüleiste.

        Dann einfach mit der Maus über alles wischen, was niemand sehen soll.

        • Pinsel (B) oder Rechteck (R) – ⇧ halten = Rechteck
        • 1 Verpixeln · 2 Unscharf · 3 Schwärzen
        • + / − ändert die Pinselgröße
        • ⌥ halten zeigt kurz das Original
        • „Automatisch“: Gesichter, E-Mails, Telefonnummern, IBANs und Tokens finden
        • ⌘C kopieren · ⌘S sichern · ⌘↩ kopieren & schließen
        • ⌘ gedrückt halten und Bild aus dem Fenster ziehen – z. B. direkt in Mail
        • ⌘Z / ⇧⌘Z widerrufen und wiederholen

        Beim ersten Screenshot fragt macOS nach der Erlaubnis für „Bildschirmaufnahme“. \
        Die bitte in den Systemeinstellungen erteilen und Pixelwisch neu starten.
        """
        a.addButton(withTitle: "Los geht’s")
        a.runModal()
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
