import SwiftUI

struct ShoppingView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Shopping")
                        .font(nunito(29, .black))
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

                HStack(spacing: 10) {
                    TextField(
                        "", text: $store.newItem,
                        prompt: Text("Add an item…").foregroundStyle(Color.fg(0.35))
                    )
                    .font(nunito(13.5, .semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(Color.fg(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.fg(0.14), lineWidth: 1))
                    .onSubmit { store.addItem() }

                    Button { store.addItem() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.gsFg)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(PeachButtonStyle())
                }
                .padding(.top, 16)

                if store.shopping.isEmpty {
                    VStack(spacing: 6) {
                        Text("Your list is empty")
                            .font(nunito(19, .extrabold))
                            .foregroundStyle(Color.fg(0.7))
                        Text("Open a recipe and add its ingredients, or add items above.")
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.fg(0.45))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 56)
                    .padding(.horizontal, 24)
                }

                ForEach(store.shopGroups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Kicker(text: group.name, size: 11, tracking: 1.8, opacity: 0.5)
                        VStack(spacing: 0) {
                            ForEach(group.items) { item in
                                ShoppingRow(item: item, isLast: item.id == group.items.last?.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .softCard(radius: 20)
                    }
                    .padding(.top, 22)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 116)
        }
        .scrollDismissesKeyboard(.interactively)
    }
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
                Text(item.name)
                    .font(nunito(13.5, .bold))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.fg(0.35) : Color.gsFg)
                Spacer()
                Text(item.qty)
                    .font(nunito(12, .bold))
                    .foregroundStyle(Color.fg(0.45))
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
