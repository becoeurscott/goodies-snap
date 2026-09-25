import Foundation

/// Where the published Terms and Privacy Policy live.
///
/// One place, because these URLs are referenced from sign-up, the paywall and Profile, and
/// App Review clicks every one of them — a link that 404s is a rejection. Point these at a
/// custom domain once one is set up; the pages are deployed from `site/`.
enum Legal {
    static let site = URL(string: "https://goodiessnap.com")!
    static let terms = URL(string: "https://goodiessnap.com/terms.html")!
    static let privacy = URL(string: "https://goodiessnap.com/privacy.html")!
    static let support = URL(string: "mailto:support@goodiessnap.com")!
}
