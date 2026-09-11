import SwiftUI
import PhotosUI
import AVFoundation

/// Bottom sheet for posting a reel: pick a video from the library, add a caption, optionally
/// link one of your recipes, and publish. A poster frame and duration are pulled from the clip
/// so the feed has a thumbnail before playback.
struct ReelComposeSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    @State private var pickedVideo: PhotosPickerItem?
    @State private var videoData: Data?
    @State private var thumbnail: UIImage?
    @State private var duration: Int?
    @State private var loadingVideo = false
    @State private var caption = ""
    @State private var attachedRecipe: Recipe?
    @State private var pickingRecipe = false
    @FocusState private var focused: Bool

    private var canPost: Bool { videoData != nil && !social.reelUploading }

    var body: some View {
        BottomSheet(onDismiss: dismiss) {
            VStack(alignment: .leading, spacing: 0) {
                header

                videoWell
                    .padding(.top, 14)

                TextField("", text: $caption,
                          prompt: Text("Say something about this dish…").foregroundStyle(Color.gsMuted),
                          axis: .vertical)
                    .font(nunito(15, .semibold))
                    .focused($focused)
                    .lineLimit(2...5)
                    .padding(14)
                    .background(Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 12)

                if pickingRecipe {
                    recipePicker.padding(.top, 10)
                }

                HStack(spacing: 8) {
                    Button { withAnimation { pickingRecipe.toggle() } } label: {
                        chip("book.closed.fill", attachedRecipe?.title ?? "Link a recipe",
                             active: attachedRecipe != nil)
                    }
                    .buttonStyle(.plain)
                    if attachedRecipe != nil {
                        Button { withAnimation { attachedRecipe = nil } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.gsMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, 12)

                if !social.errorMessage.isEmpty {
                    Text(social.errorMessage)
                        .font(nunito(12, .bold)).foregroundStyle(Color.gsAccentInk)
                        .padding(.top, 8)
                }

                Button(action: post) {
                    Group {
                        if social.reelUploading { ProgressView().tint(.white) }
                        else { Text("Post reel").font(nunito(15, .extrabold)) }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(DarkButtonStyle())
                .opacity(canPost ? 1 : 0.5)
                .disabled(!canPost)
                .padding(.top, 14)
            }
        }
        .onChange(of: pickedVideo) { _, item in loadVideo(item) }
    }

    private var header: some View {
        HStack {
            Text("New reel").font(nunito(21, .extrabold))
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.gsFg)
                    .frame(width: 32, height: 32).background(Color.gsFill).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var videoWell: some View {
        PhotosPicker(selection: $pickedVideo, matching: .videos) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.gsFill)
                    .frame(height: 190)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable().scaledToFill()
                        .frame(height: 190).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if let duration {
                                Text(timeLabel(duration))
                                    .font(nunito(11, .extrabold)).foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .padding(10)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Text("Change")
                                .font(nunito(11, .extrabold)).foregroundStyle(.black)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.white, in: Capsule())
                                .padding(10)
                        }
                } else if loadingVideo {
                    ProgressView().tint(Color.gsFg)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 30, weight: .semibold)).foregroundStyle(Color.gsFg)
                        Text("Choose a clip").font(nunito(14, .extrabold)).foregroundStyle(Color.gsFg)
                        Text("A short vertical video works best")
                            .font(nunito(11.5, .semibold)).foregroundStyle(Color.gsMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var recipePicker: some View {
        VStack(spacing: 0) {
            ForEach(store.recipes.prefix(8)) { r in
                Button { withAnimation { attachedRecipe = r; pickingRecipe = false } } label: {
                    HStack(spacing: 10) {
                        CoverImage(url: r.imageURL)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(r.title).font(nunito(13.5, .bold)).lineLimit(1)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            if store.recipes.isEmpty {
                Text("Save a recipe first to link it.")
                    .font(nunito(12.5, .semibold)).foregroundStyle(Color.gsMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 12)
        .background(Color.gsFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chip(_ system: String, _ label: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system).font(.system(size: 12, weight: .bold))
            Text(label).font(nunito(12.5, .extrabold)).lineLimit(1)
        }
        .foregroundStyle(active ? .white : Color.gsFg)
        .padding(.horizontal, 14).frame(height: 38)
        .background(active ? Color.gsDock : Color.gsCard)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.gsFg.opacity(active ? 0 : 0.12), lineWidth: 1))
    }

    // MARK: - Actions

    private func loadVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingVideo = true
        thumbnail = nil
        Task {
            defer { loadingVideo = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    store.showToast("Couldn't load that video — try another")
                    return
                }
                videoData = data
                extractPoster(from: data)
            } catch {
                store.showToast("Couldn't load that video — try another")
            }
        }
    }

    /// Writes the clip to a temp file so AVFoundation can read a poster frame and its length.
    private func extractPoster(from data: Data) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-\(UUID().uuidString).mp4")
        do {
            try data.write(to: url)
            let asset = AVURLAsset(url: url)
            Task {
                let seconds = (try? await asset.load(.duration)).map { Int(CMTimeGetSeconds($0).rounded()) }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                let cgImage = try? await generator.image(at: time).image
                await MainActor.run {
                    if let seconds { self.duration = seconds }
                    if let cgImage { self.thumbnail = UIImage(cgImage: cgImage) }
                }
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            // A missing poster is fine — the feed falls back to a black frame.
        }
    }

    private func post() {
        guard let videoData else { return }
        focused = false
        Task {
            if await social.publishReel(videoData: videoData, thumbnail: thumbnail,
                                        caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                                        recipe: attachedRecipe, duration: duration) {
                store.showToast("Your reel is live")
            }
        }
    }

    private func dismiss() {
        social.errorMessage = ""
        withAnimation(AppStore.sheetAnimation) { social.composingReel = false }
    }

    private func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
