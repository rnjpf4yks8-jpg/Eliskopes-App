import SwiftUI

/// One project's package screen: a short header and all 10 buttons, sized to fit one iPhone screen without
/// scrolling. The arrows step through the main contract and each package, like hips in HAINTEL.
struct ProjectView: View {
    @Environment(ProjectStore.self) private var store
    let projectID: String
    @Binding var path: [Route]
    @State private var showPeople = false
    @State private var addingPackage = false
    @State private var editingPackage: Package?

    var body: some View {
        VStack(spacing: 0) {
            if store.project?.id == projectID, let package = store.currentPackage {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 0) {
                        PackageHeader(package: package, now: context.date)
                        FieldGrid(package: package, now: context.date) { path.append(.field($0)) }
                            .padding(16)
                    }
                }
            } else if store.project?.id == projectID, store.packagesLoaded, store.packages.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Text("No packages yet").font(Theme.sans(18, .semibold)).foregroundStyle(Theme.ink)
                    Text(store.isStaff
                         ? "Add the main contract and each bid package. Bidders see them as soon as you add them."
                         : "Eliskopes is loading this project’s bid packages.")
                        .font(Theme.sans(15)).foregroundStyle(Theme.slate).multilineTextAlignment(.center)
                    if store.isStaff {
                        Button { addingPackage = true } label: { Label("Add package", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    if store.isLoading || store.project?.id != projectID || store.packages.isEmpty {
                        ProgressView()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.page)
        .overlay(alignment: .bottom) { ErrorBanner() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { ProjectSwitcher(path: $path) }
            if store.isStaff {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showPeople = true } label: {
                        Image(systemName: "person.2.badge.gearshape").foregroundStyle(.white)
                    }
                    .accessibilityLabel("People: approve bidders and trades")
                    Menu {
                        Button { addingPackage = true } label: { Label("Add package", systemImage: "plus") }
                        if let package = store.currentPackage, store.project?.id == projectID {
                            Button { editingPackage = package } label: {
                                Label("Edit \(package.code) · \(package.name)", systemImage: "pencil")
                            }
                        }
                    } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Add or edit packages")
                }
            }
        }
        .navBarStyle()
        .task(id: projectID) { await store.open(projectID: projectID) }
        .sheet(isPresented: $showPeople) { PeopleSheet() }
        .sheet(isPresented: $addingPackage) {
            PackageSheet(editing: nil, order: (store.packages.map(\.order).max() ?? -1) + 1,
                         projectClose: store.project?.closesAt ?? .now)
        }
        .sheet(item: $editingPackage) { package in
            PackageSheet(editing: package, order: package.order, projectClose: store.project?.closesAt ?? package.closesAt)
        }
    }
}

/// The title in a project's bar. Tapping it lists every project, so you can jump straight to another one.
private struct ProjectSwitcher: View {
    @Environment(ProjectStore.self) private var store
    @Binding var path: [Route]

