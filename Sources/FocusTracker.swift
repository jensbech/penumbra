import AppKit
import ApplicationServices

// Private macOS SkyLight APIs for reading window corner radius
@_silgen_name("SLSMainConnectionID")
private func SLSMainConnectionID() -> Int32

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ outWindowID: UnsafeMutablePointer<UInt32>) -> AXError

@_silgen_name("SLSWindowQueryWindows")
private func SLSWindowQueryWindows(_ cid: Int32, _ windows: CFArray, _ options: UInt32) -> OpaquePointer?

@_silgen_name("SLSWindowQueryResultCopyWindows")
private func SLSWindowQueryResultCopyWindows(_ query: OpaquePointer) -> OpaquePointer?

@_silgen_name("SLSWindowIteratorAdvance")
private func SLSWindowIteratorAdvance(_ iterator: OpaquePointer) -> Bool

// Loaded dynamically — only available on macOS 26+, follows the Get rule (no ownership transfer)
private typealias CornerRadiiFn = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
private let _getCornerRadii: CornerRadiiFn? = {
    guard let handle = dlopen(nil, RTLD_LAZY),
          let sym = dlsym(handle, "SLSWindowIteratorGetCornerRadii") else { return nil }
    return unsafeBitCast(sym, to: CornerRadiiFn.self)
}()

final class FocusTracker {
    var onFocusedWindowChanged: (((rect: NSRect, cornerRadius: CGFloat)?) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var focusedElement: AXUIElement?
    private var trackedPID: pid_t = 0

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func start() {
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
        guard pid != trackedPID else { return }
        removeObserver()
        trackedPID = pid

        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 1.0)
        appElement = element

        var obs: AXObserver?
        let err = AXObserverCreate(pid, axCallback, &obs)
        guard err == .success, let obs = obs else {
            trackedPID = 0
            appElement = nil
            onFocusedWindowChanged?(nil)
            return
        }
        observer = obs

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, element, kAXFocusedWindowChangedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, element, kAXMainWindowChangedNotification as CFString, selfPtr)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

        if let win = queryFocusedWindow(element) {
            focusedElement = win
            registerWindowNotifications(obs: obs, win: win, selfPtr: selfPtr)
            publishRect()
        } else {
            focusedElement = nil
            onFocusedWindowChanged?(nil)
            retryFocusedWindow(pid: pid, appElement: element, attempt: 1)
        }
    }

    private func retryFocusedWindow(pid: pid_t, appElement: AXUIElement, attempt: Int) {
        let delays: [Double] = [0.05, 0.1, 0.25, 0.5]
        guard attempt <= delays.count else { return }
        let delay = delays[attempt - 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.trackedPID == pid, let obs = self.observer else { return }
            guard self.focusedElement == nil else { return }
            if let win = self.queryFocusedWindow(appElement) {
                self.focusedElement = win
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                self.registerWindowNotifications(obs: obs, win: win, selfPtr: selfPtr)
                self.publishRect()
            } else {
                self.retryFocusedWindow(pid: pid, appElement: appElement, attempt: attempt + 1)
            }
        }
    }

    private func queryFocusedWindow(_ appElement: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success, value != nil {
            return (value as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &value) == .success, value != nil {
            return (value as! AXUIElement)
        }
        return nil
    }

    private func registerWindowNotifications(obs: AXObserver, win: AXUIElement, selfPtr: UnsafeMutableRawPointer) {
        AXObserverAddNotification(obs, win, kAXMovedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, win, kAXResizedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, win, kAXWindowMiniaturizedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, win, kAXWindowDeminiaturizedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, win, kAXUIElementDestroyedNotification as CFString, selfPtr)
    }

    private func removeObserver() {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            observer = nil
        }
        appElement = nil
        focusedElement = nil
    }

    private func cornerRadius(for element: AXUIElement) -> CGFloat {
        var windowID: UInt32 = 0
        guard _AXUIElementGetWindow(element, &windowID) == .success,
              let getRadii = _getCornerRadii else { return 10 }

        let cid = SLSMainConnectionID()
        let windowArray = [NSNumber(value: windowID)] as NSArray
        guard let query = SLSWindowQueryWindows(cid, windowArray, 0),
              let iterator = SLSWindowQueryResultCopyWindows(query) else { return 10 }

        guard SLSWindowIteratorAdvance(iterator) else { return 10 }

        guard let unmanaged = getRadii(iterator) else { return 10 }
        let radii = unmanaged.takeUnretainedValue()
        guard CFArrayGetCount(radii) > 0 else { return 10 }

        let valuePtr = CFArrayGetValueAtIndex(radii, 0)!
        let cfNumber = unsafeBitCast(valuePtr, to: CFNumber.self)
        var radius: Int32 = 0
        CFNumberGetValue(cfNumber, .sInt32Type, &radius)

        return radius > 0 ? CGFloat(radius) : 10
    }

    fileprivate func handleNotification(_ notification: CFString, element: AXUIElement) {
        let name = notification as String
        if name == kAXFocusedWindowChangedNotification as String || name == kAXMainWindowChangedNotification as String {
            guard let appEl = appElement else { return }
            guard let win = queryFocusedWindow(appEl) else {
                if let obs = observer, let oldWin = focusedElement {
                    AXObserverRemoveNotification(obs, oldWin, kAXMovedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXResizedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXWindowMiniaturizedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXWindowDeminiaturizedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXUIElementDestroyedNotification as CFString)
                }
                focusedElement = nil
                onFocusedWindowChanged?(nil)
                retryFocusedWindow(pid: trackedPID, appElement: appEl, attempt: 1)
                return
            }
            if let old = focusedElement, CFEqual(win, old) { return }
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            if let obs = observer {
                if let oldWin = focusedElement {
                    AXObserverRemoveNotification(obs, oldWin, kAXMovedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXResizedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXWindowMiniaturizedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXWindowDeminiaturizedNotification as CFString)
                    AXObserverRemoveNotification(obs, oldWin, kAXUIElementDestroyedNotification as CFString)
                }
                focusedElement = win
                registerWindowNotifications(obs: obs, win: win, selfPtr: selfPtr)
            } else {
                focusedElement = win
            }
            publishRect()
        } else if name == kAXMovedNotification as String || name == kAXResizedNotification as String {
            publishRect()
        } else if name == kAXWindowMiniaturizedNotification as String {
            onFocusedWindowChanged?(nil)
        } else if name == kAXWindowDeminiaturizedNotification as String {
            publishRect()
        } else if name == kAXUIElementDestroyedNotification as String {
            focusedElement = nil
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
            focusedElement = nil
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
        let radius = cornerRadius(for: win)
        onFocusedWindowChanged?((rect: rect, cornerRadius: radius))
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
