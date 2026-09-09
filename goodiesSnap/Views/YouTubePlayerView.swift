import SwiftUI
import WebKit

/// A request to jump the player to a moment. `nonce` makes repeated taps on the same
/// timestamp still re-trigger a seek (SwiftUI wouldn't otherwise see a change).
struct SeekCommand: Equatable {
    var seconds: Int
    var nonce: Int
}

/// Embeds a YouTube video inside the app so a saved video recipe plays in place instead of
/// bouncing the user out to the YouTube app or Safari. Uses the privacy-preserving
/// `youtube-nocookie` iframe embed; inline playback keeps it in the card. A `SeekCommand`
/// jumps to a step's moment and starts playing.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    /// nil = just show the video paused at the start; non-nil = seek there and play.
    var seek: SeekCommand? = nil

    private func embedURL(start: Int?, autoplay: Bool) -> URL? {
        var s = "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1"
        if let start, start > 0 { s += "&start=\(start)" }
        if autoplay { s += "&autoplay=1" }
        return URL(string: s)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        if let url = embedURL(start: nil, autoplay: false) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload to the requested moment only when a new seek arrives.
        guard let seek, seek != context.coordinator.lastSeek else { return }
        context.coordinator.lastSeek = seek
        if let url = embedURL(start: seek.seconds, autoplay: true) {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastSeek: SeekCommand?
    }
}
