import AppKit
import ApplicationServices
import CoreGraphics
import SwitcherCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError

final class AXWindowActions: WindowActing {

    func activate(_ window: WindowInfo) {
        if let axWindow = axElement(for: window) {
            // Restore from the Dock if minimized (harmless if it isn't).
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    /// Minimized (in-Dock) windows across all regular apps, via Accessibility.
    /// ScreenCaptureKit does not report these, so they are gathered separately.
    func minimizedWindows() -> [WindowInfo] {
        var result: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let appEl = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appEl, kAXWindowsAttribute as CFString, &windowsRef
            ) == .success, let axWindows = windowsRef as? [AXUIElement] else { continue }

            for el in axWindows {
                var minRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    el, kAXMinimizedAttribute as CFString, &minRef
                ) == .success, (minRef as? Bool) == true else { continue }

                var wid = CGWindowID(0)
                guard _AXUIElementGetWindow(el, &wid) == .success, wid != 0 else { continue }

                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""
                let appName = app.localizedName ?? ""
                result.append(WindowInfo(
                    id: wid, pid: pid,
                    appName: appName,
                    bundleId: app.bundleIdentifier,
                    title: title.isEmpty ? appName : title,
                    frame: .zero,
                    isMinimized: true
                ))
            }
        }
        return result
    }

    func close(_ window: WindowInfo, completion: @escaping (Bool) -> Void) {
        guard let axWindow = axElement(for: window) else { completion(false); return }
        var buttonRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            axWindow, kAXCloseButtonAttribute as CFString, &buttonRef
        )
        if err == .success, let button = buttonRef {
            let pressErr = AXUIElementPerformAction(
                button as! AXUIElement, kAXPressAction as CFString
            )
            completion(pressErr == .success)
        } else {
            completion(false)
        }
    }

    func frontmostWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appEl, kAXFocusedWindowAttribute as CFString, &focusedRef
        ) == .success, let focused = focusedRef else { return nil }
        var wid = CGWindowID(0)
        if _AXUIElementGetWindow(focused as! AXUIElement, &wid) == .success {
            return wid
        }
        return nil
    }

    private func axElement(for window: WindowInfo) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appEl, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return nil
        }
        for el in axWindows {
            var wid = CGWindowID(0)
            if _AXUIElementGetWindow(el, &wid) == .success, wid == window.id {
                return el
            }
        }
        return nil
    }
}
