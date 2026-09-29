import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwitcherCore

final class ScreenCaptureWindowSource: WindowSource {

    // Last-seen thumbnails, keyed by window id. Lets a window that gets
    // minimized during the session still show its most recent preview.
    private var thumbnailCache: [CGWindowID: CGImage] = [:]
    private let cacheLock = NSLock()

    private func storeCache(_ image: CGImage, for id: CGWindowID) {
        cacheLock.lock(); thumbnailCache[id] = image; cacheLock.unlock()
    }
    private func cachedThumbnail(for id: CGWindowID) -> CGImage? {
        cacheLock.lock(); defer { cacheLock.unlock() }; return thumbnailCache[id]
    }

    func currentWindows() async -> [WindowInfo] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ) else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var result: [WindowInfo] = []

        for w in content.windows {
            guard w.isOnScreen,
                  w.windowLayer == 0,
                  let app = w.owningApplication else { continue }
            if app.processID == myPID { continue }
            if w.frame.width < 40 || w.frame.height < 40 { continue }

            let title = w.title ?? ""
            result.append(WindowInfo(
                id: w.windowID,
                pid: app.processID,
                appName: app.applicationName,
                bundleId: app.bundleIdentifier,
                title: title.isEmpty ? app.applicationName : title,
                frame: w.frame
            ))
        }
        return result
    }

    func captureThumbnail(for window: WindowInfo, maxSize: CGSize) async -> CGImage? {
        // 1. Live capture if the window is currently on screen.
        if let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ), let scWindow = content.windows.first(where: { $0.windowID == window.id }) {
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let cfg = SCStreamConfiguration()
            let w = max(scWindow.frame.width, 1)
            let h = max(scWindow.frame.height, 1)
            let scale = min(maxSize.width / w, maxSize.height / h, 1)
            cfg.width = max(1, Int(w * scale))
            cfg.height = max(1, Int(h * scale))
            cfg.showsCursor = false

            if let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: cfg
            ) {
                storeCache(image, for: window.id)
                return image
            }
        }

        // 2. Off screen (e.g. minimized): last-seen thumbnail from this session.
        if let cached = cachedThumbnail(for: window.id) { return cached }

        // 3. Best-effort fallback: the window server may still hold the last
        //    rendered frame for a minimized window (deprecated API, may fail).
        if let fallback = CGWindowListCreateImage(
            .null, .optionIncludingWindow, window.id, [.boundsIgnoreFraming, .bestResolution]
        ) {
            return fallback
        }

        return nil
    }
}
