import Foundation

/// Promotional offers.
///
/// Every price here is floored by the unit economics: at the quota cap, Plus below $1.99 and
/// Pro below $4.99 lose money, and an uncapped free trial is unbounded spend. The trial is
/// therefore limited by actions as well as days.
enum Promo {

    /// Days of Pro unlocked by the trial.
    static let trialDays = 7
    /// Hard action cap during the trial — this is what bounds acquisition cost.
    /// Must match the server's `trial_allowance()`, which is the source of truth.
    static let trialActions = 5
}

extension Entitlement {

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
