import AppKit
import ApplicationServices

/// Reads and sets the frame of a Claude window through the Accessibility
/// API, so the profile you switch to takes the place of the one you leave.
/// Without the Accessibility permission nothing moves.
enum WindowFrames {
    static var allowed: Bool { AXIsProcessTrusted() }

    static func askForAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func frame(of app: NSRunningApplication) -> CGRect? {
        guard allowed, let window = mainWindow(app.processIdentifier) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard read(window, kAXPositionAttribute, .cgPoint, &origin), read(window, kAXSizeAttribute, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setFrame(_ frame: CGRect, of app: NSRunningApplication) -> Bool {
        guard allowed, let window = mainWindow(app.processIdentifier) else { return false }
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else {
            return false
        }
        // Size, position, size again: moving to another display can clamp the
        // first size to the old display.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent) == .success
    }

    /// Waits for a profile that is still starting to open its window, then
    /// places it.
    static func place(_ app: NSRunningApplication, at frame: CGRect, timeout: TimeInterval = 15) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !app.isTerminated {
            if setFrame(frame, of: app) { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private static func mainWindow(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value,
                CFGetTypeID(value) == AXUIElementGetTypeID()
            {
                return (value as! AXUIElement)
            }
        }
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success else {
            return nil
        }
        return (windows as? [AXUIElement])?.first
    }

    private static func read<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType, _ out: inout T) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return false }
        return AXValueGetValue(value as! AXValue, type, &out)
    }
}
