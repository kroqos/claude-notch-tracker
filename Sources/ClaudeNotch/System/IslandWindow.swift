import AppKit
import SwiftUI
import os

private let hoverLog = Logger(subsystem: "com.claudenotch.app", category: "hover")

/// Borderless floating panel that never becomes key (so it can't steal typing focus).
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Only claims mouse events inside `interactiveRect` (the pill's footprint). Everywhere else it
/// returns nil so clicks fall through to the menu bar / desktop / other apps.
///
/// NOTE: that fall-through works because the window server click-throughs transparent pixels of a
/// borderless non-opaque window. NEVER set `panel.ignoresMouseEvents` explicitly (even to false):
/// doing so disables that per-pixel behavior for the whole frame, and every click in the top strip
/// gets routed to us and dies here — dead menu bar and title-bar buttons under the strip.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: CGRect = .zero
    /// Cleared while the pill is retracted for fullscreen so a hidden pill can never claim a click.
    var interactionEnabled = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactionEnabled, interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A FIXED-size top-strip window. The pill animates its own height inside it — the window is
/// never resized, so expand/collapse can't jump or redraw the whole thing.
@MainActor
final class IslandWindow {
    private let panel: NotchPanel
    private let hosting: PassthroughHostingView<IslandRootView>
    private let model: AppModel
    private let panelHeight: CGFloat = 420   // room for the open spring's overshoot and the shadow

    private var hoverMonitors: [Any] = []
    private var hoverInside = false
    private var collapseTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        hosting = PassthroughHostingView(rootView: IslandRootView(model: model))
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: panelHeight))
        panel.contentView = hosting
        installHoverProbe()
    }

    // MARK: hover probe — detection only, logged, nothing visible yet.
    //
    // Two monitors on purpose: mouse-moves over the pill's opaque pixels are delivered to THIS
    // app (local monitor), moves anywhere else go to other apps (global monitor). Each one
    // answers the same question, "is the pointer inside the pill's footprint", so the source is
    // logged to learn which path actually fires on this window.
    private func installHoverProbe() {
        panel.acceptsMouseMovedEvents = true
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.probe(source: "local") }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.probe(source: "global") }
        }
        // A click under the camera lands on no window at all, so it reaches us only this way.
        // Opens only: while open, the delegate's outside-click monitor already closes on it.
        let click = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.isExpanded,
                      self.pillScreenRect.contains(NSEvent.mouseLocation) else { return }
                hoverLog.log("click via global inside pill: opening")
                self.model.isExpanded = true
            }
        }
        hoverMonitors = [local, global, click].compactMap { $0 }
        hoverLog.log("probe installed, monitors: \(self.hoverMonitors.count)")
    }

    /// Leaving the open card closes it, after a short grace so grazing the edge doesn't slam it,
    /// and never while a menu is up: opening the context menu reads as an exit.
    private func scheduleCollapse() {
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            while !Task.isCancelled, RunLoop.main.currentMode == .eventTracking {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let self, !Task.isCancelled, !self.hoverInside else { return }
            self.model.isExpanded = false
        }
    }

    /// `interactiveRect` is written in window coordinates (that's what hitTest compares against:
    /// AppKit passes the point in the unflipped parent's space), so it converts straight to
    /// screen. Routing it through the flipped hosting view lands the zone at the panel's bottom.
    private var pillScreenRect: NSRect {
        // Extended past the top of the screen: under the camera the pointer is clamped to the
        // very top row, and NSRect.contains excludes its own maxY, so a flush rect flickers.
        var rect = panel.convertToScreen(hosting.interactiveRect)
        rect.size.height += 40
        return rect
    }

    private func probe(source: String) {
        let inside = pillScreenRect.contains(NSEvent.mouseLocation)
        guard inside != hoverInside else { return }
        hoverInside = inside
        model.isHovering = inside
        collapseTask?.cancel()
        collapseTask = nil
        if inside {
            if !model.isExpanded { Haptics.thump() }
        } else if model.isExpanded {
            scheduleCollapse()
        }
        let p = NSEvent.mouseLocation
        let r = pillScreenRect
        hoverLog.log("\(inside ? "ENTER" : "EXIT", privacy: .public) via \(source, privacy: .public) at \(Int(p.x)),\(Int(p.y)) pill x\(Int(r.minX))-\(Int(r.maxX)) y\(Int(r.minY))-\(Int(r.maxY))")
    }

    /// Resting frame: the full-width strip flush to the top of the notched screen (or main).
    private func restingFrame() -> NSRect? {
        guard let screen = NSScreen.island else { return nil }
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - panelHeight,
                      width: screen.frame.width, height: panelHeight)
    }

    /// Position the full-width strip on the notched screen (or main), flush to its top.
    /// Called on launch and whenever the display configuration changes.
    ///
    /// Retract-aware: `sync()` also runs this on Claude launch/quit and screen-parameter changes,
    /// which can happen mid-fullscreen. A retracted pill must stay retracted, or an invisible
    /// (alpha-0) panel would be parked back over the fullscreen app until the next show().
    func relayout() {
        guard var frame = restingFrame() else { return }
        if isRetracted { frame.origin.y += slideDistance }
        panel.setFrame(frame, display: true)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        updateInteractiveZone()
    }

    /// Resize only the invisible click-catcher to the pill's current footprint — cheap, no
    /// window resize, so no animation jump.
    func updateInteractiveZone() {
        let closedH = max(model.topInset, 30)
        let dropH = model.expandedDropHeight
        let zoneW = model.notchWidth + 56 * 2 + 24 + 48    // wing+gap+wing + edge insets + open width + margin
        let zoneH = model.isExpanded ? closedH + dropH + 8
                  : model.isHovering ? closedH + model.peekHeight + 8
                  : closedH + 6
        let w = hosting.bounds.width
        let h = hosting.bounds.height
        hosting.interactiveRect = CGRect(x: (w - zoneW) / 2, y: h - zoneH, width: zoneW, height: zoneH)
    }

    /// How far the pill travels up (into the notch) when hiding for fullscreen. Enough to clear the
    /// collapsed pill + Clawd; paired with a fade so the retract reads cleanly.
    private let slideDistance: CGFloat = 110

    /// True while the pill is retracted for fullscreen: slid up, alpha 0, but still in the window
    /// list (see hide() for why it's never ordered out). relayout() consults this.
    private(set) var isRetracted = false

    /// Slide the pill down out of the notch into its resting spot. Used when leaving fullscreen or
    /// turning the option off.
    func show() {
        isRetracted = false
        hosting.interactionEnabled = true                      // interactive again
        guard let rest = restingFrame() else { panel.orderFrontRegardless(); return }
        if !panel.isVisible {                                  // first appearance: start retracted
            var start = rest; start.origin.y += slideDistance
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(rest, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Slide the pill up into the notch and fade it out. The panel is NOT ordered out — removing it
    /// from the window list while a fullscreen Space is active makes macOS drop its
    /// `.canJoinAllSpaces` membership, pinning it to one Space afterward. Staying in the list (just
    /// transparent + slid up) keeps it on every Space.
    ///
    /// While retracted, interaction is additionally gated off at the view level (see
    /// PassthroughHostingView.interactionEnabled) so a hidden pill can never claim a click even if
    /// something repositions it on-screen. Window-server click-through of transparent pixels stays
    /// untouched — `ignoresMouseEvents` must never be set explicitly (see the note on the view).
    func hide() {
        model.isExpanded = false                               // never slide away mid-expand
        isRetracted = true
        hosting.interactionEnabled = false                     // a hidden pill must never eat clicks
        guard let rest = restingFrame() else { return }
        var end = rest; end.origin.y += slideDistance
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        }
    }
}
