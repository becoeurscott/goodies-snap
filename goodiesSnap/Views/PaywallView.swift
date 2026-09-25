import SwiftUI

/// Upgrade screen — stacked "folder tab" plan cards. The selected card expands to show
/// what it includes; the others stay collapsed behind it.
///
/// Prices and purchases come from StoreKit; the server verifies paid access.
struct PaywallView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var purchases: Purchases
    /// Which card is open. Pro is the default — it is the plan the screen is arguing for,
    /// and an opening screen of four collapsed prices asks the user to work out the
    /// difference themselves.
    @State private var selected = PaywallView.defaultOfferID

    /// Set on every appearance, not just on first construction: coming back to the paywall
    /// after opening Plus once should still open on Pro.
    static let defaultOfferID = "pro-year"
    @State private var restoring = false

    /// A purchasable option as shown on one card.
    struct Offer: Identifiable {
        let id: String
        let name: String
        let price: String
        let cadence: String
        let plan: Entitlement.Plan
        let annual: Bool
        let save: String?
        let perks: [String]
    }

    /// The perks are written as things the user just did in onboarding — import a video,
    /// build a list, price a week — rather than as units of AI. "100 AI saves a month" only
    /// means something to us; "100 recipes imported a month" means something to them.
    ///
    /// Prices are unchanged: they come from the measured per-action cost, not from this copy.
    /// Auto-renewal terms for the plan currently selected, stated next to the purchase in
    /// plain words: price, billing period, that it renews until cancelled, and where to
    /// cancel. California's automatic renewal law (and Apple's guideline 3.1.2) require this
    /// before the user pays, not only in the Terms.
    private var renewalDisclosure: String {
        let offer = offers.first { $0.id == selected } ?? offers[0]
        guard purchases.product(for: offer.plan, annual: offer.annual) != nil else {
            return "Subscriptions are temporarily unavailable. You can continue using the free plan or try again."
        }
        let period = offer.annual ? "year" : "month"
        var text = "\(offer.name) is \(offer.price) per \(period) and renews automatically every \(period) at that price until you cancel. "
        if !offer.annual, store.entitlement.welcomeOfferActive, let intro = Promo.introPrice(for: offer.plan) {
            text = "\(offer.name) is \(intro) for the first month, then \(offer.price) per month, renewing automatically until you cancel. "
        }
        text += "Payment is charged to your Apple account. Cancel any time in Settings > Apple ID > Subscriptions, at least 24 hours before the renewal date. Recipes you've saved stay yours on any plan."
        return text
    }

    private var offers: [Offer] {
        [
            Offer(id: "plus-month", name: "Plus", price: purchases.priceLabel(for: .plus, annual: false), cadence: "/month",
                  plan: .plus, annual: false, save: nil,
                  perks: ["100 recipe imports a month", "Import from video, links & text",
                          "Cost estimates on every list", "Unlimited meal plans",
                          "Ingredient reuse across your week"]),
            Offer(id: "plus-year", name: "Plus · Yearly", price: purchases.priceLabel(for: .plus, annual: true), cadence: "/year",
                  plan: .plus, annual: true, save: nil,
                  perks: ["100 recipe imports a month", "Import from video, links & text",
                          "Cost estimates on every list", "Unlimited meal plans",
                          "Ingredient reuse across your week", "Full community access"]),
            Offer(id: "pro-month", name: "Pro", price: purchases.priceLabel(for: .pro, annual: false), cadence: "/month",
                  plan: .pro, annual: false, save: nil,
                  perks: ["Snap a dish and get the recipe", "400 imports & scans a month",
                          "Everything in Plus"]),
            Offer(id: "pro-year", name: "Pro · Yearly", price: purchases.priceLabel(for: .pro, annual: true), cadence: "/year",
                  plan: .pro, annual: true, save: nil,
                  perks: ["Snap a dish and get the recipe", "400 imports & scans a month",
                          "Import from video, links & text", "Cost estimates on every list",
                          "Unlimited meal plans", "Full community access"]),
        ]
    }

    /// What the user keeps without paying. Stated plainly on the end-of-onboarding pitch,
    /// because the honest answer — everything you just built — is also the reason to trust
    /// the paid tiers.
    private let freePerks = ["Everything you just built, saved",
                             "5 recipe imports a month",
                             "Shopping lists & meal planning"]

    // Card colours are positional, deepening toward the hero at the bottom.
    private func style(_ index: Int) -> CardStyle {
        switch index {
        case 0: return CardStyle(fill: .gsPeach, ink: .gsFg, sub: Color.gsFg.opacity(0.62),
                                 button: .white, buttonInk: .gsFg)
        case 1: return CardStyle(fill: .gsCard, ink: .gsFg, sub: .gsMuted,
                                 button: .gsFill, buttonInk: .gsFg)
        case 2: return CardStyle(fill: .gsPeachSoft, ink: .gsFg, sub: Color.gsFg.opacity(0.55),
                                 button: .white, buttonInk: .gsFg)
        default: return CardStyle(fill: .gsDock, ink: .white, sub: Color.white.opacity(0.68),
                                  button: .gsPeach, buttonInk: .gsFg)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                // Stacked cards. Later cards sit on top so each one tucks under the next tab.
                VStack(spacing: -16) {
                    ForEach(Array(offers.enumerated()), id: \.element.id) { i, offer in
                        PlanTabCard(
                            offer: offer,
                            style: style(i),
                            expanded: selected == offer.id,
                            isCurrent: store.entitlement.plan == offer.plan
                                && store.entitlement.annualBilling == offer.annual,
                            renewal: store.entitlement.renewalCountdown,
                            introPrice: (store.entitlement.welcomeOfferActive && !offer.annual)
                                ? Promo.introPrice(for: offer.plan) : nil,
                            onSelect: { withAnimation(AppStore.stepAnimation) { selected = offer.id } },
                            onChoose: { choose(offer) }
                        )
                        .disabled(purchases.purchasing != nil || restoring)
                        .zIndex(Double(i))
                    }
                }
                .padding(.top, 26)

                if store.paywallReason == .onboardingComplete {
                    freeCard.padding(.top, 20)
                }

                Button { store.goBack() } label: {
                    Text("Continue with Free")
                        .font(nunito(15, .extrabold))
                        .foregroundStyle(Color.gsFg)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.top, 14)

                HStack(spacing: 18) {
                    Button {
                        restoring = true
                        Task {
                            let result = await purchases.restore()
                            restoring = false
                            switch result {
                            case .success: store.showToast("Purchases restored")
                            case .failed(let message): store.showToast(message)
                            default: break
                            }
                        }
                    } label: {
                        Text(restoring ? "Restoring..." : "Restore purchases").font(nunito(12.5, .extrabold))
                    }
                    if purchases.products.isEmpty {
                        Button { Task { await purchases.loadProducts() } } label: {
                            Text("Retry").font(nunito(12.5, .extrabold))
                        }
                    }
                }
                .disabled(restoring || purchases.purchasing != nil || purchases.loading)
                .buttonStyle(.plain)
                .foregroundStyle(Color.gsAccentInk)
                .padding(.top, 16)

                Text(renewalDisclosure)
                    .font(nunito(10.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 16)

                HStack(spacing: 16) {
                    Link("Terms of Use", destination: Legal.terms)
                    Link("Privacy Policy", destination: Legal.privacy)
                }
                .font(nunito(11, .extrabold))
                .foregroundStyle(Color.gsAccentInk)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(hex: 0xFFF7DA).ignoresSafeArea())
        .task { await purchases.loadProducts() }
        .onAppear {
            // A camera-gated visit is specifically about Pro's scanning, so open the monthly
            // Pro card there; everywhere else the yearly one leads.
            selected = store.paywallReason == .cameraIsPro ? "pro-month" : Self.defaultOfferID
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack {
                    Button { store.goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Color.gsFg)
                            .frame(width: 42, height: 42)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                    Spacer()
                }
                Text(headline)
                    .font(nunito(26, .black))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                    .padding(.horizontal, 56)
            }
            Text(store.paywallReason.body)
                .font(nunito(12.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 12)
        }
    }

    /// The end-of-onboarding pitch leads with what the user just built; every other entry
    /// point leads with what they were stopped from doing.
    private var headline: String {
        switch store.paywallReason {
        case .onboardingComplete: return "Your food system\nis ready"
        case .upgrade: return "Your personal\nfood planner"
        default: return "More recipes,\nmore possibilities"
        }
    }

    /// What Free keeps. Only shown on the end-of-onboarding pitch, where the user has not hit
    /// a wall and deserves to see that walking away costs them nothing they just made.
    private var freeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Free").font(nunito(17, .black)).foregroundStyle(Color.gsFg)
                Text("what you have now")
                    .font(nunito(11.5, .bold))
                    .foregroundStyle(Color.gsMuted)
                Spacer()
                Text("$0").font(nunito(17, .black)).foregroundStyle(Color.gsFg)
            }
            ForEach(freePerks, id: \.self) { perk in
                HStack(spacing: 9) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.gsAccentInk)
                    Text(perk)
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsFg)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.gsFg.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func choose(_ offer: Offer) {
        guard store.isAuthenticated else {
            store.showAuth(.upgrade)
            return
        }
        guard purchases.purchasing == nil else { return }
        Task { await buy(offer) }
    }

    /// Runs the real StoreKit purchase. On success the server verifies the receipt and raises
    /// the plan, so the later server sync agrees instead of reverting to free — which is what
    /// made a chosen plan disappear before. Falls back to a DEBUG-only local unlock only where
    /// StoreKit products can't load (e.g. the plain simulator).
    @MainActor
    private func buy(_ offer: Offer) async {
        if purchases.products.isEmpty { await purchases.loadProducts() }
        guard purchases.product(for: offer.plan, annual: offer.annual) != nil else {
            print("[Paywall] No StoreKit product for \(offer.plan) annual=\(offer.annual). Loaded: \(purchases.products.map(\.id))")
            store.showToast("Subscriptions aren’t available right now. Please try again shortly.")
            return
        }
        switch await purchases.purchase(plan: offer.plan, annual: offer.annual) {
        case .success:
            // `onPlanChange` already applied the plan and the server now knows about it.
            store.goBack()
        case .pending:
            store.showToast("Your purchase is pending approval.")
        case .cancelled:
            break
        case .failed(let message):
            Haptics.notify(.error)
            store.showToast(message)
        }
    }
}

