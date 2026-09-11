import SwiftUI
import WebKit

/// A request to jump the player to a moment. `nonce` makes repeated taps on the same
/// timestamp still re-trigger a seek (SwiftUI wouldn't otherwise see a change).
struct SeekCommand: Equatable {
    var seconds: Int
    var nonce: Int
}

/// Embeds a YouTube video inside the app so a saved video recipe plays in place instead of
/// bouncing the user out to the YouTube app or Safari. A `SeekCommand` jumps to a step's
/// moment and starts playing.
///
/// The video is hosted in an HTML shell running the IFrame Player API, with a real
/// `youtube-nocookie.com` base URL — **not** by pointing the web view straight at the embed
/// URL. Loading the embed as a top-level document gives it no usable origin/referrer, which
/// is why many videos answer with "Video unavailable" or simply never start. The shell also
/// means a seek is a `seekTo` call rather than a full page reload, so jumping between steps
/// no longer restarts the player.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    /// nil = show the video cued at the start; non-nil = seek there and play.
    var seek: SeekCommand? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(
            Self.html(videoID: videoID),
            baseURL: URL(string: "https://www.youtube-nocookie.com")
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let seek, seek != context.coordinator.lastSeek else { return }
        context.coordinator.lastSeek = seek
        context.coordinator.run(on: webView, seconds: seek.seconds)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastSeek: SeekCommand?
        private var ready = false
        /// A seek that arrived before the player finished loading, replayed on ready.
        private var pending: Int?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The API needs a beat after the script loads before it accepts commands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak webView] in
                guard let self else { return }
                self.ready = true
                if let seconds = self.pending, let webView {
                    self.pending = nil
                    self.seek(webView, to: seconds)
                }
            }
        }

        func run(on webView: WKWebView, seconds: Int) {
            guard ready else { pending = seconds; return }
            seek(webView, to: seconds)
        }

        private func seek(_ webView: WKWebView, to seconds: Int) {
            webView.evaluateJavaScript(
                "if (window.player && player.seekTo) { player.seekTo(\(max(0, seconds)), true); player.playVideo(); }"
            )
        }
    }

    private static func html(videoID: String) -> String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html,body{margin:0;height:100%;background:#000;overflow:hidden}
          #player{position:absolute;inset:0;width:100%;height:100%}
        </style></head><body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player;
          function onYouTubeIframeAPIReady(){
            player = new YT.Player('player', {
              videoId: '\(videoID)',
              playerVars: {playsinline:1, rel:0, modestbranding:1, iv_load_policy:3}
            });
          }
        </script></body></html>
        """
    }
}