    var body: some View {
        Menu {
            ForEach(store.projects) { project in
                Button {
                    path = [.project(project.id)]
                } label: {
                    if project.id == store.project?.id {
                        Label("\(project.name) · \(project.city)", systemImage: "checkmark")
                    } else {
                        Text("\(project.name) · \(project.city)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(store.project?.name ?? "Project")
                    .font(Theme.sans(16, .bold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.amber)
            }
        }
        .accessibilityLabel("Switch project, current: \(store.project?.name ?? "")")
    }
}

private struct PackageHeader: View {
    @Environment(ProjectStore.self) private var store
    let package: Package
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "\(store.project?.round ?? "") · \(store.project?.city ?? "")", color: Theme.amber)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .center, spacing: 8) {
                Menu {
                    ForEach(store.packages) { item in
                        Button {
                            store.select(item.id)
                        } label: {
                            if item.id == package.id {
                                Label("\(item.code) · \(item.name)", systemImage: "checkmark")
                            } else {
                                Text("\(item.code) · \(item.name)")
                            }
                        }
                    }
                } label: {
                    Text(package.code)
                        .font(Theme.mono(30, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)
                .accessibilityLabel("\(package.code), \(package.name). Pick another package")
                LowBidChip(package: package)
                Spacer(minLength: 0)
                StepButton(symbol: "chevron.left", enabled: store.hasPreviousPackage) { store.stepPackage(-1) }
                    .accessibilityLabel("Previous package")
                StepButton(symbol: "chevron.right", enabled: store.hasNextPackage) { store.stepPackage(1) }
                    .accessibilityLabel("Next package")
            }
            Text("\(package.name) · \(package.bidderType.label)")
                .font(Theme.sans(15, .medium))
                .foregroundStyle(Theme.mist)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            statusLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.navy)
        .animation(.snappy, value: package.id)
    }

    @ViewBuilder
    private var statusLine: some View {
        if package.isClosed(at: now) {
            Text(package.isAwarded ? "Awarded · \(package.winner ?? "no bids")" : "Bidding closed · awarding")
                .font(Theme.sans(13)).foregroundStyle(Theme.muted).lineLimit(1)
        } else if let user = store.user {
            Text("\(user.company)\(store.myBidderID.map { " · \($0)" } ?? "") · \(Countdown.text(to: package.closesAt, from: now, long: false))")
                .font(Theme.sans(13)).foregroundStyle(Theme.muted).lineLimit(1)
        } else {
            HStack(spacing: 6) {
                Circle().fill(Theme.greenDot).frame(width: 7, height: 7)
                Text(Countdown.text(to: package.closesAt, from: now, long: false)).foregroundStyle(.white)
                Text("· closes \(package.closesAt.centralText)").foregroundStyle(Theme.muted)
            }
            .font(Theme.sans(13))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

/// The current low bid beside the package code, and how far under budget it is.
private struct LowBidChip: View {
    let package: Package

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Money.text(package.current, showCents: package.lowBid != nil))
                .font(Theme.mono(16, .bold))
                .foregroundStyle(Theme.amber)
                .contentTransition(.numericText())
            Text(package.lowBid == nil ? "BUDGET · NO BIDS" : "LOW · \(Money.percentUnder(package.current, budget: package.budget)) UNDER")
                .font(Theme.mono(10, .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .animation(.snappy, value: package.current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(package.lowBid == nil
            ? "Budget \(Money.text(package.budget, showCents: false)), no bids yet"
            : "Current low \(Money.text(package.current)), \(Money.percentUnder(package.current, budget: package.budget)) under budget")
    }
}

private struct StepButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(enabled ? .white : Theme.navyBorder)
                .overlay(Circle().stroke(enabled ? Theme.navyOutline : Theme.navyBorder))
        }
        .disabled(!enabled)
    }
}

/// 2 columns × 5 rows. Rows stretch to share the space under the header, so nothing scrolls.
private struct FieldGrid: View {
    @Environment(ProjectStore.self) private var store
    let package: Package
    let now: Date
    let open: (PackageField) -> Void

    private let rows: [[PackageField]] = stride(from: 0, to: PackageField.allCases.count, by: 2).map {
        Array(PackageField.allCases[$0..<min($0 + 2, PackageField.allCases.count)])
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row) { field in
                        FieldTile(field: field, summary: store.tileSummary(field, package: package, now: now)) {
                            open(field)
                        }
                    }
                }
            }
        }
    }
}

private struct FieldTile: View {
    let field: PackageField
    let summary: String
    let action: () -> Void

    /// Place Bid is the one navy tile: it's where the auction happens.
    private var isBid: Bool { field == .placeBid }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: field.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isBid ? Theme.amber : Theme.blue)
                    Spacer()
                    Text(String(format: "%02d", field.rawValue + 1))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                Text(field.title)
                    .font(Theme.sans(14, .semibold))
                    .foregroundStyle(isBid ? .white : Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(summary)
                    .font(isBid ? Theme.mono(12, .semibold) : Theme.sans(12))
                    .foregroundStyle(isBid ? Theme.amber : Theme.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isBid ? Theme.navy : .white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isBid ? Theme.navy : Theme.line))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(field.title), \(summary)")
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
