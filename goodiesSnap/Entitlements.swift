import Foundation

/// What the user is entitled to run, and how much of it they've used.
///
/// Quotas are the thing that keeps AI cost bounded — see the pricing analysis. Every paid tier's
/// break-even sits several times above its cap, so a maxed-out subscriber is still profitable.
///
/// NOTE: this counter lives on the device, which makes it a *product* control, not a security
/// control — a determined user can reset it. It becomes authoritative once the AI calls move
/// behind the InsForge proxy and the server owns the count.
struct Entitlement: Codable, Equatable {

    enum Plan: String, Codable, CaseIterable {
        case free, plus, pro

        var title: String {
            switch self {
            case .free: return "Free"
            case .plus: return "Plus"
            case .pro: return "Pro"
            }
        }

        /// Actions included per month.
        var allowance: Int {
            switch self {
            case .free: return 5
            case .plus: return 100
            case .pro: return 400
            }
        }

        /// Scanning a dish with the camera is the Pro differentiator.
        var allowsCamera: Bool { self == .pro }

        var priceLabel: String {
            switch self {
            case .free: return "$0"
            case .plus: return "$9.99"
            case .pro: return "$12.99"
            }
        }

        /// Yearly price — a real ~33-36% saving against twelve monthly payments.
        var annualPriceLabel: String {
            switch self {
            case .free: return "$0"
            case .plus: return "$79.99"
            case .pro: return "$99.99"
            }
        }

        var annualLabel: String {
            switch self {
            case .free: return ""
            case .plus: return "or $79.99/year"
            case .pro: return "or $99.99/year"
            }
        }

        var isPaid: Bool { self != .free }

        /// Every plan's allowance refreshes monthly, Free included.
        var refreshesMonthly: Bool { true }

        var blurb: String {
            switch self {
            case .free: return "5 saves a month from links, video & text"
            case .plus: return "100 saves a month from links, video & text"
            case .pro: return "400 AI actions a month, camera included"
            }
        }

        var perks: [String] {
            switch self {
            case .free:
                return ["Save from links, video & text",
                        "Unlimited recipes you add yourself",
                        "Shopping list, meal plan & community"]
            case .plus:
                return ["20× more saves from links, video & text",
                        "Everything in Free"]
            case .pro:
                return ["Scan a dish with your camera",
                        "400 AI actions a month",
                        "Everything in Plus"]
            }
        }
    }

    var plan: Plan = .free
    /// Actions consumed in the current period.
    var used: Int = 0
    /// Extra actions bought as a top-up; spent only after the included allowance runs out.
    var topUp: Int = 0
    /// "yyyy-MM" the `used` counter belongs to, so paid plans roll over cleanly.
    var period: String = Entitlement.currentPeriod
    /// First launch, which anchors the welcome offer window.
    var installedAt: Date = Date()
    /// End of the Pro trial, if one was started.
    var trialUntil: Date?
    /// True when the active plan was bought on the yearly price, so the paywall can mark
    /// the right card as the current one.
    var annualBilling: Bool = false
    /// Set once an intro-priced month has been taken, so it can't be reused.
    var introUsed: Bool = false
    /// Promo codes already redeemed, so each only counts once.
    var redeemed: [String] = []

    static var currentPeriod: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    /// Rolls the counter into the current month for plans that refresh.
    mutating func rollOverIfNeeded() {
        let now = Entitlement.currentPeriod
        guard period != now else { return }
        period = now
        if plan.refreshesMonthly { used = 0 }
    }

    /// The trial grants Pro's capabilities but its own, much smaller allowance — that cap is
    /// what keeps free-trial acquisition cost bounded.
    var included: Int { onProTrial ? Promo.trialActions : plan.allowance }
    var includedRemaining: Int { max(0, included - used) }
    var remaining: Int { includedRemaining + topUp }
    var hasActionsLeft: Bool { remaining > 0 }

    /// Spends one action, taking from the included allowance first, then top-ups.
    mutating func consume() {
        if includedRemaining > 0 {
            used += 1
        } else if topUp > 0 {
            topUp -= 1
        }
    }

    /// Adopts the server's count. The proxy meters in Postgres, so once a call returns the
    /// device mirrors that number rather than its own optimistic one.
    mutating func syncRemaining(_ serverRemaining: Int) {
        let clamped = max(0, serverRemaining)
        if clamped >= topUp {
            used = max(0, included - (clamped - topUp))
        } else {
            // Server says less than our top-up balance: allowance is spent, top-ups partly gone.
            used = included
            topUp = clamped
        }
    }

    var usageLabel: String {
        if topUp > 0 {
            return "\(includedRemaining) left + \(topUp) topped up"
        }
        return "\(includedRemaining) of \(included) left"
    }

    var renewalLabel: String { "Refreshes at the start of each month" }

    /// The allowance resets on the first of the month — `rollOverIfNeeded()` keys off the
    /// "yyyy-MM" period, so the next reset is the start of the next calendar month.
    var renewsAt: Date {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: 1, to: start) ?? start
    }

    /// Countdown to that reset, for the current plan's card.
    var renewalCountdown: String {
        let seconds = renewsAt.timeIntervalSinceNow
        guard seconds > 0 else { return "Renewing now" }
        let hours = Int(seconds / 3600)
        if hours >= 48 { return "Renews in \(hours / 24) days" }
        if hours >= 24 { return "Renews tomorrow" }
        if hours >= 1 { return "Renews in \(hours) hour\(hours == 1 ? "" : "s")" }
        return "Renews within the hour"
    }
}

/// Why the paywall was shown — lets the screen lead with the right message.
enum PaywallReason: Equatable {
    case outOfActions
    case cameraIsPro
    case upgrade

    var title: String {
        switch self {
        case .outOfActions: return "You've used this month's AI actions"
        case .cameraIsPro: return "Scanning a dish is a Pro feature"
        case .upgrade: return "Do more with goodiesSnap AI"
        }
    }

    var body: String {
        switch self {
        case .outOfActions:
            return "Upgrade for more, or come back next month when your actions refresh. Everything you've already saved stays yours."
        case .cameraIsPro:
            return "Point your camera at any plate and Pro identifies the dish, breaks down what's on it, and writes the recipe."
        case .upgrade:
            return "Save recipes from links, video, and text — or go Pro and scan a dish with your camera."
        }
    }

    /// Which plan the screen should push hardest.
    var highlight: Entitlement.Plan { self == .cameraIsPro ? .pro : .plus }
}

/// Why the sign-up wall appeared, so the auth screen can name what it unlocks.
enum AuthReason: Equatable {
    case general
    case aiFeature
    case scan
    case community
    case upgrade

    var title: String {
        switch self {
        case .general:   return "Create your account"
        case .aiFeature: return "Create an account to use AI"
        case .scan:      return "Create an account to scan dishes"
        case .community: return "Join the community"
        case .upgrade:   return "Create an account to subscribe"
        }
    }

    var blurb: String {
        switch self {
        case .general:
            return "Your recipes, plan and shopping list, synced and safe."
        case .aiFeature:
            return "Saving recipes with AI is tied to your account, so your recipes and monthly allowance follow you to any device."
        case .scan:
            return "Scanning a dish is tied to your account. Create one to start — it takes a moment."
        case .community:
            return "Share dishes, ask questions, cook with other people."
        case .upgrade:
            return "A plan belongs to your account, not this phone — so it follows you to a new device and survives a reinstall."
        }
    }
}
