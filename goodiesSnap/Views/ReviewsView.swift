import SwiftUI

// MARK: - Stars

/// A row of stars showing a rating (supports halves). Read-only.
struct StarRow: View {
    let rating: Double
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                let d = rating - Double(i)
                Image(systemName: d >= 0 ? "star.fill" : (d >= -0.5 ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Color.gsPeach)
            }
        }
    }
}

/// A tappable star picker used when writing a review.
struct StarPicker: View {
    @Binding var rating: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    Haptics.tap(.light)
                    rating = i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(i <= rating ? Color.gsPeach : Color.fg(0.25))
                }
                .buttonStyle(PressableStyle(scale: 0.85))
            }
        }
    }
}

// MARK: - One review

struct ReviewRow: View {
    @EnvironmentObject var store: AppStore
    let review: RecipeReview
    var isMine: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(String(review.author_name.prefix(1)).uppercased())
                    .font(nunito(13, .extrabold))
                    .frame(width: 34, height: 34)
                    .background(Color.gsFill)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isMine ? "You" : review.author_name)
                            .font(nunito(13.5, .extrabold))
                            .lineLimit(1)
                        if !review.relativeTime.isEmpty {
                            Text("· \(review.relativeTime)")
                                .font(nunito(11, .semibold))
                                .foregroundStyle(Color.gsMuted)
                        }
                    }
                    StarRow(rating: Double(review.rating), size: 12)
                }
                Spacer()
                Menu {
                    if isMine {
                        Button("Edit review") { store.startReview() }
                        Button("Delete review", role: .destructive) { Task { await store.deleteMyReview() } }
                    } else {
                        Button(role: .destructive) { store.startReviewReport(review) } label: {
                            Label("Report review", systemImage: "flag")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            if !review.body.isEmpty {
                Text(review.body)
                    .font(nunito(13.5, .semibold))
                    .foregroundStyle(Color.gsFg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .softCard(radius: 18)
    }
}

// MARK: - All reviews screen

/// Full list of a recipe's reviews with a star-rating filter.
struct ReviewsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                summary.padding(.top, 8)
                filterChips.padding(.top, 16)

                if store.reviewsLoading && store.reviews.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 50)
                } else if store.filteredReviews.isEmpty {
                    Text(store.reviewFilter == nil
                         ? "No reviews yet — be the first to rate this recipe."
                         : "No \(store.reviewFilter!)-star reviews.")
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.filteredReviews) { review in
                            ReviewRow(review: review, isMine: review.user_id == store.currentUserID)
                        }
                    }
                    .padding(.top, 16)
                }

                Button { store.startReview() } label: {
                    Text(store.myReview == nil ? "Write a review" : "Edit your review")
                        .font(nunito(15, .extrabold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.top, 24)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 116)
        }
        .background(Color.gsBg)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 44, height: 44)
                    .background(Color.gsCard)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.gsFg.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            Text("Reviews").font(nunito(24, .black))
            Spacer()
        }
    }

    @ViewBuilder
    private var summary: some View {
        if store.reviewCount > 0 {
            HStack(spacing: 12) {
                Text(String(format: "%.1f", store.averageRating)).font(nunito(30, .black))
                VStack(alignment: .leading, spacing: 2) {
                    StarRow(rating: store.averageRating, size: 15)
                    Text("\(store.reviewCount) review\(store.reviewCount == 1 ? "" : "s")")
                        .font(nunito(11.5, .bold)).foregroundStyle(Color.gsMuted)
                }
                Spacer()
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", count: store.reviewCount, active: store.reviewFilter == nil) {
                    store.setReviewFilter(nil)
                }
                // 5★ down to 1★.
                ForEach((1...5).reversed(), id: \.self) { star in
                    let count = store.ratingBuckets[star - 1]
                    filterChip(label: "\(star)★", count: count, active: store.reviewFilter == star) {
                        store.setReviewFilter(star)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, -2)
    }

    private func filterChip(label: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(nunito(13, active ? .extrabold : .semibold))
                Text("\(count)")
                    .font(nunito(10.5, .black))
                    .foregroundStyle(active ? Color.gsDock : Color.gsMuted)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(active ? Color.white.opacity(0.5) : Color.gsFill)
                    .clipShape(Capsule())
            }
            .foregroundStyle(active ? Color.white : Color.gsFg)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(active ? Color.gsDock : Color.gsCard)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gsFg.opacity(active ? 0 : 0.1), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }
}

