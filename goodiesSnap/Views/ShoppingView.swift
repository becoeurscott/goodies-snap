import SwiftUI

struct ShoppingView: View {
    @EnvironmentObject var store: AppStore
    /// Briefly true right after an item is added, driving the success animation.
    @State private var justAdded = false
    @FocusState private var addFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if store.shopping.isEmpty {
                    emptyState
                } else {
                    storeBar
                        .padding(.top, 18)

                    // One card per recipe you're shopping for; the items live inside.
                    VStack(spacing: 12) {
                        ForEach(store.shopByRecipe, id: \.id) { group in
                            BasketCard(group: group)
                        }
                    }
                    .padding(.top, 16)
                }

                // The add-item control lives below the list.
                addBar
                    .padding(.top, store.shopping.isEmpty ? 8 : 24)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 116)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $store.storePickerOpen) { StorePickerSheet() }
    }

    // MARK: Add item (below the list)

    private func add() {
        guard store.addItem() else { return }
        addFocused = true                       // keep the keyboard up for quick multi-add
        Haptics.notify(.success)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { justAdded = true }
        // Reset the confirmation shortly after so it reads as a flash, not a state.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.3)) { justAdded = false }
        }
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Success confirmation, sliding in above the field.
            if justAdded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Added to your list")
                        .font(nunito(12.5, .extrabold))
                }
                .foregroundStyle(Color.gsAccentInk)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                TextField("", text: $store.newItem,
                          prompt: Text("Add an item…").foregroundStyle(Color.fg(0.35)))
                    .font(nunito(13.5, .semibold))
                    .focused($addFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(Color.fg(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.fg(0.14), lineWidth: 1))
                    .onSubmit { add() }

                // The add button: plus normally, a green checkmark bounce on success.
                Button { add() } label: {
                    Image(systemName: justAdded ? "checkmark" : "plus")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(Color.gsDock)
                        .scaleEffect(justAdded ? 1.18 : 1)
                        .frame(width: 52, height: 52)
                        .background(justAdded ? Color.gsMint : Color.gsPeach)
                        .clipShape(Circle())
                        .shadow(color: (justAdded ? Color.gsMint : Color.gsPeach).opacity(0.45),
                                radius: justAdded ? 12 : 6, y: 4)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .disabled(store.newItem.trimmingCharacters(in: .whitespaces).isEmpty && !justAdded)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: justAdded)
    }

    // MARK: Store + prices

    private var storeBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.gsAccentInk)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.krogerStoreName ?? "No store set")
                    .font(nunito(13.5, .extrabold))
                    .lineLimit(1)
                Text(store.krogerStoreName == nil ? "Set a store to see prices" : "Prices from this store")
                    .font(nunito(10.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
            }
            Spacer()
            if store.krogerStoreName == nil {
                Button("Set store") { store.openStorePicker() }
                    .font(nunito(12.5, .extrabold))
                    .foregroundStyle(Color.gsAccentInk)
                    .buttonStyle(.plain)
            } else {
                Button {
                    if store.pricesLoading { return }
                    store.refreshPrices()
                } label: {
                    if store.pricesLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Get prices").font(nunito(12.5, .extrabold)).foregroundStyle(Color.gsAccentInk)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .softCard(radius: 18)
        .contextMenu {
            if store.krogerStoreName != nil {
                Button("Change store") { store.openStorePicker() }
            }
        }
    }

    // MARK: Header + add

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Shopping").font(nunito(29, .black))
            Spacer()
            if store.shopping.contains(where: \.done) {
                Button { store.clearDone() } label: {
                    Text("Clear checked")
                        .font(nunito(13, .extrabold))
                        .foregroundStyle(Color.fg(0.6))
                        .underline()
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Your list is empty")
                .font(nunito(19, .extrabold))
                .foregroundStyle(Color.fg(0.7))
            Text("Open a recipe and add its ingredients, or add items below.")
                .font(nunito(12.5, .semibold))
                .foregroundStyle(Color.fg(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 24)
    }

    // MARK: Grouping toggle

}

struct ShoppingRow: View {
    @EnvironmentObject var store: AppStore
    let item: ShoppingItem
    let isLast: Bool

    var body: some View {
        Button { store.toggleItem(item.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(item.done ? Color.gsFg : Color.clear)
                        .overlay(Circle().strokeBorder(item.done ? Color.gsFg : Color.fg(0.3), lineWidth: 2))
                        .frame(width: 22, height: 22)
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.gsCard)
                    }
                }

                // The matched store product's photo, once prices have been fetched.
                if let img = item.priceImage, let url = URL(string: img) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Color.gsFill
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(item.done ? 0.4 : 1)
                }

                Text(item.name)
                    .font(nunito(13.5, .bold))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.fg(0.35) : Color.gsFg)
                Spacer()
                if let cents = item.priceCents {
                    Text(store.formatPrice(cents))
                        .font(nunito(12.5, .black))
                        .foregroundStyle(item.done ? Color.fg(0.35) : Color.gsAccentInk)
                } else {
                    Text(item.qty)
                        .font(nunito(12, .bold))
                        .foregroundStyle(Color.fg(0.45))
                }
            }
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.fg(0.07)).frame(height: 1)
            }
        }
    }
}

