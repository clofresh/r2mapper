import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let ring = Ring()
    let filter = EventFilter()
    let dryRun = CommandLine.arguments.contains("--dry-run")
    var config = Config.presentationDefault
    var configModified: Date?
    var statusItem: NSStatusItem!
    var enabled = true
    var status = "No presses yet"
    var openResult: IOReturn = kIOReturnSuccess

    func applicationDidFinishLaunching(_ notification: Notification) {
        ring.debug = CommandLine.arguments.contains("--debug")
        reloadConfig()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !dryRun { requestPermissions() }
        ring.onConnectionChange = { [weak self] _ in self?.updateIcon() }
        ring.onButton = { [weak self] button in self?.handle(button) }
        openResult = ring.start()
        ring.log("open: 0x\(String(UInt32(bitPattern: openResult), radix: 16))")

        filter.debug = ring.debug
        filter.shouldDrop = { [weak self] sender in
            guard let self, self.enabled else { return false }
            return self.ring.senderIDs.contains(sender)
        }
        // The filter needs Accessibility; keep trying until it's granted.
        if !filter.start() {
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                if self?.filter.start() ?? true { timer.invalidate() }
            }
        }
        updateIcon()
    }

    func requestPermissions() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func handle(_ button: RingButton) {
        reloadConfigIfChanged()
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let action = config.action(for: button, frontmostBundleID: bundleID) else {
            status = "\(button.rawValue.capitalized): not mapped"
            return
        }
        status = "\(button.rawValue.capitalized) → \(action.summary)"
        guard enabled, !dryRun else { return }
        if !AXIsProcessTrusted() && action.key != nil {
            status = "Needs Accessibility permission"
            return
        }
        if let error = Output.perform(action) { status = error }
    }

    // MARK: Config

    func reloadConfig() {
        let (loaded, error) = Config.load()
        config = loaded
        configModified = modificationDate()
        if let error { status = error }
    }

    func reloadConfigIfChanged() {
        if modificationDate() != configModified { reloadConfig() }
    }

    func modificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: Config.fileURL.path)[.modificationDate] as? Date
    }

    // MARK: Menu

    func updateIcon() {
        let name = ring.connected ? "play.rectangle.fill" : "play.rectangle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "R2 Mapper")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !ring.connected || !enabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        reloadConfigIfChanged()
        menu.removeAllItems()

        let connection: String
        if openResult == kIOReturnNotPermitted {
            connection = "R2 ring: needs Input Monitoring permission"
        } else if !ring.connected {
            connection = "R2 ring: not connected"
        } else {
            connection = "R2 ring: connected"
        }
        menu.addItem(disabled(connection))
        if ring.connected && !filter.isRunning {
            menu.addItem(disabled("Ring's own events not blocked (needs Accessibility)"))
        }
        menu.addItem(disabled("Last: \(status)"))
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        let mappings = NSMenuItem(title: "Mappings", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for button in RingButton.allCases {
            let action = config.buttons[button.rawValue]?.summary ?? "—"
            sub.addItem(disabled("\(button.rawValue.capitalized): \(action)"))
        }
        if let apps = config.apps, !apps.isEmpty {
            for (bundleID, overrides) in apps.sorted(by: { $0.key < $1.key }) {
                sub.addItem(.separator())
                sub.addItem(disabled("In \(bundleID)\(bundleID == frontmost ? " (active)" : ""):"))
                for (button, action) in overrides.sorted(by: { $0.key < $1.key }) {
                    sub.addItem(disabled("   \(button.capitalized): \(action.summary)"))
                }
            }
        }
        mappings.submenu = sub
        menu.addItem(mappings)

        menu.addItem(item("Edit Mappings…", #selector(editConfig), key: ","))
        menu.addItem(item("Reset to Slideshow Defaults", #selector(resetConfig)))
        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            menu.addItem(item("Grant Accessibility Permission…", #selector(openAccessibility)))
        }
        if openResult == kIOReturnNotPermitted {
            menu.addItem(item("Grant Input Monitoring Permission…", #selector(openInputMonitoring)))
        }
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit R2 Mapper", #selector(quit), key: "q"))
    }

    func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func toggleEnabled() {
        enabled.toggle()
        updateIcon()
    }

    @objc func editConfig() {
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([Config.fileURL], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func resetConfig() {
        Config.presentationDefault.save()
        reloadConfig()
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            status = "Launch at Login failed: \(error.localizedDescription)"
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
