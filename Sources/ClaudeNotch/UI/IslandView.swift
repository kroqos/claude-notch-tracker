import SwiftUI
import AppKit

/// Top-anchors the pill inside the fixed full-width window, horizontally centered on the notch.
struct IslandRootView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            IslandView(model: model, notchWidth: model.notchWidth, topInset: model.topInset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The notch-fused black island. Closed: Clawd + session-% flanking the camera. Expanded: it
/// grows taller (never wider), dropping a tile grid below the notch. The NotchShape's radii
/// animate, so it morphs like the notch itself growing.
struct IslandView: View {
    let model: AppModel
    let notchWidth: CGFloat
    let topInset: CGFloat

    /// 5-Hour tile: false = show burn-rate ETA when available, true = always show reset.
    @State private var prefReset = false
    /// Tracks draw in, staggered, once per open; reset on close so the next open draws again.
    @State private var drawn = false
    /// Id of the limit row under the pointer, for the row's hover state.
    @State private var hovered: String?
    /// Id of the money cell under the pointer; its token count shows only then.
    @State private var hoveredStat: String?
    /// One amber breath on the closed pill's percent when spend pulls ahead of the clock.
    @State private var pulse = false
    /// Pointer on the peek line's text itself; only then does its reset time type in.
    @State private var peekHovered = false

    private let wing: CGFloat = 56
    private let wingInset: CGFloat = 8    // icon sits this far into its wing, the ring the same from its end
    private let iconSize: CGFloat = 18
    private let edgeInset: CGFloat = 12   // keeps content off the pill's flared edges
    private let dropInset: CGFloat = 26   // the open card's side margin: clear of the bottom corners
    private var dropHeight: CGFloat { model.expandedDropHeight }

    private var expanded: Bool { model.isExpanded }
    private var peek: Bool { model.isHovering && !expanded && !peekText.isEmpty }
    private var peekH: CGFloat { model.peekHeight }
    private var closedH: CGFloat { max(topInset, 30) }
    private var gap: CGFloat { notchWidth }
    private var closedWidth: CGFloat { wing + gap + wing + edgeInset * 2 }
    /// Peek and the open card share one width, so the click doesn't snap the pill narrower.
    private var openWidth: CGFloat { closedWidth + 32 }
    private var wide: Bool { peek || expanded }
    private var provider: ProviderUsageSnapshot { model.activeProviderSnapshot }
    private var used: Double { provider.primaryUsage ?? 0 }
    /// Loaded once each — these are read on every render of the closed row, and hitting the disk
    /// per frame during animations would be pure waste. MainActor because NSImage isn't Sendable.
    @MainActor private static let codexIcon: NSImage? = mark(named: "codex")
    @MainActor private static let antigravityIcon: NSImage? = mark(named: "antigravity")

    /// Resolves a bundled provider mark, preferring the packaged .app layout over SwiftPM's.
    private static func mark(named name: String) -> NSImage? {
        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent("ClaudeNotch_ClaudeNotch.bundle")
           ),
           let url = packagedBundle.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    @MainActor private static func mark(for provider: UsageProviderID) -> NSImage? {
        switch provider {
        case .claude: nil               // Claude draws an animated avatar instead of a mark.
        case .codex: codexIcon
        case .antigravity: antigravityIcon
        }
    }

    var body: some View {
        let shape = NotchShape(topRadius: 8,
                               bottomRadius: expanded ? 22 : peek ? 16 : max(10, closedH * 0.40))
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            // Rim light: a 1pt stroke of which the clip keeps the inner half, so the edge catches
            // a little light instead of dissolving into the wallpaper.
            shape.stroke(.white.opacity(peek || expanded ? 0.14 : 0.08), lineWidth: 1)
            VStack(spacing: 0) {
                notchRow.frame(width: closedWidth, height: closedH)
                ZStack(alignment: .top) {
                    // Content never slides in: it resolves from soft to sharp, like material
                    // settling, while the shape morphs underneath.
                    // The card rides the container's spring: when the shape overshoots, the
                    // content stretches with it (anchored under the notch) and settles back,
                    // so the whole notch reads as one elastic body instead of a shape bouncing
                    // behind fixed text. Never squashed below 1, only stretched.
                    GeometryReader { geo in
                        dropDown
                            .frame(width: openWidth, alignment: .top)
                            .scaleEffect(x: 1, y: max(1, geo.size.height / max(1, dropHeight)),
                                         anchor: .top)
                    }
                    .opacity(expanded ? 1 : 0)
                    .blur(radius: expanded ? 0 : 24)
                    if peek { peekLine.transition(.blurFade) }
                }
            }
        }
        .frame(width: wide ? openWidth : closedWidth,
               height: expanded ? closedH + dropHeight : peek ? closedH + peekH : closedH,
               alignment: .top)
        .clipShape(shape)
        // Depth: a heavy, downward shadow, deeper the more the pill is doing. Cast by a plain
        // black copy of the shape underneath, not by the content, so a moving pager never makes
        // the shadow re-render. Masked out of the menu-bar strip beside the pill: pixels there
        // would catch clicks meant for the menu bar.
        .background(alignment: .top) {
            let w = wide ? openWidth : closedWidth
            let h = expanded ? closedH + dropHeight : peek ? closedH + peekH : closedH
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                    .frame(width: w, height: h)
                    .blur(radius: expanded ? 30 : peek ? 20 : 10)
                    .offset(y: expanded ? 16 : peek ? 10 : 5)
                    .opacity(expanded ? 0.75 : peek ? 0.65 : 0.5)
            }
            // A canvas far larger than the pill, so the blur is never clipped to a box, and a
            // mask that fades in below the menu-bar strip instead of cutting a hard line.
            .frame(width: w + 320, height: h + 320, alignment: .top)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: closedH)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                    Color.black
                }
            }
        }
        .contentShape(shape)
        .contextMenu { menu }
        .onChange(of: expanded) { _, open in
            if open {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { drawn = true }
            } else {
                drawn = false
            }
        }
        .onChange(of: model.isHovering) { _, inside in
            if !inside { hovered = nil; hoveredStat = nil; peekHovered = false }
        }
        .onChange(of: sessionAheadOfClock, initial: true) { _, ahead in
            guard ahead else { return }
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { pulse = false }
        }
        // Opening overshoots a touch, closing is tighter: the open direction is the one that
        // should feel alive. `.animation(_:value:)` reads the curve off the new value.
        .animation(expanded ? .spring(duration: 0.5, bounce: 0.24)
                            : .spring(duration: 0.4, bounce: 0.05), value: expanded)
        // Peek arrives with a little bounce, leaves with almost none.
        .animation(peek ? .spring(duration: 0.4, bounce: 0.3)
                        : .spring(duration: 0.34, bounce: 0.05), value: peek)
        .animation(.easeInOut(duration: 0.3), value: used)
    }

    /// True while the 5-hour window's spend runs ahead of its clock: the moment the closed
    /// pill breathes amber once.
    private var sessionAheadOfClock: Bool {
        guard let session = provider.limits.first(where: { $0.id == "claude-session" }),
              let used = session.usedFraction, let elapsed = elapsedFraction(session)
        else { return false }
        return used > elapsed + 0.08
    }

    // MARK: peek — the hover state's one-line summary under the notch

    /// The session % already sits in the wing, so the line carries the window it can't show:
    /// the Fable weekly cap, or the provider's second limit when there is no Fable one.
    private var peekMetric: (name: String, used: Double, metric: UsageLimitMetric)? {
        let snapshot = provider
        let second = snapshot.limits.first { $0.id == "claude-fable" }
            ?? snapshot.limits.dropFirst().first
        guard let second, let used = second.usedFraction else { return nil }
        return (second.id == "claude-fable" ? "Fable weekly" : second.label, used, second)
    }
    private var peekText: String { peekMetric.map { "\($0.name) \(Fmt.pct($0.used)) " } ?? "" }

    private var peekLine: some View {
        // The hover target is exactly the text on the line: name and number alone at first,
        // then, once the reset time has typed in beside them, all of it.
        HStack(spacing: 0) {
            if let peek = peekMetric {
                HStack(spacing: 8) {
                    label(peek.name)
                    value(Fmt.pct(peek.used), size: 12,
                          color: trackColor(used: peek.used, elapsed: elapsedFraction(peek.metric)))
                }
                if peek.metric.resetsAt != nil {
                    // Zero width until hovered, so the pair sits centred and slides left as the
                    // reset time appears.
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 0, height: 1)
                        sub("·").opacity(0.6)
                        Reveal(resetText(peek.metric), color: Palette.muted, visible: peekHovered)
                    }
                    .frame(width: peekHovered ? nil : 0, alignment: .leading)
                    .clipped()
                }
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { peekHovered = $0 }
        .padding(.vertical, -6).padding(.horizontal, -6)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: peekHovered)
        .frame(width: openWidth, height: peekH)
        .contentShape(Rectangle())
        .onTapGesture { model.isExpanded.toggle() }
    }

    // Right-click menu (replaces the menu-bar item).
    @ViewBuilder private var menu: some View {
        Menu("Provider") {
            ForEach(UsageProviderID.allCases) { provider in
                Button {
                    model.selectProvider(provider)
                } label: {
                    // Undetected providers stay listed and selectable: hiding them would make the
                    // feature invisible to anyone who installs the tool later.
                    let name = ProviderAvailability.isAvailable(provider)
                        ? provider.displayName
                        : "\(provider.displayName) (not detected)"
                    if model.selectedProvider == provider {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        }
        // Every style here is a Claude mark, and Codex draws its own logo, so the picker would
        // have no effect on what's on screen.
        if model.selectedProvider == .claude {
            Menu("Icon") {
                ForEach(AvatarStyle.allCases) { style in
                    Button {
                        model.setAvatar(style)
                    } label: {
                        if model.avatarStyle == style {
                            Label(style.label, systemImage: "checkmark")
                        } else {
                            Text(style.label)
                        }
                    }
                }
            }
        }
        Button("Refresh now") { model.refreshNow() }
        Button(model.isPaused ? "Resume tracking" : "Pause tracking") { model.togglePause() }
        Button((model.animateIcon ? "✓ " : "") + "Animate icon") { model.toggleAnimateIcon() }
        Button((model.hideInFullscreen ? "✓ " : "") + "Hide in full screen") { model.toggleHideInFullscreen() }
        Button((LoginItem.isEnabled ? "✓ " : "") + "Launch at Login") { LoginItem.toggle() }
        Divider()
        Button("Check for Updates…") { Updater.shared.checkForUpdates() }
        Button("GitHub Repository…") { NSWorkspace.shared.open(AppInfo.repository) }
        Divider()
        Button("Claude Notch v\(AppInfo.version) — \(AppInfo.tagline)") {}.disabled(true)
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }

    // MARK: closed row

    private var notchRow: some View {
        HStack(spacing: 0) {
            providerIcon
                .frame(width: iconSize, height: iconSize)
                .scaleEffect(wide ? 1.35 : 1)
                .animation(.spring(duration: 0.45, bounce: 0.4), value: wide)
                .frame(width: wing - wingInset, height: closedH, alignment: .leading)
                .padding(.leading, wingInset)
                .contentShape(Rectangle())
                // Tap cycles the providers this Mac has. With only one it cycles Clawd's look
                // instead, which is what the click did before there was more than one provider.
                .onTapGesture { model.cycleProvider() }
                .help(model.iconClickSwitchesProvider
                      ? "Click to switch provider"
                      : "Click to change the icon")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.iconClickSwitchesProvider ? "Switch provider" : "Change icon")
                .accessibilityValue(model.selectedProvider.displayName)
                .accessibilityHint(model.iconClickSwitchesProvider
                                   ? "Cycles the providers installed on this Mac"
                                   : "Cycles Clawd, mono and Spark")
                .accessibilityAddTraits(.isButton)
                .accessibilityInputLabels(["Switch provider", model.selectedProvider.displayName])

            Color.clear.frame(width: gap, height: closedH)

            HStack(spacing: 5) {
                Text(provider.primaryUsage.map(Fmt.pct) ?? "—")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.45), value: provider.primaryUsage)
                    .foregroundStyle(pulse ? Palette.amber : .white)
                    .animation(.easeInOut(duration: 0.7), value: pulse)
                Ring(fraction: used, state: ringState(for: used), lineWidth: 3)
                    .frame(width: 14, height: 14)
            }
            .frame(width: wing - wingInset, height: closedH, alignment: .trailing)
            .padding(.trailing, wingInset)
            .opacity(model.isStale ? 0.5 : 1)          // dim when data isn't fresh
            .contentShape(Rectangle())
            .onTapGesture { model.isExpanded.toggle() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.selectedProvider.displayName) usage")
            .accessibilityValue(provider.primaryUsage.map(Fmt.pct) ?? "unknown")
            .accessibilityHint(model.isExpanded ? "Collapses the usage card" : "Expands the usage card")
            .accessibilityAddTraits(.isButton)
        }
        .padding(.horizontal, edgeInset)
        // The whole row is the button, camera cutout included: no pixels there, but it's still
        // the middle of the pill. Inner gestures (the icon's provider cycle) win over this one.
        .contentShape(Rectangle())
        .onTapGesture { model.isExpanded.toggle() }
    }

    @ViewBuilder private var providerIcon: some View {
        if model.selectedProvider == .claude {
            AvatarView(style: model.avatarStyle,
                       active: model.animateIcon && !model.isPaused && !model.isAtLimit,
                       urgency: model.iconUrgency)
        } else if let icon = Self.mark(for: model.selectedProvider) {
            ProviderMarkView(
                image: icon,
                active: model.animateIcon && !model.isPaused && !model.isAtLimit,
                urgency: model.iconUrgency
            )
            .opacity(model.isPaused ? 0.45 : 0.9)
        } else if let symbol = NSImage(
            systemSymbolName: model.selectedProvider.systemImage,
            accessibilityDescription: model.selectedProvider.displayName
        ) {
            Image(nsImage: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(model.isPaused ? 0.45 : 0.9))
        } else {
            Text("C")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(model.isPaused ? 0.45 : 0.9))
        }
    }

    // MARK: drop-down — the card below the notch row

    /// The card body. Its natural height is measured and pushed into the model, so the pill's
    /// frame and the click zone follow the content exactly instead of a guessed constant.
    private var dropDown: some View {
        pageLimits
            .padding(.horizontal, dropInset).padding(.top, 14).padding(.bottom, 16)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - model.expandedDropHeight) > 0.5 { model.expandedDropHeight = height }
            }
    }

    // MARK: design tokens — one accent, mono micro-labels, a 6 / 12 / 22 rhythm

    private var accent: Color { Palette.accent }
    private let gapTight: CGFloat = 6
    private let gapRow: CGFloat = 12
    private let gapSection: CGFloat = 22

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(Palette.label)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func value(_ text: String, size: CGFloat, color: Color = .white) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold)).monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.45), value: text)   // digits roll instead of blink
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func sub(_ text: String, color: Color? = nil) -> some View {
        Text(text).font(.system(size: 10)).monospacedDigit()
            .foregroundStyle(color ?? Palette.muted)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    private var hairline: some View {
        Rectangle().fill(Palette.rule).frame(height: 1)
    }

    // MARK: burn tracks — one bar carries two facts: how much of the budget is gone (the fill)
    // and how far the window's clock has run (the tick). Fill behind the tick: on pace, accent.
    // Fill past it: burning faster than the window resets, amber. Near the cap: red.

    /// Window length per limit, for the clock tick. Unknown windows get no tick.
    private func windowLength(_ metric: UsageLimitMetric) -> TimeInterval? {
        switch metric.id {
        case "claude-session": 5 * 3600
        case "claude-weekly", "claude-fable": 7 * 86_400
        default: nil
        }
    }

    private func elapsedFraction(_ metric: UsageLimitMetric) -> Double? {
        guard let length = windowLength(metric), let resets = metric.resetsAt else { return nil }
        return min(1, max(0, 1 - resets.timeIntervalSinceNow / length))
    }

    private func trackColor(used: Double, elapsed: Double?) -> Color {
        if used >= 0.85 { return Palette.red }
        if used >= 0.66 { return Palette.amber }
        if let elapsed, used > elapsed + 0.08 { return Palette.amber }
        return accent
    }

    /// `tint` overrides the pace colouring (share bars are plain white).
    private func track(used: Double?, elapsed: Double?, height: CGFloat, index: Int,
                       tint: Color? = nil) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fraction = used ?? 0
            let fillWidth = drawn && fraction > 0 ? max(height, w * fraction) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(tint ?? trackColor(used: fraction, elapsed: elapsed))
                    .frame(width: fillWidth)
                    .animation(drawn ? .spring(duration: 0.7, bounce: 0.18).delay(Double(index) * 0.08)
                                     : .easeOut(duration: 0.15), value: drawn)
                    // Live changes move too: a refresh nudges the fill, a window reset drains it.
                    .animation(.spring(duration: 0.8, bounce: 0.2), value: fraction)
                if let elapsed {
                    // The clock: a hair of white at "now", standing a touch taller than the bar.
                    Rectangle().fill(.white.opacity(0.8))
                        .frame(width: 1.5, height: height + 4)
                        .offset(x: w * elapsed - 0.75)
                        .opacity(drawn ? 1 : 0)
                        .animation(drawn ? .easeOut(duration: 0.3).delay(0.4 + Double(index) * 0.08)
                                         : .easeOut(duration: 0.1), value: drawn)
                }
            }
        }
        .frame(height: height)
    }

    /// The short window: countdown plus the clock time it lands on. The long ones: day and time.
    private func resetText(_ metric: UsageLimitMetric) -> String {
        guard let date = metric.resetsAt else { return "resets —" }
        let clock = date.formatted(date: .omitted, time: .shortened)
        if date.timeIntervalSinceNow > 20 * 3600 {
            return "resets \(date.formatted(.dateTime.weekday(.abbreviated))) \(clock)"
        }
        return "resets in \(Fmt.until(date)) at \(clock)"
    }

    private func limitRow(_ metric: UsageLimitMetric, hero: Bool, index: Int) -> some View {
        let used = metric.usedFraction
        let elapsed = elapsedFraction(metric)
        let isSession = metric.id == "claude-session"
        let eta = isSession && !prefReset ? model.etaToLimit : nil
        let title = metric.id == "claude-fable" ? "Fable weekly" : metric.label
        let color = trackColor(used: used ?? 0, elapsed: elapsed)
        let subText = eta.map { "~\(Fmt.dur($0)) to limit" } ?? resetText(metric)
        let isHovered = hovered == metric.id
        return VStack(alignment: .leading, spacing: gapTight) {
            HStack(alignment: .firstTextBaseline) {
                label(title).opacity(isHovered ? 1.6 : 1)
                Spacer(minLength: 8)
                value(used.map(Fmt.pct) ?? "—", size: hero ? 26 : 16,
                      color: used == nil ? .white.opacity(0.4) : color)
            }
            track(used: used, elapsed: elapsed, height: hero ? 6 : 4, index: index)
            Reveal(subText, color: eta != nil ? Palette.amber : Palette.muted, visible: isHovered)
        }
        // A roomier hover target than the row itself, without moving the layout: pad out,
        // take the hit shape, pad back in.
        .padding(.vertical, 5).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = metric.id } else if hovered == metric.id { hovered = nil }
        }
        .onTapGesture { if isSession, model.etaToLimit != nil { prefReset.toggle() } }
        .padding(.vertical, -5).padding(.horizontal, -8)
        .animation(.easeOut(duration: 0.18), value: hovered)
    }

    // MARK: page 1 — the limits, hero window on top, the other two side by side, stats below

    /// Nothing to render at all: a provider that isn't set up yet, or one whose first fetch
    /// hasn't landed. Centred and calm, because this is a setup state rather than a failure.
    private var providerPlaceholder: some View {
        VStack(spacing: 5) {
            Spacer(minLength: 0)
            Text(provider.provider.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(provider.statusMessage ?? "Waiting for the first reading")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
    }

    private var providerHasNothingToShow: Bool {
        let s = provider
        return s.limits.isEmpty && s.stats.isEmpty && s.dailySeries.isEmpty && s.sessions.isEmpty
    }

    /// True when the limits page hosts the week chart (Codex-style); the detail page then keeps
    /// its stat cells. When false and a series exists (Claude), the chart lives on the detail page.
    private var chartOnLimitsPage: Bool {
        let s = provider
        return !s.dailySeries.isEmpty && !s.chartOnDetailPage && s.limits.count <= 2
    }

    private var pageLimits: some View {
        let snapshot = provider
        let limits = Array(snapshot.limits.prefix(3))
        let rest = Array(limits.dropFirst())
        let stats = Array(snapshot.stats.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            if providerHasNothingToShow {
                providerPlaceholder
            } else {
                if let hero = limits.first { limitRow(hero, hero: true, index: 0) }
                if !rest.isEmpty {
                    HStack(alignment: .top, spacing: gapSection) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { i, metric in
                            limitRow(metric, hero: false, index: i + 1)
                        }
                    }
                    .padding(.top, gapRow)
                }
                if chartOnLimitsPage {
                    WeekActivityChart(series: snapshot.dailySeries, title: snapshot.chartTitle)
                        .padding(.top, gapRow)
                } else if moneyCells != nil || !stats.isEmpty {
                    hairline.padding(.top, gapSection)
                    HStack(alignment: .top, spacing: gapRow) {
                        if let cells = moneyCells {
                            ForEach(cells, id: \.id) { moneyCell($0) }
                        } else {
                            ForEach(stats) { statCell($0) }
                        }
                    }
                    .padding(.top, gapRow)
                }
                statusLine
            }
        }
        .opacity(model.isStale ? 0.55 : 1)         // dim live limits when not fresh
    }

    @ViewBuilder private var statusLine: some View {
        if let message = provider.statusMessage {
            sub(message, color: Palette.amber).padding(.top, gapRow)
        } else if model.isStale {                       // only surface a problem, never chrome
            sub("reconnecting…", color: Palette.amber).padding(.top, gapRow)
        }
    }

    private struct MoneyCell { let id: String, title: String, cost: Double?, tokens: Int? }

    /// Today / this week / all-time from the local logs, at API list price. Nil for providers
    /// without local logs, which keep their own stat metrics.
    private var moneyCells: [MoneyCell]? {
        let s = provider
        guard s.todayCost != nil || s.lifetimeCost != nil else { return nil }
        let costs = s.dailySeries.compactMap(\.cost)
        let weekCost: Double? = costs.isEmpty ? nil : costs.reduce(0, +)
        let weekTokens: Int? = s.dailySeries.isEmpty ? s.weekTokens
                                                     : s.dailySeries.map(\.tokens).reduce(0, +)
        return [
            MoneyCell(id: "today", title: "today", cost: s.todayCost, tokens: s.todayTokens),
            MoneyCell(id: "week", title: "this week", cost: weekCost, tokens: weekTokens),
            MoneyCell(id: "all", title: "all-time", cost: s.lifetimeCost, tokens: s.lifetimeTokens),
        ]
    }

    /// The sum, and on hover the token count behind it.
    private func moneyCell(_ cell: MoneyCell) -> some View {
        let isHovered = hoveredStat == cell.id
        return VStack(alignment: .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: gapTight) {
                label(cell.title)
                value(cell.cost.map(Fmt.usd) ?? cell.tokens.map(Fmt.tokens) ?? "—", size: 15)
            }
            Reveal(cell.tokens.map { "\(Fmt.tokens($0)) tokens" } ?? " ",
                   color: Palette.muted, visible: isHovered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 5)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredStat = cell.id } else if hoveredStat == cell.id { hoveredStat = nil }
        }
        .padding(.vertical, -8).padding(.horizontal, -5)
        .animation(.easeOut(duration: 0.18), value: hoveredStat)
    }

    private func statCell(_ metric: UsageStatMetric) -> some View {
        let title: String = switch metric.id {
        case "cost-today": "today"
        case "all-time": "all-time"
        default: metric.label
        }
        return VStack(alignment: .leading, spacing: gapTight) {
            label(title)
            value(metric.value, size: 15)
            sub(metric.subtitle ?? " ")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Blur-fade: the NotchNook-style state change. Content doesn't move, it goes from soft and
/// transparent to sharp and opaque (and back), while the pill's shape does the moving.
private struct BlurFade: ViewModifier {
    var radius: CGFloat
    var opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(radius: 18, opacity: 0),
                  identity: BlurFade(radius: 0, opacity: 1))
    }
}

/// A hover-only line that arrives word by word, left to right, each word from blur to sharp
/// with a few milliseconds between them: barely noticeable, like it was typed. Leaves the same
/// way, faster. Always laid out (invisible when hidden) so nothing below it shifts.
private struct Reveal: View {
    let text: String
    let color: Color
    let visible: Bool

    init(_ text: String, color: Color, visible: Bool) {
        self.text = text
        self.color = color
        self.visible = visible
    }

    var body: some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        HStack(spacing: 3) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word).font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(color).lineLimit(1)
                    // Opacity lands fast so the word is there the moment the pointer arrives;
                    // the blur resolves slowly on top of it.
                    .opacity(visible ? 1 : 0)
                    .animation(visible ? .easeOut(duration: 0.1).delay(Double(index) * 0.05)
                                       : .easeIn(duration: 0.18).delay(Double(index) * 0.02),
                               value: visible)
                    .blur(radius: visible ? 0 : 10)
                    .animation(visible ? .easeOut(duration: 0.32).delay(Double(index) * 0.05)
                                       : .easeIn(duration: 0.18).delay(Double(index) * 0.02),
                               value: visible)
            }
        }
        .accessibilityLabel(text)
    }
}
