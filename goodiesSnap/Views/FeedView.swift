import SwiftUI
import PhotosUI

struct FeedView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    var body: some View {
        Group {
            if social.signedIn {
                feed
            } else {
                AuthView()
            }
        }
        .onAppear {
            // UI-automation hook: `-gsFeedFilter mine|<groupSlug>` preselects a filter.
            if let preset = UserDefaults.standard.string(forKey: "gsFeedFilter") {
                social.pendingFilterSlug = preset
            }
            if social.signedIn && social.posts.isEmpty {
                Task { await social.refresh() }
            }
        }
    }

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Community")
                            .font(nunito(29, .black))
                        Text("What everyone's cooking")
                            .font(nunito(13, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    Spacer()
                    Menu {
                        Button("Sign out", role: .destructive) { social.signOut() }
                    } label: {
                        Text(String(social.session?.displayName.prefix(1) ?? "?").uppercased())
                            .font(nunito(15, .extrabold))
                            .foregroundStyle(Color.gsFg)
                            .frame(width: 44, height: 44)
                            .background(Color.gsPeachSoft)
                            .clipShape(Circle())
                    }
                }

                ComposerBar()
                    .padding(.top, 16)

                GroupsStrip()
                    .padding(.top, 22)

                FeedFilterTabs()
                    .padding(.top, 20)

                if social.loading {
                    // Skeletons rather than a bare spinner: the shape of what's coming
                    // makes the wait feel shorter and stops the layout jumping.
                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in SkeletonPostCard() }
                    }
                    .padding(.top, 14)
                } else if social.visiblePosts.isEmpty {
                    VStack(spacing: 6) {
                        Text(social.feedFilter == nil ? "Nothing here yet" : "No posts here yet")
                            .font(nunito(19, .extrabold))
                            .foregroundStyle(Color.fg(0.7))
                        Text(social.feedFilter == "mine"
                             ? "Join a group above to see its posts."
                             : "Be the first — say hi, ask a question, or share a dish.")
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }

                VStack(spacing: 18) {
                    ForEach(social.visiblePosts) { post in
                        FeedPostCard(post: post)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .padding(.top, 16)
                .animation(AppStore.lateralAnimation, value: social.visiblePosts)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 116)
        }
        .background(Color.gsBg)
        .refreshable { await social.refresh() }
    }
}

// MARK: - Composer bar ("What's cooking?")

struct ComposerBar: View {
    @EnvironmentObject var social: SocialStore

    var body: some View {
        VStack(spacing: 12) {
            Button {
                open(groupPreset: (social.feedFilter == "mine") ? nil : social.feedFilter)
            } label: {
                HStack(spacing: 12) {
                    Text(String(social.session?.displayName.prefix(1) ?? "?").uppercased())
                        .font(nunito(14, .extrabold))
                        .frame(width: 38, height: 38)
                        .background(Color.gsPeachSoft)
                        .clipShape(Circle())
                    Text("What's cooking, \(social.session?.displayName.split(separator: " ").first.map(String.init) ?? "chef")?")
                        .font(nunito(14, .semibold))
                        .foregroundStyle(Color.gsMuted)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 54)
                .background(Color.gsFill)
                .clipShape(Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.985))

            HStack(spacing: 8) {
                composerAction("photo.fill", "Photo") { open(groupPreset: nil) }
                composerAction("questionmark.bubble.fill", "Ask") { open(groupPreset: nil, question: true) }
                composerAction("book.closed.fill", "Recipe") { open(groupPreset: nil) }
            }
        }
        .padding(14)
        .softCard(radius: 24)
    }

    private func open(groupPreset: String?, question: Bool = false) {
        social.composeGroupID = groupPreset
        social.composeAsQuestion = question
        withAnimation(AppStore.sheetAnimation) { social.composing = true }
    }

    private func composerAction(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gsAccentInk)
                Text(label)
                    .font(nunito(13, .extrabold))
                    .foregroundStyle(Color.gsFg)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.gsCard)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gsFill, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }
}

// MARK: - Groups strip

struct GroupsStrip: View {
    @EnvironmentObject var social: SocialStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Groups")
                    .font(nunito(19, .extrabold))
                Text("\(social.myGroupIDs.count)")
                    .font(nunito(10, .black))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 22, height: 22)
                    .background(Color.gsPeach)
                    .clipShape(Circle())
                Spacer()
                Text("joined")
                    .font(nunito(12.5, .bold))
                    .foregroundStyle(Color.gsMuted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(social.groups) { group in
                        GroupTile(group: group)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, -2)
        }
    }
}

struct GroupTile: View {
    @EnvironmentObject var social: SocialStore
    let group: CommunityGroup

    private var joined: Bool { social.myGroupIDs.contains(group.id) }
    private var selected: Bool { social.feedFilter == group.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.emoji)
                    .font(.system(size: 26))
                Spacer()
                Button { social.toggleMembership(group) } label: {
                    Text(joined ? "Joined" : "Join")
                        .font(nunito(11.5, .extrabold))
                        .foregroundStyle(Color.gsDock)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .background(joined ? Color.gsFill : Color.gsPeach)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
            }
            Text(group.name)
                .font(nunito(14, .extrabold))
                .lineLimit(1)
            Text("\(group.member_count) members · \(group.post_count) posts")
                .font(nunito(11, .semibold))
                .foregroundStyle(Color.gsMuted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 176, alignment: .leading)
        .background(selected ? Color.gsPeachSoft : Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(selected ? Color.gsPeach : Color.clear, lineWidth: 2))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap(.light)
            withAnimation(AppStore.lateralAnimation) {
                social.feedFilter = selected ? nil : group.id
            }
        }
    }
}

// MARK: - Filter tabs

