import Foundation

/// Promotional offers.
///
/// Every price here is floored by the unit economics: at the quota cap, Plus below $1.99 and
/// Pro below $4.99 lose money, and an uncapped free trial is unbounded spend. The trial is
/// therefore limited by actions as well as days.
enum Promo {

    /// Master switch for the first-month intro offer.
    ///
    /// Kept OFF until a matching StoreKit **Introductory Offer** is configured on the
    /// monthly products in App Store Connect — advertising "$4.99 first month" without a
    /// real offer would charge full price and is a review/consumer-law problem. When the
    /// promo is configured, flip this to `true` (and mirror the offer in Products.storekit)
    /// and the ribbon, Home banner and intro pricing all light up again.
    static let introOfferAvailable = false

    /// How long a new user's welcome offer stays open.
    static let welcomeWindowDays = 7
    /// Days of Pro unlocked by the trial.
    static let trialDays = 7
    /// Hard action cap during the trial — this is what bounds acquisition cost (~$0.22/user).
    static let trialActions = 25

    /// Introductory price for the first month — half of the standing price.
    ///
    /// This is a genuine discount off the genuine ongoing price: the plan really does renew at
    /// its full price, and the card must always say so ("then $9.99/month"). That disclosure is
    /// what keeps it a lawful introductory offer rather than a fictitious "was" price.
    /// Floors from the unit economics: Plus must stay ≥ $1.99, Pro ≥ $4.99.
    static func introPrice(for plan: Entitlement.Plan) -> String? {
        switch plan {
        case .plus: return "$4.99"
        case .pro: return "$9.99"
        case .free: return nil
        }
    }

    /// Headline for the ribbon. "Up to" because the depth differs by plan —
    /// Plus is 50% off, Pro is 23% — so a flat "half price" claim would be wrong for Pro.
    static let introDiscountLabel = "Up to 50% off"

    /// Redeemable codes → extra one-off actions.
    static let codes: [String: Int] = [
        "WELCOME10": 10,
        "COOK25": 25,
        "GOODIES50": 50,
    ]

    static func bonus(forCode raw: String) -> Int? {
        codes[raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }
}

extension Entitlement {

    // MARK: Welcome offer

    /// The welcome offer runs for a week from first launch, so it's always live for new users
    /// rather than tied to a calendar date that silently goes stale.
    var welcomeEndsAt: Date {
        Calendar.current.date(byAdding: .day, value: Promo.welcomeWindowDays, to: installedAt) ?? installedAt
    }

    var welcomeOfferActive: Bool {
        Promo.introOfferAvailable && !introUsed && plan == .free && Date() < welcomeEndsAt
    }

    /// "3 days left" / "6 hours left", for the countdown on the banner and paywall.
    var welcomeCountdown: String {
        let seconds = welcomeEndsAt.timeIntervalSinceNow
        guard seconds > 0 else { return "Ended" }
        let hours = Int(seconds / 3600)
        if hours >= 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s") left"
        }
        if hours >= 1 { return "\(hours) hour\(hours == 1 ? "" : "s") left" }
        return "Ends soon"
    }

    // MARK: Pro trial

    var onProTrial: Bool {
        guard let until = trialUntil else { return false }
        return Date() < until
    }

    /// What the user can actually do right now — the trial temporarily grants Pro.
    var effectivePlan: Plan { onProTrial ? .pro : plan }

    /// Whether the trial has been taken already, so it can't be restarted.
    var canStartTrial: Bool { trialUntil == nil && !plan.isPaid }

    var trialCountdown: String {
        guard let until = trialUntil, until > Date() else { return "" }
        let hours = Int(until.timeIntervalSinceNow / 3600)
        if hours >= 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s") of Pro left"
        }
        return "Pro trial ends today"
    }
}
