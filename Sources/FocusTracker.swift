import AppKit
import ApplicationServices

final class FocusTracker {
    var onFocusedWindowChanged: ((NSRect?) -> Void)?

    private var observer: AXObserver?
    private var focusedElement: AXUIElement?
    private var trackedPID: pid_t = 0

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // Track initial frontmost app
        if let app = NSWorkspace.shared.frontmostApplication {
            trackApp(pid: app.processIdentifier)
        }
    }

    deinit {
        removeObserver()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        trackApp(pid: app.processIdentifier)
    }

    private func trackApp(pid: pid_t) {
        removeObserver()
        trackedPID = pid

        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused window
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        if result == .success {
            focusedElement = (value as! AXUIElement)
            publishRect()
        } else {
            focusedElement = nil
            onFocusedWindowChanged?(nil)
        }

        // Create observer for this PID
        var obs: AXObserver?
        let err = AXObserverCreate(pid, axCallback, &obs)
        guard err == .success, let obs = obs else { return }
        observer = obs

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AXObserverAddNotification(obs, appElement, kAXFocusedWindowChangedNotification as CFString, selfPtr)

        if let win = focusedElement {
            AXObserverAddNotification(obs, win, kAXMovedNotification as CFString, selfPtr)
            AXObserverAddNotification(obs, win, kAXResizedNotification as CFString, selfPtr)
            AXObserverAddNotification(obs, win, kAXWindowMiniaturizedNotification as CFString, selfPtr)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    private func removeObserver() {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            observer = nil
        }
        focusedElement = nil
    }

    fileprivate func handleNotification(_ notification: CFString, element: AXUIElement) {
        let name = notification as String
        if name == kAXFocusedWindowChangedNotification as String {
            // Remove old window notifications
            if let obs = observer, let oldWin = focusedElement {
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                AXObserverRemoveNotification(obs, oldWin, kAXMovedNotification as CFString)
                AXObserverRemoveNotification(obs, oldWin, kAXResizedNotification as CFString)
                AXObserverRemoveNotification(obs, oldWin, kAXWindowMiniaturizedNotification as CFString)

                // Add for new window
                focusedElement = element
                AXObserverAddNotification(obs, element, kAXMovedNotification as CFString, selfPtr)
                AXObserverAddNotification(obs, element, kAXResizedNotification as CFString, selfPtr)
                AXObserverAddNotification(obs, element, kAXWindowMiniaturizedNotification as CFString, selfPtr)
            } else {
                focusedElement = element
            }
            publishRect()
        } else if name == kAXMovedNotification as String || name == kAXResizedNotification as String {
            publishRect()
        } else if name == kAXWindowMiniaturizedNotification as String {
            onFocusedWindowChanged?(nil)
        }
    }

    private func publishRect() {
        guard let win = focusedElement else {
            onFocusedWindowChanged?(nil)
            return
        }

        var posValue: AnyObject?
        var sizeValue: AnyObject?
        let posResult = AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posValue)
        let sizeResult = AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeValue)

        guard posResult == .success, sizeResult == .success else {
            onFocusedWindowChanged?(nil)
            return
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        // AX uses top-left origin; convert to AppKit bottom-left origin.
        // The main screen's frame defines the global coordinate space.
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitY = screenHeight - position.y - size.height

        let rect = NSRect(x: position.x, y: appKitY, width: size.width, height: size.height)
        onFocusedWindowChanged?(rect)
    }
}

private func axCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
    tracker.handleNotification(notification, element: element)
}
