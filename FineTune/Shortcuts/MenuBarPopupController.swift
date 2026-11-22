// FineTune/Shortcuts/MenuBarPopupController.swift
import AppKit
import os

/// Toggles the FineTune menu-bar popup from outside the SwiftUI scene chain
/// (e.g. when a global hotkey fires).
///
/// Locates the underlying `NSStatusItem` via `NSApp.windows` + KVC introspection
/// of the private `NSStatusBarWindow.statusItem` key. This is the same technique
/// used by `orchetect/MenuBarExtraAccess` for Apple's `MenuBarExtra` and works
/// equally well for `FluidMenuBarExtra` because both ultimately call
/// `NSStatusBar.system.statusItem(...)` and rely on the standard menu-bar window
/// machinery. The technique is package-agnostic and avoids needing any callback
/// wiring (no `onStatusItemReady`, no Scene-reference capture).
///
/// Once the status item is located, we toggle the popup by posting a synthetic
/// `.leftMouseDown` event aimed at the button's window. `FluidMenuBarExtra`
/// installs a `LocalEventMonitor` that filters events on the status button's
/// window — the synthetic event satisfies that filter and re-uses the package's
/// existing visible→dismiss / hidden→show toggle logic, including the
/// screen-edge framing math.
@MainActor
protocol MenuBarPopupControlling: AnyObject {
    func toggle()
}

@MainActor
final class MenuBarPopupController: MenuBarPopupControlling {
    private static let logger = Logger(
        subsystem: "com.finetuneapp.FineTune",
        category: "MenuBarPopupController"
    )

    /// Accessibility title used to identify FineTune's status item among any
    /// other status items in the same process. `FluidMenuBarExtra` sets this on
    /// the button via `setAccessibilityTitle(title)` where `title` is the first
    /// argument we pass to `FluidMenuBarExtra(...)` in `FineTuneApp`.
    private let accessibilityTitle: String

    init(accessibilityTitle: String = "LazyTune") {
        self.accessibilityTitle = accessibilityTitle
    }

    /// Shows the popup if it is not already visible, retrying briefly on cold launch
    /// while `FluidMenuBarExtra` creates its status bar item.
    func openWhenReady(retriesLeft: Int = 30) {
        if isPopupWindowVisible() { return }
        if findStatusButton() != nil {
            toggle()
            return
        }
        guard retriesLeft > 0 else {
            Self.logger.debug("openWhenReady: status item did not appear within timeout")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.openWhenReady(retriesLeft: retriesLeft - 1)
        }
    }

    func toggle() {
        guard let button = findStatusButton(), let window = button.window else {
            Self.logger.debug("toggle: no status button/window found yet (cold-launch race?); ignoring")
            return
        }

        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        let location = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        ) else {
            Self.logger.error("toggle: failed to construct synthetic mouse-down event")
            return
        }

        NSApp.postEvent(event, atStart: false)
    }

    private func isPopupWindowVisible() -> Bool {
        NSApp.windows.contains { $0.isVisible && $0.className.contains("FluidMenuBarExtraWindow") }
    }

    private func findStatusButton() -> NSStatusBarButton? {
        if let button = findStatusItem()?.button {
            return button
        }
        for window in NSApp.windows {
            guard window.className.contains("NSStatusBarWindow"),
                  let contentView = window.contentView else { continue }
            if let button = findStatusBarButton(in: contentView, matching: accessibilityTitle) {
                return button
            }
        }
        return nil
    }

    private func findStatusBarButton(in view: NSView, matching title: String) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton, button.accessibilityTitle() == title {
            return button
        }
        for subview in view.subviews {
            if let match = findStatusBarButton(in: subview, matching: title) {
                return match
            }
        }
        return nil
    }

    // MARK: - NSApp.windows + KVC introspection

    /// Exposed `internal` so tests can verify discovery without depending on
    /// `NSApp.postEvent` delivery, which is flaky in a unit-test process.
    func findStatusItem() -> NSStatusItem? {
        NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap(Self.extractStatusItem(from:))
            // Multi-display setups with "Displays have separate Spaces" enabled produce
            // one NSStatusBarWindow per display; the inactive ones return an
            // `NSStatusItemReplicant`. Skip replicants so we target the canonical button.
            .filter { !$0.className.contains("Replicant") }
            .first { $0.button?.accessibilityTitle() == accessibilityTitle }
    }

    /// Pulls the `statusItem` private key off an `NSStatusBarWindow`.
    /// KVC is the primary path; `Mirror` is a defensive fallback in case Apple
    /// changes how the property is exposed in a future macOS release.
    private static func extractStatusItem(from window: NSWindow) -> NSStatusItem? {
        if let item = window.value(forKey: "statusItem") as? NSStatusItem {
            return item
        }
        return Mirror(reflecting: window).descendant("statusItem") as? NSStatusItem
    }
}
