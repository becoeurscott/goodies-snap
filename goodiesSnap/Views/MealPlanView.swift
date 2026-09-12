import SwiftUI

struct MealPlanView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    // A tab root has nothing to pop back to, so no chevron here.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week")
                            .font(nunito(29, .black))
                            .tracking(-0.6)
                        Text(store.planRangeLabel + (store.plannedCount == 0
                             ? " · no dinners planned"
                             : " · \(store.plannedCount) of \(AppStore.days.count) planned"))
                            .font(nunito(13, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    Spacer()
                    Button { store.planToShopping() } label: {
                        Text("Shop the plan")
                            .font(nunito(13, .extrabold))
                            .foregroundStyle(Color.fg(0.6))
                            .underline()
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    ForEach(Array(store.planDays.enumerated()), id: \.offset) { _, entry in
                        DayRow(day: entry.day, date: entry.date, isToday: entry.isToday)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 116)
        }
    }
}

struct DayRow: View {
    @EnvironmentObject var store: AppStore
    let day: String
    let date: Int
    var isToday: Bool = false

    private var recipe: Recipe? {
        store.plan[day].flatMap { id in store.recipes.first { $0.id == id } }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(day.prefix(3).uppercased())
                    .font(nunito(9, .extrabold))
                    .tracking(0.7)
                Text("\(date)")
                    .font(nunito(16, .extrabold))
            }
            .foregroundStyle(recipe != nil ? Color.gsFg : (isToday ? Color.gsAccentInk : Color.gsMuted))
            .frame(width: 46, height: 46)
            .background(recipe != nil ? Color.gsPeach : (isToday ? Color.gsPeachSoft : Color.gsCard))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isToday && recipe == nil ? Color.gsPeach.opacity(0.6) : Color.clear,
                                  lineWidth: 1.5)
            )

            if let r = recipe {
                Button { store.open(r) } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: r.imageURL)
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title)
                                .font(nunito(14.5, .extrabold))
                                .lineLimit(1)
                            Text(r.meta)
                                .font(nunito(11, .bold))
                                .foregroundStyle(Color.fg(0.5))
                        }
                        Spacer(minLength: 4)
                        Button { store.removePlan(day: day) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.fg(0.5))
                                .frame(width: 34, height: 34)
                                .background(Color.fg(0.07))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassCard(radius: 18, fill: 0.05, stroke: 0.1)
                }
                .buttonStyle(.plain)
            } else {
                Button { store.openPicker(day: day) } label: {
                    Text("+ Add dinner")
                        .font(nunito(12.5, .bold))
                        .foregroundStyle(Color.fg(0.45))
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.fg(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }
}

struct MealPickerSheet: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        BottomSheet(onDismiss: { store.closePicker() }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Dinner for \(store.pickDay ?? "")")
                    .font(nunito(21, .extrabold))
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.fg(0.1)).frame(height: 1)
                    }

                if store.recipes.isEmpty {
                    VStack(spacing: 10) {
                        Text("No recipes to plan yet")
                            .font(nunito(16, .extrabold))
                        Text("Save one first, then you can drop it onto a day.")
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button {
                                store.closePicker()
                                store.go(to: .importer)
                            } label: {
                                Text("Save a recipe")
                                    .font(nunito(13.5, .extrabold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(DarkButtonStyle())

                            Button {
                                store.closePicker()
                                store.openDiscover()
                            } label: {
                                Text("Browse")
                                    .font(nunito(13.5, .extrabold))
                                    .foregroundStyle(Color.gsFg)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(FillButtonStyle())
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }

                ForEach(store.recipes) { r in
                    Button {
                        if let day = store.pickDay { store.assign(r, to: day) }
                    } label: {
                        HStack(spacing: 12) {
                            CoverImage(url: r.imageURL)
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(nunito(14.5, .extrabold))
                                Text(r.meta)
                                    .font(nunito(11, .bold))
                                    .foregroundStyle(Color.fg(0.5))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.fg(0.07)).frame(height: 1)
                    }
                }
            }
        }
    }
}
