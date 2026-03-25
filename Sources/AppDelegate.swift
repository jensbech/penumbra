import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindows: [OverlayWindow] = []
    private var focusTracker: FocusTracker!
    private var enabled = true
    private var opacity: CGFloat = 0.4
    private var enableMenuItem: NSMenuItem!
    private var loginItemMenuItem: NSMenuItem!
    private var opacitySlider: NSSlider!
    private var opacityValueLabel: NSTextField!
    private var lastCutoutRect: NSRect?
    private var lastCornerRadius: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "penumbra needs Accessibility access to track the focused window.\n\nPlease grant access in System Settings → Privacy & Security → Accessibility, then relaunch."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()
        setupOverlays()
        setupFocusTracker()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        let menu = NSMenu()

        enableMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enableMenuItem.target = self
        enableMenuItem.state = .on
        menu.addItem(enableMenuItem)

        loginItemMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItemMenuItem.target = self
        loginItemMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItemMenuItem)

        menu.addItem(.separator())

        let sliderItem = NSMenuItem()
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))

        let opacityTitleLabel = NSTextField(labelWithString: "Opacity")
        opacityTitleLabel.frame = NSRect(x: 16, y: 30, width: 90, height: 14)
        opacityTitleLabel.font = .menuFont(ofSize: 13)
        sliderView.addSubview(opacityTitleLabel)

        opacityValueLabel = NSTextField(labelWithString: percentString(opacity))
        opacityValueLabel.frame = NSRect(x: 110, y: 30, width: 74, height: 14)
        opacityValueLabel.font = .menuFont(ofSize: 13)
        opacityValueLabel.alignment = .right
        opacityValueLabel.textColor = .secondaryLabelColor
        sliderView.addSubview(opacityValueLabel)

        opacitySlider = NSSlider(value: Double(opacity), minValue: 0.0, maxValue: 1.0, target: self, action: #selector(opacityChanged(_:)))
        opacitySlider.frame = NSRect(x: 16, y: 6, width: 168, height: 20)
        opacitySlider.isContinuous = true
        sliderView.addSubview(opacitySlider)

        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateIcon() {
        let symbolName = enabled ? "circle.lefthalf.filled" : "circle"
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "penumbra")
    }

    private func percentString(_ value: CGFloat) -> String {
        "\(Int(value * 100))%"
    }

    // MARK: - Overlays

    private func setupOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            window.overlayView.opacity = enabled ? opacity : 0
            overlayWindows.append(window)
            window.orderFront(nil)
        }
    }

    private func setupFocusTracker() {
        focusTracker = FocusTracker()
        focusTracker.onFocusedWindowChanged = { [weak self] info in
            self?.updateCutout(info?.rect, cornerRadius: info?.cornerRadius ?? 0)
        }
        focusTracker.start()
    }

    private func updateCutout(_ rect: NSRect?, cornerRadius: CGFloat) {
        lastCutoutRect = rect
        lastCornerRadius = cornerRadius
        for window in overlayWindows {
            if let rect = rect {
                let localRect = NSRect(
                    x: rect.origin.x - window.frame.origin.x,
                    y: rect.origin.y - window.frame.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                window.overlayView.cornerRadius = cornerRadius
                window.overlayView.cutoutRect = localRect
            } else {
                window.overlayView.cutoutRect = nil
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        enabled.toggle()
        enableMenuItem.state = enabled ? .on : .off
        opacitySlider.isEnabled = enabled
        updateIcon()
        for window in overlayWindows {
            window.overlayView.opacity = enabled ? opacity : 0
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // If registration requires user approval, open Login Items settings
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
        loginItemMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        opacity = CGFloat(sender.doubleValue)
        opacityValueLabel.stringValue = percentString(opacity)
        guard enabled else { return }
        for window in overlayWindows {
            window.overlayView.opacity = opacity
        }
    }

    @objc private func screensDidChange() {
        setupOverlays()
        updateCutout(lastCutoutRect, cornerRadius: lastCornerRadius)
    }
}