// MARK: - Write / edit a review

struct WriteReviewSheet: View {
    @EnvironmentObject var store: AppStore
    @State private var rating = 5
    @State private var body_ = ""
    @State private var busy = false
    @State private var loaded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { if !busy { store.writingReview = false } }

            VStack(alignment: .leading, spacing: 16) {
                Capsule().fill(Color.gsFill).frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity).padding(.top, 10)

                Text(store.myReview == nil ? "Rate this recipe" : "Edit your review")
                    .font(nunito(21, .black))
                if let title = store.selected?.title {
                    Text(title).font(nunito(13, .bold)).foregroundStyle(Color.gsMuted).lineLimit(1)
                }

                StarPicker(rating: $rating).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 4)

                TextField("", text: $body_, prompt: Text("Share how it went (optional)").foregroundStyle(Color.gsMuted), axis: .vertical)
                    .font(nunito(13.5, .semibold))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    busy = true
                    let r = rating, b = body_
                    Task { await store.submitReview(rating: r, body: b); busy = false }
                } label: {
                    Text(busy ? "Saving…" : (store.myReview == nil ? "Post review" : "Save changes"))
                        .font(nunito(15, .extrabold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(busy)

                if store.myReview != nil {
                    Button(role: .destructive) {
                        Task { await store.deleteMyReview(); store.writingReview = false }
                    } label: {
                        Text("Delete review").font(nunito(13, .extrabold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }

                Button("Cancel") { store.writingReview = false }
                    .font(nunito(13.5, .extrabold)).foregroundStyle(Color.gsMuted)
                    .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 30)
            }
            .padding(.horizontal, 22).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(Color.gsCard)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .transition(.move(edge: .bottom))
        }
        .onAppear {
            // Pre-fill when editing an existing review.
            guard !loaded else { return }
            loaded = true
            if let mine = store.myReview { rating = mine.rating; body_ = mine.body }
        }
    }
}

// MARK: - Report a review

struct ReviewReportSheet: View {
    @EnvironmentObject var store: AppStore
    @State private var reason: SocialAPI.ReportReason = .spam
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { if !busy { store.reportingReview = nil } }

            VStack(alignment: .leading, spacing: 14) {
                Capsule().fill(Color.gsFill).frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity).padding(.top, 10)
                Text("Report review").font(nunito(20, .black))
                Text("Our team reviews reports within 24 hours and removes anything that breaks the rules.")
                    .font(nunito(13, .semibold)).foregroundStyle(Color.gsMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(SocialAPI.ReportReason.allCases) { option in
                        Button {
                            Haptics.tap(.light); reason = option
                        } label: {
                            HStack {
                                Text(option.label).font(nunito(14, reason == option ? .extrabold : .semibold))
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.gsAccentInk)
                                }
                            }
                            .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if option != SocialAPI.ReportReason.allCases.last { Divider().overlay(Color.gsBg) }
                    }
                }
                .background(Color.gsFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 10) {
                    Button("Cancel") { store.reportingReview = nil }
                        .font(nunito(14, .extrabold))
                        .buttonStyle(PressableStyle()).frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.gsFill).clipShape(Capsule())
                    Button {
                        busy = true
                        let r = reason, n = note
                        Task { await store.submitReviewReport(reason: r, note: n); busy = false }
                    } label: {
                        Text(busy ? "Sending…" : "Submit report")
                            .font(nunito(14, .extrabold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(DarkButtonStyle()).disabled(busy)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 28)
            .frame(maxWidth: .infinity)
            .background(Color.gsCard)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .transition(.move(edge: .bottom))
        }
    }
}
