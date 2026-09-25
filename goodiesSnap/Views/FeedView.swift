import SwiftUI
import PhotosUI

struct FeedView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    @State private var showChannels = false

    var body: some View {
        Group {
            if social.signedIn {
                serverView
            } else {
                AuthView()
            }
        }
        .onAppear {
            if let preset = UserDefaults.standard.string(forKey: "gsFeedFilter") {
                social.pendingFilterSlug = preset
            }
            if social.signedIn && social.posts.isEmpty {
                Task { await social.refresh() }
            }
        }
    }

    // MARK: - Discord-style server layout

    private var serverView: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                hubBar
                channelHeader
                Divider().overlay(Color.fg(0.08))
                chatArea
                messageBar
            }
            .background(Color.gsBg)

            if showChannels {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showChannels = false } }

                channelSidebar
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeOut(duration: 0.25), value: showChannels)
    }

    // MARK: - Hub bar (back + Videos / Community)

    /// The Community hub's switcher. The dock is hidden on this screen, so this bar also
    /// carries the only visible way back to Home.
    private var hubBar: some View {
        HStack(spacing: 14) {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 36, height: 36)
                    .background(Color.fg(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            CommunityTabLabel(title: "Videos", selected: false, dark: false) {
                withAnimation(.easeOut(duration: 0.2)) { store.communityTab = .videos }
            }
            CommunityTabLabel(title: "Community", selected: true, dark: false) {}
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Color.gsBg)
    }

    // MARK: - Channel header

    private var channelHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showChannels.toggle() }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 38, height: 38)
                    .background(Color.fg(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if let groupID = social.feedFilter, groupID != "mine",
               let group = social.group(id: groupID) {
                Text(group.emoji)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name)
                        .font(nunito(16, .extrabold))
                        .lineLimit(1)
                    Text("\(group.member_count) members")
                        .font(nunito(11, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
            } else {
                Image(systemName: "number")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.gsMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(social.feedFilter == "mine" ? "My Groups" : "General")
                        .font(nunito(16, .extrabold))
                        .lineLimit(1)
                    Text("What everyone's cooking")
                        .font(nunito(11, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
            }

            Spacer()

            Menu {
                Button("Sign out", role: .destructive) { social.signOut() }
            } label: {
                Text(String(social.session?.displayName.prefix(1) ?? "?").uppercased())
                    .font(nunito(14, .extrabold))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 36, height: 36)
                    .background(Color.gsPeachSoft)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.gsBg)
    }

    // MARK: - Channel sidebar

    private var channelSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Server header
            HStack(spacing: 10) {
                Text("🍳")
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(Color.gsPeach)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("goodiesSnap")
                    .font(nunito(18, .black))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.fg(0.08)).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // General channels
                    Text("CHANNELS")
                        .font(nunito(11, .extrabold))
                        .foregroundStyle(Color.gsMuted)
                        .kerning(0.8)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    channelRow(emoji: "#", name: "General", id: nil)
                    channelRow(emoji: "📌", name: "My Groups", id: "mine")

                    // Group channels
                    if !social.groups.isEmpty {
                        Text("GROUPS")
                            .font(nunito(11, .extrabold))
                            .foregroundStyle(Color.gsMuted)
                            .kerning(0.8)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 4)

                        ForEach(social.groups) { group in
                            groupChannelRow(group)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 280)
        .background(Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 4)
    }

    private func channelRow(emoji: String, name: String, id: String?) -> some View {
        let active = social.feedFilter == id
        return Button {
            Haptics.tap(.light)
            withAnimation(AppStore.lateralAnimation) {
                social.feedFilter = id
                showChannels = false
            }
        } label: {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(nunito(15, .bold))
                    .foregroundStyle(active ? Color.gsFg : Color.gsMuted)
                    .frame(width: 24)
                Text(name)
                    .font(nunito(14, active ? .extrabold : .semibold))
                    .foregroundStyle(active ? Color.gsFg : Color.fg(0.6))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 38)
            .background(active ? Color.fg(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private func groupChannelRow(_ group: CommunityGroup) -> some View {
        let active = social.feedFilter == group.id
        let joined = social.myGroupIDs.contains(group.id)
        return Button {
            Haptics.tap(.light)
            withAnimation(AppStore.lateralAnimation) {
                social.feedFilter = active ? nil : group.id
                showChannels = false
            }
        } label: {
            HStack(spacing: 10) {
                Text(group.emoji)
                    .font(.system(size: 16))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.name)
                        .font(nunito(14, active ? .extrabold : .semibold))
                        .foregroundStyle(active ? Color.gsFg : Color.fg(0.6))
                        .lineLimit(1)
                    Text("\(group.member_count) members")
                        .font(nunito(10, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                Spacer()
                if !joined {
                    Button {
                        social.toggleMembership(group)
                    } label: {
                        Text("Join")
                            .font(nunito(11, .extrabold))
                            .foregroundStyle(Color.gsDock)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.gsPeach)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(active ? Color.fg(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chat area (messages)

    private var chatArea: some View {
        ScrollView {
            if social.loading {
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonMessage() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            } else if social.visiblePosts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.fg(0.2))
                    Text(social.feedFilter == nil ? "No messages yet" : "No messages in this channel")
                        .font(nunito(16, .extrabold))
                        .foregroundStyle(Color.fg(0.5))
                    Text("Be the first to say something!")
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(social.visiblePosts) { post in
                        MessageRow(post: post)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .refreshable { await social.refresh() }
    }

    // MARK: - Message input bar

    @State private var messageText = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var attachedRecipe: Recipe?
    @State private var pickingRecipe = false

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachedImage != nil || attachedRecipe != nil
    }

    private var messageBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.fg(0.08))

            if let img = attachedImage {
                HStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Button { withAnimation { attachedImage = nil } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.fg(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if let recipe = attachedRecipe {
                HStack(spacing: 10) {
                    CoverImage(url: recipe.imageURL)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(recipe.title)
                        .font(nunito(13, .bold))
                        .lineLimit(1)
                    Spacer()
                    Button { withAnimation { attachedRecipe = nil } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.fg(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if pickingRecipe {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.recipes.prefix(8)) { r in
                            Button {
                                withAnimation { attachedRecipe = r; pickingRecipe = false }
                            } label: {
                                HStack(spacing: 10) {
                                    CoverImage(url: r.imageURL)
                                        .frame(width: 34, height: 34)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(r.title).font(nunito(13, .bold)).lineLimit(1)
                                    Spacer()
                                }
                                .frame(minHeight: 42)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 200)
                .background(Color.fg(0.03))
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.fg(0.35))
                    }

                    TextField("Message #\(channelName)", text: $messageText, axis: .vertical)
                        .font(nunito(14, .semibold))
                        .lineLimit(1...4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.fg(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.fg(0.1), lineWidth: 1)
                )

                HStack(spacing: 4) {
                    Button { withAnimation { pickingRecipe.toggle() } } label: {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(pickingRecipe ? Color.gsPeach : Color.fg(0.35))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    Button { sendPost() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(canSend ? Color.gsPeach : Color.fg(0.15))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend || social.busy)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.gsBg)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickedPhoto = nil
                if let data, let img = UIImage(data: data) {
                    withAnimation { attachedImage = img }
                }
            }
        }
    }

    private var channelName: String {
        if let id = social.feedFilter, id != "mine", let g = social.group(id: id) {
            return g.name.lowercased().replacingOccurrences(of: " ", with: "-")
        }
        return social.feedFilter == "mine" ? "my-groups" : "general"
    }

    private func sendPost() {
        let text = messageText
        messageText = ""
        let img = attachedImage
        let recipe = attachedRecipe
        attachedImage = nil
        attachedRecipe = nil
        pickingRecipe = false
        Task {
            if await social.publish(text: text, image: img, recipe: recipe,
                                     groupID: social.composeGroupID ?? social.feedFilter,
                                     asQuestion: false) {
                store.showToast("Sent")
            }
        }
    }
}

// MARK: - Message row (Discord-style)

struct MessageRow: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    let post: FeedPost

    private var liked: Bool { social.likedPostIDs.contains(post.id) }
    private var mine: Bool { post.author_id == social.session?.userID }
    private var group: CommunityGroup? { social.group(id: post.group_id) }

    var body: some View {
        if post.isDeleted { deletedRow } else { messageRow }
    }

    private var deletedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(post.author_name.prefix(1)).uppercased())
                .font(nunito(14, .extrabold))
                .foregroundStyle(Color.gsFg)
                .frame(width: 40, height: 40)
                .background(authorColor.opacity(0.5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(post.author_name)
                        .font(nunito(14, .extrabold))
                        .foregroundStyle(Color.gsMuted)
                    Text(post.relativeTime)
                        .font(nunito(11, .semibold))
                        .foregroundStyle(Color.gsMuted)
                    Spacer()
                    if mine {
                        Menu {
                            Button("Remove", role: .destructive) { social.deletePost(post) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.fg(0.25))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Deleted message options")
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "nosign")
                        .font(.system(size: 12, weight: .semibold))
                    Text(mine ? "You deleted this message" : "This message was deleted")
                        .font(nunito(14, .semibold))
                        .italic()
                }
                .foregroundStyle(Color.gsMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.gsBg)
    }

    private var messageRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(post.author_name.prefix(1)).uppercased())
                .font(nunito(14, .extrabold))
                .foregroundStyle(Color.gsFg)
                .frame(width: 40, height: 40)
                .background(authorColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(post.author_name)
                        .font(nunito(14, .extrabold))
                        .foregroundStyle(nameColor)
                    Text(post.relativeTime)
                        .font(nunito(11, .semibold))
                        .foregroundStyle(Color.gsMuted)
                    Spacer()
                    Menu {
                        if mine {
                            Button("Delete", role: .destructive) { social.deletePost(post) }
                        } else {
                            Button { social.startReport(.post(post)) } label: {
                                Label("Report", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                social.block(userID: post.author_id)
                            } label: {
                                Label("Block", systemImage: "hand.raised")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.fg(0.25))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(mine ? "Post options" : "Report or block")
                }

                if !post.caption.isEmpty {
                    if post.isQuestion {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.gsAccentInk)
                                .padding(.top, 1)
                            Text(post.caption)
                                .font(nunito(14, .extrabold))
                        }
                    } else {
                        Text(post.caption)
                            .font(nunito(14, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let recipe = post.recipe {
                    Button { store.open(recipe) } label: {
                        recipeEmbed(recipe)
                    }
                    .buttonStyle(PressableStyle(scale: 0.985))
                    .padding(.top, 4)
                } else if post.image_url != nil, let url = post.imageURL {
                    CoverImage(url: url)
                        .frame(maxWidth: 320, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 4)
                }

                // Reactions bar
                HStack(spacing: 4) {
                    Button { social.toggleLike(post) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: liked ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .semibold))
                            if post.like_count > 0 {
                                Text("\(post.like_count)")
                                    .font(nunito(11.5, .extrabold))
                            }
                        }
                        .foregroundStyle(liked ? Color.gsPeach : Color.fg(0.4))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(liked ? Color.gsPeach.opacity(0.12) : Color.fg(0.05))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { social.openComments(post) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 12, weight: .semibold))
                            if post.comment_count > 0 {
                                Text("\(post.comment_count)")
                                    .font(nunito(11.5, .extrabold))
                            }
                        }
                        .foregroundStyle(Color.fg(0.4))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Color.fg(0.05))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if let recipe = post.recipe, !mine {
                        Button {
                            var copy = recipe
                            copy.id = "r\(Int(Date().timeIntervalSince1970 * 1000))"
                            copy.favorite = false
                            copy.source = "Community · \(post.author_name)"
                            withAnimation(AppStore.pushAnimation) { store.recipes.insert(copy, at: 0) }
                            store.persist()
                            store.showToast("Saved to your library")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Save")
                                    .font(nunito(11.5, .extrabold))
                            }
                            .foregroundStyle(Color.fg(0.4))
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(Color.fg(0.05))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.gsBg)
    }

    private func recipeEmbed(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: recipe.imageURL)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.cuisine.uppercased())
                    .font(nunito(9.5, .extrabold))
                    .tracking(1)
                    .foregroundStyle(Color.gsMuted)
                Text(recipe.title)
                    .font(nunito(14, .extrabold))
                    .foregroundStyle(Color.gsFg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Label("\(recipe.totalMinutes) min", systemImage: "clock.fill")
                    Label("Serves \(recipe.servings)", systemImage: "person.2.fill")
                }
                .font(nunito(11, .semibold))
                .foregroundStyle(Color.gsMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 340)
        .background(Color.fg(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.fg(0.08), lineWidth: 1)
        )
    }

    private var authorColor: Color {
        let colors: [Color] = [.gsPeachSoft, Color(hex: 0xD4E8D0), Color(hex: 0xD0DCE8), Color(hex: 0xE8D0E4), Color(hex: 0xE8E0D0)]
        let hash = abs(post.author_id.hashValue)
        return colors[hash % colors.count]
    }

    private var nameColor: Color {
        let colors: [Color] = [Color(hex: 0xC06B00), Color(hex: 0x2D8C3C), Color(hex: 0x3B6BA5), Color(hex: 0x8B3BAB), Color(hex: 0xA57B3B)]
        let hash = abs(post.author_id.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Skeleton message

private struct SkeletonMessage: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.fg(0.08))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.fg(0.1))
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.fg(0.06))
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.fg(0.06))
                    .frame(width: 200, height: 14)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Composer sheet (kept for share-from-recipe flow)

struct ComposerSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    @State private var text = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var attachedRecipe: Recipe?
    @State private var pickingRecipe = false
    @FocusState private var focused: Bool

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil || attachedRecipe != nil
    }

    var body: some View {
        BottomSheet(onDismiss: dismiss) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Create post")
                        .font(nunito(21, .extrabold))
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.gsFg)
                            .frame(width: 32, height: 32)
                            .background(Color.gsFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        audienceChip("🌍 Everyone", id: nil)
                        ForEach(social.groups.filter { social.myGroupIDs.contains($0.id) }) { g in
                            audienceChip("\(g.emoji) \(g.name)", id: g.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(.top, 12)

                TextField(
                    "", text: $text,
                    prompt: Text(social.composeAsQuestion ? "What do you want to ask?" : "Share what you're cooking…").foregroundStyle(Color.gsMuted),
                    axis: .vertical
                )
                .font(nunito(15, .semibold))
                .focused($focused)
                .lineLimit(4...8)
                .padding(14)
                .background(Color.gsFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 12)

                if let image {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Button { withAnimation { self.image = nil } } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 28, height: 28)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                    .padding(.top, 10)
                }

                if let recipe = attachedRecipe {
                    ZStack(alignment: .topTrailing) {
                        RecipeAttachment(recipe: recipe)
                        Button { withAnimation { attachedRecipe = nil } } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.gsFg)
                                .frame(width: 28, height: 28)
                                .background(Color.gsCard)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                    .padding(.top, 10)
                }

                if pickingRecipe {
                    VStack(spacing: 0) {
                        ForEach(store.recipes.prefix(8)) { r in
                            Button {
                                withAnimation { attachedRecipe = r; pickingRecipe = false }
                            } label: {
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
                    }
                    .padding(.horizontal, 12)
                    .background(Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 10)
                }

                HStack(spacing: 8) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        toolChip("photo.fill", "Photo", active: image != nil)
                    }
                    Button { withAnimation { pickingRecipe.toggle() } } label: {
                        toolChip("book.closed.fill", "Recipe", active: attachedRecipe != nil)
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation { social.composeAsQuestion.toggle() } } label: {
                        toolChip("questionmark.bubble.fill", "Question", active: social.composeAsQuestion)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 12)

                if !social.errorMessage.isEmpty {
                    Text(social.errorMessage)
                        .font(nunito(12, .bold))
                        .foregroundStyle(Color.gsAccentInk)
                        .padding(.top, 8)
                }

                Button {
                    focused = false
                    Task {
                        if await social.publish(text: text, image: image, recipe: attachedRecipe,
                                                groupID: social.composeGroupID, asQuestion: social.composeAsQuestion) {
                            store.showToast("Posted to the community")
                        }
                    }
                } label: {
                    Group {
                        if social.busy { ProgressView().tint(Color.white) }
                        else { Text("Post").font(nunito(15, .extrabold)) }
                    }
                    .foregroundStyle(Color.gsFg)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(!canPost || social.busy)
                .opacity(canPost ? 1 : 0.5)
                .padding(.top, 14)
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickedPhoto = nil
                if let data, let img = UIImage(data: data) {
                    withAnimation { image = img }
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(AppStore.sheetAnimation) { social.composing = false }
    }

    private func audienceChip(_ label: String, id: String?) -> some View {
        let active = social.composeGroupID == id
        return Button { withAnimation(AppStore.lateralAnimation) { social.composeGroupID = id } } label: {
            Text(label)
                .font(nunito(12.5, .extrabold))
                .foregroundStyle(active ? Color.white : Color.gsFg)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(active ? Color.gsDock : Color.gsFill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toolChip(_ system: String, _ label: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.gsDock : Color.gsPeach)
            Text(label)
                .font(nunito(12.5, .extrabold))
                .foregroundStyle(active ? Color.gsDock : Color.gsFg)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(active ? Color.gsPeach : Color.gsCard)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.gsFill, lineWidth: active ? 0 : 1.5))
    }
}

// MARK: - Recipe attachment (shared)

struct RecipeAttachment: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: recipe.imageURL)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.cuisine.uppercased())
                    .font(nunito(10, .extrabold))
                    .tracking(1.2)
                    .foregroundStyle(Color.gsMuted)
                Text(recipe.title)
                    .font(nunito(15.5, .extrabold))
                    .foregroundStyle(Color.gsFg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Label("\(recipe.totalMinutes) min", systemImage: "clock.fill")
                    Label("Serves \(recipe.servings)", systemImage: "person.2.fill")
                }
                .font(nunito(11.5, .semibold))
                .foregroundStyle(Color.gsMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.gsMuted)
        }
        .padding(10)
        .background(Color.gsFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Comments (discussion) sheet

struct CommentsSheet: View {
    @EnvironmentObject var social: SocialStore
    @State private var draft = ""

    private var isQuestion: Bool { social.commentsFor?.isQuestion ?? false }

    var body: some View {
        BottomSheet(onDismiss: { social.closeComments() }) {
            VStack(alignment: .leading, spacing: 0) {
                if let post = social.commentsFor {
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(post.author_name.prefix(1)).uppercased())
                            .font(nunito(13, .extrabold))
                            .frame(width: 34, height: 34)
                            .background(Color.gsPeachSoft)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.author_name).font(nunito(13, .extrabold))
                            if !post.caption.isEmpty {
                                Text(post.caption)
                                    .font(nunito(14, isQuestion ? .extrabold : .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let r = post.recipe {
                                Text(r.title).font(nunito(14, .extrabold))
                            }
                        }
                    }
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.gsFill).frame(height: 1) }
                }

                Text(isQuestion ? "Answers" : "Thread")
                    .font(nunito(15, .extrabold))
                    .padding(.top, 14)

                if social.comments.isEmpty {
                    Text(isQuestion ? "No answers yet — know this one?" : "No replies yet — start the thread.")
                        .font(nunito(12.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                ForEach(social.comments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(comment.author_name.prefix(1)).uppercased())
                            .font(nunito(12, .extrabold))
                            .frame(width: 30, height: 30)
                            .background(Color.gsFill)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(comment.author_name)
                                .font(nunito(12.5, .extrabold))
                            Text(comment.body)
                                .font(nunito(13.5, .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gsFill)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if comment.author_id != social.session?.userID, let post = social.commentsFor {
                            Menu {
                                Button {
                                    social.startReport(.comment(comment, postID: post.id))
                                } label: {
                                    Label("Report", systemImage: "flag")
                                }
                                Button(role: .destructive) {
                                    social.block(userID: comment.author_id)
                                } label: {
                                    Label("Block \(comment.author_name)", systemImage: "hand.raised")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.gsMuted)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Report or block")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                HStack(spacing: 10) {
                    TextField("", text: $draft, prompt: Text(isQuestion ? "Write an answer…" : "Reply…").foregroundStyle(Color.gsMuted))
                        .font(nunito(13.5, .semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .background(Color.gsFill)
                        .clipShape(Capsule())
                        .onSubmit { submit() }
                    Button { submit() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.gsDock)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(PeachButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 14)
            }
        }
    }

    private func submit() {
        let text = draft
        draft = ""
        Task { await social.addComment(text) }
    }
}

// MARK: - Share-to-feed sheet

struct ShareSheet: View {
    @EnvironmentObject var social: SocialStore
    @State private var caption = ""

    var body: some View {
        BottomSheet(onDismiss: { withAnimation(AppStore.sheetAnimation) { social.sharing = nil } }) {
            if let recipe = social.sharing {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Share to community")
                        .font(nunito(21, .extrabold))
                    RecipeAttachment(recipe: recipe)
                        .padding(.top, 12)

                    TextField(
                        "", text: $caption,
                        prompt: Text("Say something about it…").foregroundStyle(Color.gsMuted),
                        axis: .vertical
                    )
                    .font(nunito(13.5, .semibold))
                    .lineLimit(3...3)
                    .padding(14)
                    .background(Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 12)

                    Button {
                        Task { _ = await social.share(recipe: recipe, caption: caption) }
                    } label: {
                        Group {
                            if social.busy { ProgressView().tint(Color.white) }
                            else { Text("Post").font(nunito(15, .extrabold)) }
                        }
                        .foregroundStyle(Color.gsFg)
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(DarkButtonStyle())
                    .disabled(social.busy)
                    .padding(.top, 14)
                }
            }
        }
    }
}

// MARK: - Report sheet

struct ReportSheet: View {
    @EnvironmentObject var social: SocialStore

    @State private var reason: SocialAPI.ReportReason = .spam
    @State private var note: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { social.cancelReport() }

            VStack(alignment: .leading, spacing: 14) {
                Capsule()
                    .fill(Color.gsFill)
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                Text("Report content")
                    .font(nunito(20, .black))
                Text("Tell us what's wrong with this \(targetNoun). Our team reviews reports within 24 hours.")
                    .font(nunito(13, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(SocialAPI.ReportReason.allCases) { option in
                        Button {
                            Haptics.tap(.light)
                            reason = option
                        } label: {
                            HStack {
                                Text(option.label)
                                    .font(nunito(14, reason == option ? .extrabold : .semibold))
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.gsAccentInk)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if option != SocialAPI.ReportReason.allCases.last {
                            Divider().overlay(Color.gsBg)
                        }
                    }
                }
                .background(Color.gsFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                TextField("", text: $note, prompt: Text("Anything else? (optional)").foregroundStyle(Color.gsMuted), axis: .vertical)
                    .font(nunito(13.5, .semibold))
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 10) {
                    Button("Cancel") { social.cancelReport() }
                        .font(nunito(14, .extrabold))
                        .buttonStyle(PressableStyle())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gsFill)
                        .clipShape(Capsule())

                    Button {
                        let chosen = reason, text = note
                        Task { await social.submitReport(reason: chosen, note: text) }
                    } label: {
                        Text(social.busy ? "Sending…" : "Submit report")
                            .font(nunito(14, .extrabold))
                            .foregroundStyle(Color.gsFg)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(DarkButtonStyle())
                    .disabled(social.busy)
                }

                if let target = social.reporting {
                    Button(role: .destructive) {
                        let author = target.authorID
                        social.cancelReport()
                        social.block(userID: author)
                    } label: {
                        Text("Also block \(target.authorName)")
                            .font(nunito(13, .extrabold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
            .background(Color.gsCard)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .transition(.move(edge: .bottom))
        }
    }

    private var targetNoun: String {
        if case .comment = social.reporting { return "comment" }
        return "post"
    }
}