struct FeedFilterTabs: View {
    @EnvironmentObject var social: SocialStore

    var body: some View {
        HStack(spacing: 8) {
            tab("For you", value: nil)
            tab("My groups", value: "mine")
            if let id = social.feedFilter, id != "mine", let g = social.group(id: id) {
                tab("\(g.emoji) \(g.name)", value: id)
            }
            Spacer()
        }
    }

    private func tab(_ label: String, value: String?) -> some View {
        let active = social.feedFilter == value
        return Button {
            Haptics.tap(.light)
            withAnimation(AppStore.lateralAnimation) { social.feedFilter = value }
        } label: {
            Text(label)
                .font(nunito(13, .extrabold))
                .foregroundStyle(active ? Color.white : Color.gsFg)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(active ? Color.gsDock : Color.gsCard)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(active ? 0 : 0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }
}

// MARK: - Post card

struct FeedPostCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    let post: FeedPost

    private var liked: Bool { social.likedPostIDs.contains(post.id) }
    private var mine: Bool { post.author_id == social.session?.userID }
    private var group: CommunityGroup? { social.group(id: post.group_id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String(post.author_name.prefix(1)).uppercased())
                    .font(nunito(14, .extrabold))
                    .frame(width: 38, height: 38)
                    .background(Color.gsPeachSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(post.author_name)
                            .font(nunito(14, .extrabold))
                        if let group {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.gsMuted)
                            Text("\(group.emoji) \(group.name)")
                                .font(nunito(13, .bold))
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(post.relativeTime)
                        if post.isQuestion {
                            Text("· asked a question")
                        } else if post.kind == "recipe" {
                            Text("· shared a recipe")
                        }
                    }
                    .font(nunito(11, .semibold))
                    .foregroundStyle(Color.gsMuted)
                }
                Spacer()
                // Every post carries this menu, not just your own: reporting and
                // blocking have to be reachable from the content itself.
                Menu {
                    if mine {
                        Button("Delete post", role: .destructive) { social.deletePost(post) }
                    } else {
                        Button {
                            social.startReport(.post(post))
                        } label: {
                            Label("Report post", systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            social.block(userID: post.author_id)
                        } label: {
                            Label("Block \(post.author_name)", systemImage: "hand.raised")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(mine ? "Post options" : "Report or block")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            if !post.caption.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if post.isQuestion {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.gsAccentInk)
                            .padding(.top, 2)
                    }
                    Text(post.caption)
                        .font(nunito(post.isQuestion ? 16 : 14.5, post.isQuestion ? .extrabold : .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            if let recipe = post.recipe {
                Button { store.open(recipe) } label: {
                    RecipeAttachment(recipe: recipe)
                }
                .buttonStyle(PressableStyle(scale: 0.985))
                .padding(.horizontal, 10)
                .padding(.top, 12)
            } else if post.image_url != nil, let url = post.imageURL {
                CoverImage(url: url)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
            }

            HStack(spacing: 18) {
                Button { social.toggleLike(post) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .medium))
                        Text("\(post.like_count)")
                            .font(nunito(13, .extrabold))
                    }
                    .foregroundStyle(liked ? Color.gsPeach : Color.gsMuted)
                }
                .buttonStyle(.plain)

                Button { social.openComments(post) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 15, weight: .medium))
                        Text(post.isQuestion ? "\(post.comment_count) answers" : "\(post.comment_count)")
                            .font(nunito(13, .extrabold))
                    }
                    .foregroundStyle(Color.gsMuted)
                }
                .buttonStyle(.plain)

                Spacer()

                if post.isQuestion {
                    Button { social.openComments(post) } label: {
                        Text("Answer")
                            .font(nunito(12.5, .extrabold))
                            .foregroundStyle(Color.gsDock)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(PeachButtonStyle())
                } else if let recipe = post.recipe {
                    Button {
                        var copy = recipe
                        copy.id = "r\(Int(Date().timeIntervalSince1970 * 1000))"
                        copy.favorite = false
                        copy.source = "Community · \(post.author_name)"
                        withAnimation(AppStore.pushAnimation) { store.recipes.insert(copy, at: 0) }
                        store.persist()
                        store.showToast("Saved to your library")
                    } label: {
                        Text("Save recipe")
                            .font(nunito(12.5, .extrabold))
                            .foregroundStyle(Color.gsDock)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(PeachButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .softCard(radius: 24)
    }
}

/// Recipe preview embedded in a post.
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

// MARK: - Composer sheet

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
                    .foregroundStyle(Color.white)
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

                Text(isQuestion ? "Answers" : "Discussion")
                    .font(nunito(15, .extrabold))
                    .padding(.top, 14)

                if social.comments.isEmpty {
                    Text(isQuestion ? "No answers yet — know this one?" : "No comments yet — start the discussion.")
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
                                    Label("Report comment", systemImage: "flag")
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
                    TextField("", text: $draft, prompt: Text(isQuestion ? "Write an answer…" : "Add a comment…").foregroundStyle(Color.gsMuted))
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

// MARK: - Share-to-feed sheet (from a recipe's detail screen)

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
                        .foregroundStyle(Color.white)
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

/// Reporting flow required by App Store guideline 1.2. Kept to one tap plus a reason so
/// it actually gets used — a long form is a reason not to report at all.
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
                Text("Tell us what's wrong with this \(targetNoun). Our team reviews reports within 24 hours and removes anything that breaks the rules.")
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
                            // DarkButtonStyle paints the pill but not the label; every
                            // caller sets its own foreground.
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(DarkButtonStyle())
                    .disabled(social.busy)
                }

                // Blocking is offered right here: someone reporting harassment usually
                // also wants the person gone, and shouldn't have to hunt for it.
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