struct CardStyle {
    let fill: Color
    let ink: Color
    let sub: Color
    let button: Color
    let buttonInk: Color
}

// MARK: - Folder-tab card

/// Full-width card whose top edge steps down on the right, so the "Choose" button sits in
/// the notch and the next card can tuck in beneath the tab.
struct TabCardShape: Shape {
    var step: CGFloat = 44
    var split: CGFloat = 0.50
    var radius: CGFloat = 26

    func path(in r: CGRect) -> Path {
        var p = Path()
        let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
        let sx = x0 + r.width * split          // where the tab ends
        let ex = min(sx + 78, x1 - radius)     // where the lower edge begins
        let ny = y0 + step                     // notch level

        p.move(to: CGPoint(x: x0, y: y0 + radius))
        p.addQuadCurve(to: CGPoint(x: x0 + radius, y: y0), control: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: sx - radius, y: y0))
        // S-curve from the raised tab down to the notch.
        p.addCurve(to: CGPoint(x: ex, y: ny),
                   control1: CGPoint(x: sx + 18, y: y0),
                   control2: CGPoint(x: ex - 44, y: ny))
        p.addLine(to: CGPoint(x: x1 - radius, y: ny))
        p.addQuadCurve(to: CGPoint(x: x1, y: ny + radius), control: CGPoint(x: x1, y: ny))
        p.addLine(to: CGPoint(x: x1, y: y1 - radius))
        p.addQuadCurve(to: CGPoint(x: x1 - radius, y: y1), control: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x0 + radius, y: y1))
        p.addQuadCurve(to: CGPoint(x: x0, y: y1 - radius), control: CGPoint(x: x0, y: y1))
        p.closeSubpath()
        return p
    }
}

