import SwiftUI

/// Upgrade screen — stacked "folder tab" plan cards. The selected card expands to show
/// what it includes; the others stay collapsed behind it.
///
/// Purchases still flip local entitlement state via `activate(_:)`. Wiring StoreKit 2 means
/// swapping that call for a verified transaction — the layout stays as-is.
struct PaywallView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected = "pro-year"
    @State private var trialOn = true
    @State private var showCodeSheet = false

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

    private var offers: [Offer] {
        [
            Offer(id: "plus-month", name: "Plus", price: Entitlement.Plan.plus.priceLabel, cadence: "/month",
                  plan: .plus, annual: false, save: nil,
                  perks: ["100 AI saves a month", "Save from links, video & text",
                          "Unlimited recipes you add yourself", "Meal plan & shopping list"]),
            Offer(id: "plus-year", name: "Plus · Yearly", price: Entitlement.Plan.plus.annualPriceLabel, cadence: "/year",
                  plan: .plus, annual: true, save: "Save 33%",
                  perks: ["100 AI saves a month", "Save from links, video & text",
                          "Unlimited recipes you add yourself", "Meal plan & shopping list",
                          "Full community access"]),
            Offer(id: "pro-month", name: "Pro", price: Entitlement.Plan.pro.priceLabel, cadence: "/month",
                  plan: .pro, annual: false, save: nil,
                  perks: ["Scan a dish with your camera", "400 AI actions a month",
                          "Save from links, video & text", "Everything in Plus"]),
            Offer(id: "pro-year", name: "Pro · Yearly", price: Entitlement.Plan.pro.annualPriceLabel, cadence: "/year",
                  plan: .pro, annual: true, save: "Save 36%",
                  perks: ["Scan a dish with your camera", "400 AI actions a month",
                          "Save from links, video & text", "Unlimited recipes you add yourself",
                          "Meal plan & shopping list", "Full community access", "Priority support"]),
        ]
    }

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
                        .zIndex(Double(i))
                    }
                }
                .padding(.top, 26)

                if store.entitlement.canStartTrial {
                    trialToggle
                        .padding(.top, 22)
                }

                Button { store.goBack() } label: {
                    Text("Continue with Free")
                        .font(nunito(15, .extrabold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.top, 14)

                HStack(spacing: 18) {
                    Button { showCodeSheet = true } label: {
                        Text("Have a promo code?").font(nunito(12.5, .extrabold))
                    }
                    Button { store.addTopUp(50) } label: {
                        Text("Top up 50 actions · $4.99").font(nunito(12.5, .extrabold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.gsAccentInk)
                .padding(.top, 16)

                Text("Subscriptions renew automatically and can be cancelled any time in your Apple account settings. Recipes you've saved stay yours on any plan.")
                    .font(nunito(10.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(hex: 0xFFF7DA).ignoresSafeArea())
        .sheet(isPresented: $showCodeSheet) { PromoCodeSheet() }
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
                Text("Get unlimited\naccess")
                    .font(nunito(26, .black))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                    .padding(.horizontal, 56)
            }
            if store.paywallReason != .upgrade {
                Text(store.paywallReason.title)
                    .font(nunito(12.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .padding(.top, 4)
            }
        }
    }

    private var trialToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Start \(Promo.trialDays)-day free trial")
                    .font(nunito(14, .extrabold))
                Text("Pro, with \(Promo.trialActions) AI actions included")
                    .font(nunito(11, .semibold))
                    .foregroundStyle(Color.gsMuted)
            }
            Spacer()
            Toggle("", isOn: $trialOn)
                .labelsHidden()
                .tint(Color.gsPeach)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private func choose(_ offer: Offer) {
        // A plan is attached to an account, not a handset — without one there is nowhere
        // for the entitlement to live, and it would be lost on reinstall.
        guard store.isAuthenticated else {
            store.showAuth(.upgrade)
            return
        }
        // With the trial switched on, a Pro choice starts the free week instead of billing.
        if trialOn, offer.plan == .pro, store.entitlement.canStartTrial {
            store.startProTrial()
        } else {
            store.activate(offer.plan, annual: offer.annual)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.name)
                        .font(nunito(13, .bold))
                        .foregroundStyle(style.sub)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(offer.price)
                            .font(nunito(30, .black))
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
                        // Already on this plan: an inert chip, not a button you can press again.
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
                        .buttonStyle(PressableStyle(scale: 0.95))
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
        .background(style.fill)
        .clipShape(TabCardShape(step: step))
        .shadow(color: .black.opacity(expanded ? 0.16 : 0.08), radius: 16, y: 8)
        .contentShape(TabCardShape(step: step))
        .onTapGesture(perform: onSelect)
        .animation(AppStore.stepAnimation, value: expanded)
    }
}


/// Promo-code entry. Codes grant one-off bonus actions.
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
                    .foregroundStyle(Color.white)
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