// MARK: - Store picker

/// Find a Kroger store by ZIP and pick one. The chosen store is remembered, and prices
/// refresh against it.
struct StorePickerSheet: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your store")
                .font(nunito(23, .black))
                .padding(.top, 28)
            Text("Prices come from your Kroger-family store. Enter your ZIP to find one nearby.")
                .font(nunito(13, .semibold))
                .foregroundStyle(Color.gsMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("", text: $store.storeZip,
                          prompt: Text("ZIP code").foregroundStyle(Color.gsMuted))
                    .font(nunito(15, .extrabold))
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button { store.findStores() } label: {
                    Text("Find").font(nunito(14, .extrabold)).foregroundStyle(.white)
                        .frame(width: 84, height: 50)
                }
                .buttonStyle(DarkButtonStyle())
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.storeCandidates) { s in
                        Button { store.chooseStore(s) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(nunito(14, .extrabold)).foregroundStyle(Color.gsFg)
                                    Text(s.address).font(nunito(11.5, .semibold)).foregroundStyle(Color.gsMuted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.gsMuted)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(Color.gsCard)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.gsFg.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gsBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}


/// One recipe's shopping basket, as it appears in the Shopping list.
struct BasketCard: View {
    @EnvironmentObject var store: AppStore
    let group: (id: String, title: String, items: [ShoppingItem])

    private var bought: Int { group.items.filter(\.done).count }
    private var total: Int { group.items.count }
    private var allDone: Bool { total > 0 && bought == total }

    var body: some View {
        Button { store.openBasket(group.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: group.id == "__manual__" ? "square.and.pencil" : "fork.knife")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.gsAccentInk)
                        .frame(width: 40, height: 40)
                        .background(Color.gsPeachSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(nunito(15.5, .extrabold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(allDone ? "All bought" : "\(total - bought) still to buy · \(total) items")
                            .font(nunito(12, .semibold))
                            .foregroundStyle(allDone ? Color.gsAccentInk : Color.gsMuted)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        if let cents = store.priceTotalCents(group.items) {
                            Text(store.formatPrice(cents))
                                .font(nunito(14, .black))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.gsMuted)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gsFill)
                        Capsule()
                            .fill(Color.gsPeach)
                            .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(bought) / CGFloat(total))
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .softCard(radius: 20)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("Remove this list", role: .destructive) { store.removeBasket(group.id) }
        }
    }
}

/// The items for one recipe, grouped by aisle so the shop can be walked in order.
struct BasketView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconButton(system: "chevron.left") { store.goBack() }
                    Spacer()
                    if let g = store.openBasketGroup, g.items.contains(where: \.done) {
                        Button { store.clearDone() } label: {
                            Text("Clear checked")
                                .font(nunito(13, .extrabold))
                                .foregroundStyle(Color.fg(0.6))
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let g = store.openBasketGroup {
                    let bought = g.items.filter(\.done).count
                    Text(g.title)
                        .font(nunito(27, .black))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    Text("\(bought) of \(g.items.count) bought")
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .padding(.top, 2)

                    ForEach(store.aisleSections(of: g.items), id: \.name) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Kicker(text: section.name, size: 11, tracking: 1.8, opacity: 0.5)
                            VStack(spacing: 0) {
                                ForEach(section.items) { item in
                                    ShoppingRow(item: item, isLast: item.id == section.items.last?.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .softCard(radius: 20)
                        }
                        .padding(.top, 22)
                    }

                    Button { store.removeBasket(g.id) } label: {
                        Text("Remove this list")
                            .font(nunito(13.5, .extrabold))
                            .foregroundStyle(Color.gsMuted)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 26)
                } else {
                    Text("This list is gone")
                        .font(nunito(17, .extrabold))
                        .foregroundStyle(Color.gsMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 116)
        }
        .background(Color.gsBg)
    }
}
