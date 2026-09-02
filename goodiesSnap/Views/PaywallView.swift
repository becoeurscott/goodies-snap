import SwiftUI

/// Upgrade screen. Reached when the AI quota runs out, or from the Profile / Import meters.
///
/// Purchases run through StoreKit 2 (see `Purchases`); the plan is only raised once Apple
/// — and, when signed in, our own server — has verified the transaction.
struct PaywallView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var purchases: Purchases
    @State private var annual = false
    @State private var showCodeSheet = false
    @State private var purchaseError = ""

    /// When the camera raised the paywall, Pro leads — it's the only plan that unlocks it.
    private var plans: [Entitlement.Plan] {
        store.paywallReason == .cameraIsPro ? [.pro, .plus] : [.plus, .pro]
    }

    /// Guideline 3.1.2 requires the purchase screen itself to state what is being bought,
    /// how long it lasts, that it auto-renews, and to link the Terms and Privacy Policy.
    private var subscriptionTerms: some View {
        VStack(spacing: 10) {
            Text("Plus and Pro are auto-renewing subscriptions billed \(annual ? "yearly" : "monthly") to your Apple Account. Your subscription renews automatically unless you turn off auto-renew at least 24 hours before the period ends. Manage or cancel in your Apple Account settings.")
                .font(nunito(10.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Link("Terms of Use", destination: Legal.terms)
                Link("Privacy Policy", destination: Legal.privacy)
            }
            .font(nunito(11, .extrabold))
            .foregroundStyle(Color.gsAccentInk)
        }
        .padding(.horizontal, 6)
    }

    private func buy(_ plan: Entitlement.Plan) {
        Task {
            purchaseError = ""
            switch await purchases.purchase(plan: plan, annual: annual) {
            case .success:
                // applyPurchasedPlan already ran via onPlanChange; just leave the screen.
                store.goBack()
            case .cancelled:
                break
            case .pending:
                purchaseError = "Waiting for approval — this unlocks as soon as it's approved."
            case .failed(let message):
                purchaseError = message
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if store.entitlement.welcomeOfferActive {
                    welcomeRibbon.padding(.top, 18)
                }
                meter.padding(.top, 16)
                if store.entitlement.canStartTrial {
                    trialCard.padding(.top, 16)
                }
                billingToggle.padding(.top, 22)

                VStack(spacing: 12) {
                    ForEach(plans, id: \.self) { plan in
                        PlanCard(
                            plan: plan,
                            annual: annual,
                            current: store.entitlement.plan == plan,
                            featured: plan == store.paywallReason.highlight,
                            // First-month pricing, so it doesn't apply to the annual option.
                            intro: (store.entitlement.welcomeOfferActive && !annual)
                                ? Promo.introPrice(for: plan) : nil
                        ) {
                            buy(plan)
                        }
                    }
                }
                .padding(.top, 14)

                topUpCard.padding(.top, 18)
                promoCodeRow.padding(.top, 12)

                if !purchaseError.isEmpty {
                    Text(purchaseError)
                        .font(nunito(12, .semibold))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }

                // Apple requires a restore control on any screen selling a subscription.
                Button {
                    Task {
                        purchaseError = ""
                        if case .failed(let message) = await purchases.restore() { purchaseError = message }
                    }
                } label: {
                    Text("Restore purchases")
                        .font(nunito(13, .extrabold))
                        .foregroundStyle(Color.gsAccentInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Text("Recipes you've already saved stay yours on any plan. Cancel anytime.")
                    .font(nunito(11.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)

                subscriptionTerms
                    .padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(Color.gsBg)
        .sheet(isPresented: $showCodeSheet) { PromoCodeSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                IconButton(system: "xmark") { store.goBack() }
                Spacer()
            }
            Text(store.paywallReason.title)
                .font(nunito(28, .black))
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
            Text(store.paywallReason.body)
                .font(nunito(13.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where the user currently stands, so the ask is grounded in something real.
    private var meter: some View {
        let e = store.entitlement
        let fraction = e.included > 0 ? Double(e.included - e.includedRemaining) / Double(e.included) : 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(e.plan.title) plan")
                    .font(nunito(14, .extrabold))
                Spacer()
                Text(store.quotaLabel)
                    .font(nunito(13, .bold))
                    .foregroundStyle(e.hasActionsLeft ? Color.gsMuted : Color.gsPeach)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gsFill)
                    Capsule()
                        .fill(e.hasActionsLeft ? Color.gsPeach : Color.gsPeach.opacity(0.45))
                        .frame(width: max(4, geo.size.width * min(1, fraction)))
                }
            }
            .frame(height: 8)
            Text(e.renewalLabel)
                .font(nunito(11.5, .semibold))
                .foregroundStyle(Color.gsMuted)
        }
        .padding(16)
        .softCard(radius: 20)
    }

    /// Time-limited welcome pricing, with the countdown that makes it real.
    private var welcomeRibbon: some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.gsDock)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.35))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Promo.introDiscountLabel) your first month")
                    .font(nunito(14.5, .black))
                    .foregroundStyle(Color.gsDock)
                Text("Plus \(Promo.introPrice(for: .plus) ?? "") instead of \(Entitlement.Plan.plus.priceLabel) · \(store.entitlement.welcomeCountdown)")
                    .font(nunito(11.5, .bold))
                    .foregroundStyle(Color.gsDock.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.gsPeach)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The camera hook — capped at 25 actions so the giveaway stays bounded.
    private var trialCard: some View {
        Button { store.startProTrial() } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gsDock)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try Pro free for \(Promo.trialDays) days")
                        .font(nunito(15, .extrabold))
                    Text("Unlocks the camera · \(Promo.trialActions) AI actions included")
                        .font(nunito(11.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.gsMuted)
            }
            .padding(14)
            .softCard(radius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.gsDock.opacity(0.9), lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var promoCodeRow: some View {
        Button { showCodeSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.gsMuted)
                Text("Have a promo code?")
                    .font(nunito(13.5, .extrabold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.gsMuted)
            }
            .padding(14)
            .fillSurface(radius: 18)
        }
        .buttonStyle(PressableStyle())
    }

    private var billingToggle: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { isAnnual in
                Button {
                    withAnimation(AppStore.stepAnimation) { annual = isAnnual }
                } label: {
                    Text(isAnnual ? "Yearly · save up to 36%" : "Monthly")
                        .font(nunito(13, .extrabold))
                        .foregroundStyle(annual == isAnnual ? Color.white : Color.gsMuted)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(annual == isAnnual ? Color.gsDock : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.gsFill)
        .clipShape(Capsule())
    }

    private var topUpCard: some View {
        Button { store.addTopUp(50) } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.gsAccentInk)
                    .frame(width: 46, height: 46)
                    .background(Color.gsPeachSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top up 50 actions")
                        .font(nunito(15, .extrabold))
                    Text("One-off · no subscription")
                        .font(nunito(12, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                Spacer()
                Text("$4.99")
                    .font(nunito(16, .extrabold))
            }
            .padding(14)
            .softCard(radius: 20)
        }
        .buttonStyle(PressableStyle())
    }

}

private struct PlanCard: View {
    let plan: Entitlement.Plan
    let annual: Bool
    let current: Bool
    let featured: Bool
    /// First-month intro price, nil once the welcome window closes.
    var intro: String? = nil
    let onPick: () -> Void

    /// The standing price this plan renews at — always shown, never hidden behind the offer.
    private var fullPrice: String {
        annual ? plan.annualPriceLabel : plan.priceLabel
    }

    private var price: String { intro ?? fullPrice }
    private var cadence: String { annual ? "/year" : "/month" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.title)
                    .font(nunito(19, .black))
                if featured {
                    Text(plan == .pro ? "UNLOCKS CAMERA" : "MOST POPULAR")
                        .font(nunito(9.5, .black))
                        .tracking(1)
                        .foregroundStyle(Color.gsDock)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Color.gsPeach)
                        .clipShape(Capsule())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price).font(nunito(21, .black))
                        Text(cadence).font(nunito(12, .bold)).foregroundStyle(Color.gsMuted)
                    }
                    if intro != nil {
                        Text(fullPrice)
                            .font(nunito(12, .bold))
                            .foregroundStyle(Color.gsMuted)
                            .strikethrough()
                    }
                }
            }

            // Renewal terms are never omitted — the offer is only lawful if the ongoing
            // price is stated plainly alongside it.
            Text(intro != nil
                 ? "First month \(price), then \(fullPrice)/month · \(plan.blurb)"
                 : plan.blurb)
                .font(nunito(12.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.perks, id: \.self) { perk in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color.gsAccentInk)
                            .padding(.top, 3)
                        Text(perk)
                            .font(nunito(13, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            Button(action: onPick) {
                Text(current ? "Current plan" : (intro != nil ? "Start for \(price)" : "Choose \(plan.title)"))
                    .font(nunito(14, .extrabold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(DarkButtonStyle())
            .opacity(current ? 0.45 : 1)
            .disabled(current)
        }
        .padding(16)
        .softCard(radius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(featured ? Color.gsPeach : Color.clear, lineWidth: 2)
        )
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