struct PlanTabCard: View {
    let offer: PaywallView.Offer
    let style: CardStyle
    let expanded: Bool
    let isCurrent: Bool
    let renewal: String
    let introPrice: String?
    let onSelect: () -> Void
    let onChoose: () -> Void

    private let step: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab row: name + price on the raised left, Choose in the right-hand notch.
            HStack(alignment: .top) {
                // No Button here any more: the whole card takes the tap (see the
                // onTapGesture below), so only the price block used to be expandable.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(offer.name)
                            .font(nunito(13, .bold))
                            .foregroundStyle(style.sub)
                        // The affordance that says the rest of the card is tappable.
                        if !expanded {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(style.sub)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(offer.price)
                            .font(nunito(30, .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(style.ink)
                        Text(offer.cadence)
                            .font(nunito(12, .bold))
                            .foregroundStyle(style.sub)
                    }
                    if isCurrent {
                        HStack(spacing: 5) {
                            Image(systemName: "clock").font(.system(size: 10, weight: .bold))
                            Text(renewal).font(nunito(11.5, .extrabold))
                        }
                        .foregroundStyle(style.ink.opacity(0.75))
                    } else if let introPrice {
                        Text("First month \(introPrice)")
                            .font(nunito(11.5, .extrabold))
                            .foregroundStyle(style.ink)
                    }
                }
                .padding(.top, 18)

                Spacer(minLength: 12)

                Group {
                    if isCurrent {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .black))
                            Text("Active").font(nunito(14, .extrabold))
                        }
                        .foregroundStyle(style.buttonInk.opacity(0.7))
                        .padding(.horizontal, 22)
                        .frame(minHeight: 46)
                        .background(style.button.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(style.buttonInk.opacity(0.25), lineWidth: 1.5))
                    } else {
                        Button(action: onChoose) {
                            Text("Choose")
                                .font(nunito(14, .extrabold))
                                .foregroundStyle(style.buttonInk)
                                .padding(.horizontal, 26)
                                .frame(minHeight: 46)
                                .background(style.button)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                    }
                }
                .padding(.top, step + 12)
            }
            .padding(.horizontal, 22)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let save = offer.save {
                        Text(save)
                            .font(nunito(13.5, .extrabold))
                            .foregroundStyle(style.fill == .gsDock ? Color.gsPeach : style.ink)
                            .padding(.top, 2)
                    }
                    ForEach(offer.perks, id: \.self) { perk in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.gsPeach).frame(width: 20, height: 20)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(Color.gsFg)
                            }
                            Text(perk)
                                .font(nunito(13.5, .semibold))
                                .foregroundStyle(style.ink)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 26)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Color.clear.frame(height: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TabCardShape(step: step).fill(style.fill))
        .compositingGroup()
        .clipShape(TabCardShape(step: step))
        .contentShape(Rectangle())
        // The whole card opens it, not just the price. The "Choose" Button inside takes
        // its own taps first, so buying is still one deliberate tap on that pill.
        .onTapGesture {
            guard !expanded else { return }
            Haptics.tap(.light)
            onSelect()
        }
        .shadow(color: .black.opacity(expanded ? 0.16 : 0.08), radius: 16, y: 8)
        .animation(AppStore.stepAnimation, value: expanded)
        .accessibilityElement(children: .contain)
        .accessibilityHint(expanded ? "" : "Tap to see what \(offer.name) includes")
    }
}


