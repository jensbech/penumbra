import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindows: [OverlayWindow] = []
    private var focusTracker: FocusTracker!
    private var enabled = true
    private var opacity: CGFloat = 0.4
    private var enableMenuItem: NSMenuItem!
    private var sliderMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility permissions
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
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "penumbra")
        }

        let menu = NSMenu()

        enableMenuItem = NSMenuItem(title: "Disable", action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        menu.addItem(enableMenuItem)

        menu.addItem(.separator())

        let sliderItem = NSMenuItem()
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let slider = NSSlider(value: Double(opacity), minValue: 0.0, maxValue: 1.0, target: self, action: #selector(opacityChanged(_:)))
        slider.frame = NSRect(x: 16, y: 4, width: 168, height: 22)
        slider.isContinuous = true
        sliderView.addSubview(slider)
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        sliderMenuItem = sliderItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
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
    }

    private func updateCutout(_ rect: NSRect?, cornerRadius: CGFloat) {
        for window in overlayWindows {
            if let rect = rect {
                // Convert the screen-global rect to this overlay's local coordinates
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
        enableMenuItem.title = enabled ? "Disable" : "Enable"
        for window in overlayWindows {
            window.overlayView.opacity = enabled ? opacity : 0
        }
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        opacity = CGFloat(sender.doubleValue)
        guard enabled else { return }
        for window in overlayWindows {
            window.overlayView.opacity = opacity
        }
    }

    @objc private func screensDidChange() {
        setupOverlays()
    }
}