/// Promo-code entry. Codes grant one-off bonus actions.
#if DEBUG
struct PromoCodeSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var message = ""
    @State private var ok = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Redeem a code")
                .font(nunito(24, .black))
                .padding(.top, 26)
            Text("Promo codes add extra AI actions to your account.")
                .font(nunito(13, .semibold))
                .foregroundStyle(Color.gsMuted)
                .padding(.top, 6)

            TextField("", text: $code, prompt: Text("Enter your code").foregroundStyle(Color.fg(0.35)))
                .font(nunito(16, .extrabold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(Color.gsFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 22)

            if !message.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(message).font(nunito(12.5, .bold))
                }
                .foregroundStyle(ok ? Color.gsPeach : Color.gsMuted)
                .padding(.top, 10)
            }

            Button {
                let result = store.redeem(code: code)
                ok = result.ok
                message = result.message
                if result.ok { code = "" }
            } label: {
                Text("Redeem")
                    .font(nunito(15, .extrabold))
                    .foregroundStyle(Color.gsFg)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(DarkButtonStyle())
            .padding(.top, 18)

            Button { dismiss() } label: {
                Text("Done")
                    .font(nunito(13.5, .extrabold))
                    .foregroundStyle(Color.gsMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gsBg)
        .presentationDetents([.height(380)])
    }
}
#endif
