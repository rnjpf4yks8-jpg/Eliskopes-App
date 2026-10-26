import SwiftUI

/// What each of the 10 buttons shows. Everything here is free to read; Place Bid is the only action.
struct FieldContent: View {
    let field: PackageField
    let package: Package

    var body: some View {
        switch field {
        case .package: PackageInfo(package: package)
        case .budget: BudgetInfo(package: package)
        case .quantities: QuantitiesInfo(package: package)
        case .unitCosts: UnitCostsInfo(package: package)
        case .documents: DocumentsInfo(package: package)
        case .schedule: ScheduleInfo(package: package)
        case .approvals: ApprovalsInfo(package: package)
        case .questions: QuestionsInfo(package: package)
        case .bidHistory: BidHistoryInfo(package: package)
        case .placeBid: BidDesk(package: package)
        }
    }
}

// MARK: 01 Package

private struct PackageInfo: View {
    @Environment(ProjectStore.self) private var store
    let package: Package

    var body: some View {
        HeroCard {
            Eyebrow(text: "\(package.code) · \(package.auction.label)", color: Theme.amber)
            Text(package.name).font(Theme.sans(26, .bold)).foregroundStyle(.white)
            Text("\(package.bidderType.label) · \(package.primaryQty.quantityText) \(package.primaryUnit)")
                .font(Theme.sans(15)).foregroundStyle(Theme.mist)
            Text(package.scope).font(Theme.sans(15)).foregroundStyle(Theme.mist).fixedSize(horizontal: false, vertical: true)
        }
        Card {
            InfoRow(label: "Project", value: store.project?.name ?? "")
            InfoRow(label: "Location", value: store.project?.city ?? "")
            InfoRow(label: "Owner", value: store.project?.owner ?? "")
            InfoRow(label: "Trade", value: Trades.label(package.trade))
            InfoRow(label: "Bidding closes", value: package.closesAt.centralText)
            InfoRow(label: "Approved bidders", value: "\(package.approvedBidders)", mono: true)
        }
        if package.auction == .supplier {
            NoteRow(symbol: "clock", text: "Vendor and supplier packages close 3 hours before the main auction, so contractors bid with material prices settled.")
        }
        Eyebrow(text: "All packages").padding(.top, 4)
        VStack(spacing: 0) {
            ForEach(store.packages) { item in
                Button { store.select(item.id) } label: {
                    HStack(spacing: 14) {
                        Text(item.code).font(Theme.mono(14, .semibold)).foregroundStyle(Theme.ink).frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                            Text(item.lowBid == nil ? "Budget \(Money.text(item.budget, showCents: false))" : "Low \(Money.text(item.current))")
                                .font(Theme.sans(13)).foregroundStyle(Theme.slate).monospacedDigit()
                        }
                        Spacer()
                        if item.id == package.id { Image(systemName: "checkmark").foregroundStyle(Theme.blue) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if item.id != store.packages.last?.id { Divider().overlay(Theme.line) }
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

// MARK: 02 Budget

private struct BudgetInfo: View {
    let package: Package

    /// How far bidding has moved from the budget toward the floor, 0…1.
    private var progress: Double {
        let span = Double(package.budget - package.floor)
        guard span > 0 else { return 0 }
        return min(1, max(0, Double(package.budget - package.current) / span))
    }

    var body: some View {
        HeroCard {
            Eyebrow(text: "Established budget", color: Theme.amber)
            Text(Money.text(package.budget, showCents: false)).font(Theme.mono(34, .bold)).foregroundStyle(.white)
            Text("The starting price. Every bidder works from this number, and the first bid is 1% under it.")
                .font(Theme.sans(15)).foregroundStyle(Theme.mist).fixedSize(horizontal: false, vertical: true)
        }
        Card {
            Eyebrow(text: "Where bidding stands")
            InfoRow(label: "Current low", value: package.lowBid.map { Money.text($0) } ?? "No bids yet", mono: true)
            InfoRow(label: "Under budget",
                    value: package.lowBid == nil ? "–" : "\(Money.text(package.budget - package.current)) · \(Money.percentUnder(package.current, budget: package.budget))",
                    mono: true)
            InfoRow(label: "Owner’s floor", value: Money.text(package.floor, showCents: false), mono: true)
            ProgressView(value: progress)
                .tint(Theme.amber)
                .accessibilityLabel("\(Int(progress * 100)) percent of the way from budget to floor")
            HStack {
                Text("Budget"); Spacer(); Text("Floor")
            }
            .font(Theme.mono(12)).foregroundStyle(Theme.muted)
        }
        NoteRow(symbol: "info.circle", text: "Bids stop at the owner’s floor. The low bid when bidding closes wins the package.")
    }
}

// MARK: 03 Quantities

private struct QuantitiesInfo: View {
    let package: Package

    var body: some View {
        Card {
            HStack {
                Text("Takeoff").font(Theme.sans(17, .semibold))
                Spacer()
                StatusBadge(text: "Provided")
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("ITEM").gridColumnAlignment(.leading)
                    Text("QTY").gridColumnAlignment(.trailing)
                    Text("UNIT").gridColumnAlignment(.leading)
                }
                .font(Theme.mono(11, .medium)).foregroundStyle(Theme.muted)
                ForEach(package.quantities, id: \.self) { line in
                    Divider().overlay(Theme.line)
                    GridRow {
                        Text(line.item).font(Theme.sans(14)).foregroundStyle(Theme.ink)
                        Text(line.qty.quantityText).font(Theme.mono(14, .semibold)).foregroundStyle(Theme.ink)
                        Text(line.unit).font(Theme.mono(12)).foregroundStyle(Theme.slate)
                    }
                }
                if package.showTotal {
                    Rectangle().fill(Theme.ink).frame(height: 2)
                    GridRow {
                        Text("Total").font(Theme.sans(14, .semibold))
                        Text(package.primaryQty.quantityText).font(Theme.mono(14, .bold))
                        Text(package.primaryUnit).font(Theme.mono(12, .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }
        NoteRow(symbol: "ruler", text: "Quantities by Eliskopes estimating, in the format suppliers already use. Price your labor and material against these.")
    }
}

// MARK: 04 Unit costs

private struct UnitCostsInfo: View {
    let package: Package
    @State private var rateText = ""

    var body: some View {
        Card {
            Eyebrow(text: "Per \(package.primaryUnit), calculated for you")
            InfoRow(label: "At budget", value: package.unitRate(package.budget), mono: true)
            InfoRow(label: "At current low", value: package.lowBid.map { package.unitRate($0) } ?? "No bids yet", mono: true)
            InfoRow(label: "At next bid", value: package.reachedFloor ? "At the floor" : package.unitRate(package.nextBid), mono: true)
        }
        Card {
            Eyebrow(text: "Also worked out")
            ForEach(package.facts, id: \.self) { fact in
                InfoRow(label: fact.label, value: fact.value, mono: true)
            }
        }
        Card {
            Eyebrow(text: "Check your number")
            Text("Your price per \(package.primaryUnit)").font(Theme.sans(13)).foregroundStyle(Theme.slate)
            HStack(spacing: 8) {
                Text("$").font(Theme.mono(15)).foregroundStyle(Theme.slate)
                TextField(placeholder, text: $rateText)
                    .keyboardType(.decimalPad)
                    .font(Theme.mono(17, .semibold))
                Text("/ \(package.primaryUnit)").font(Theme.mono(14)).foregroundStyle(Theme.slate)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.page, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            verdict
        }
    }

    private var placeholder: String {
        String(format: "%.2f", Double(package.nextBid) / 100 / max(package.primaryQty, 1))
    }

    @ViewBuilder
    private var verdict: some View {
        if let rate = Double(rateText.replacingOccurrences(of: ",", with: "")), rate > 0 {
            let total = Int((rate * 100 * package.primaryQty).rounded())
            let next = package.nextBid
            if total < package.floor {
                verdictText("Total \(Money.text(total)) is below the owner’s floor of \(Money.text(package.floor, showCents: false)). Bids stop there.", Theme.red)
            } else if package.reachedFloor {
                verdictText("Total \(Money.text(total)). Bidding has already reached the floor.", Theme.slate)
            } else if total <= next {
                verdictText("Total \(Money.text(total)). You can take the next bid of \(Money.text(next)) with \(Money.text(next - total)) to spare.", Theme.green)
            } else {
                verdictText("Total \(Money.text(total)) is \(Money.text(total - next)) above the next bid of \(Money.text(next)).", Theme.red)
            }
        } else {
            verdictText("Enter a unit price to see your total against the next bid.", Theme.slate)
        }
    }

    private func verdictText(_ text: String, _ color: Color) -> some View {
        Text(text).font(Theme.sans(15)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: 05 Plans & specs

private struct DocumentsInfo: View {
    let package: Package

    var body: some View {
        Card {
            ForEach(Array(package.documents.enumerated()), id: \.offset) { index, document in
                if index > 0 { Divider().overlay(Theme.line) }
                row(document)
            }
        }
        NoteRow(symbol: "info.circle", text: "Every document is free. Tap one to open the PDF.")
    }

    @ViewBuilder
    private func row(_ document: ProjectDocument) -> some View {
        let content = HStack(spacing: 12) {
            Text("PDF")
                .font(Theme.mono(10, .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 36, height: 42)
                .background(Theme.blueTint, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                Text(document.detail).font(Theme.sans(13)).foregroundStyle(Theme.slate)
            }
            Spacer(minLength: 0)
            if document.url != nil {
                Image(systemName: "arrow.up.right.square").foregroundStyle(Theme.blue)
            } else {
                Text("Coming soon").font(Theme.sans(12)).foregroundStyle(Theme.muted)
            }
        }
        if let url = document.url {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

// MARK: 06 Schedule

private struct ScheduleInfo: View {
    let package: Package

    var body: some View {
        HeroCard {
            Eyebrow(text: "Start", color: Theme.amber)
            Text(package.schedule.start).font(Theme.mono(28, .bold)).foregroundStyle(.white)
            Text(package.schedule.duration).font(Theme.sans(15)).foregroundStyle(Theme.mist)
        }
        Card {
            Eyebrow(text: "Milestones")
            ForEach(Array(package.schedule.milestones.enumerated()), id: \.offset) { index, milestone in
                if index > 0 { Divider().overlay(Theme.line) }
                HStack {
                    Text(milestone.label).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(milestone.date).font(Theme.mono(13)).foregroundStyle(Theme.slate)
                }
            }
        }
        Card {
            Eyebrow(text: "Payment")
            Text(package.schedule.payment).font(Theme.sans(15)).foregroundStyle(Theme.slate).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: 07 Approvals

private struct ApprovalsInfo: View {
    let package: Package

    var body: some View {
        Card {
            ForEach(Array(package.approvals.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().overlay(Theme.line) }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                        Text(item.note).font(Theme.sans(13)).foregroundStyle(Theme.slate)
                    }
                    Spacer(minLength: 0)
                    StatusBadge(text: item.status, ready: item.ready)
                }
            }
        }
        NoteRow(symbol: "checkmark.shield", text: "Approved once, before bidding. The winner starts work at award without waiting on submittals.")
    }
}

// MARK: 08 Q&A

private struct QuestionsInfo: View {
    @Environment(ProjectStore.self) private var store
    let package: Package
    @State private var answering: Question?
    @State private var asking = false
    @State private var showAccount = false

    var body: some View {
        if store.questions.isEmpty {
            Card {
                Text("No questions yet").font(Theme.sans(17, .semibold))
                Text("Approved bidders can ask anything about this package. Every answer is shared with all bidders.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate)
            }
        }
        ForEach(store.questions) { question in
            Card {
                HStack(alignment: .top) {
                    Text(question.text).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    if !question.isAnswered { StatusBadge(text: "Open", ready: false) }
                }
                if let answer = question.answer, question.isAnswered {
                    Text(answer).font(Theme.sans(15)).foregroundStyle(Theme.slate).fixedSize(horizontal: false, vertical: true)
                    Eyebrow(text: "Answered by Eliskopes · \(question.answeredAt?.shortDay ?? "")", color: Theme.muted)
                } else if store.isStaff {
                    Button("Answer") { answering = question }
                        .buttonStyle(.bordered)
                } else {
                    Text("Eliskopes will answer before bidding closes.").font(Theme.sans(14)).foregroundStyle(Theme.slate)
                }
            }
        }
        if store.canAsk {
            Button("Ask a question") { asking = true }.buttonStyle(.bordered)
        } else if store.user == nil {
            Button("Sign in to ask a question") { showAccount = true }.buttonStyle(.bordered)
        } else if store.user?.role.isBidder == true {
            NoteRow(symbol: "hourglass", text: "You can ask questions once Eliskopes approves your account.")
        }
        NoteRow(symbol: "eye.slash", text: "Questions are posted without your name. Answers go to every bidder.")
            .sheet(item: $answering) { AnswerSheet(question: $0) }
            .sheet(isPresented: $asking) { AskSheet() }
            .sheet(isPresented: $showAccount) { AccountView() }
    }
}

// MARK: 09 Bid history

private struct BidHistoryInfo: View {
    @Environment(ProjectStore.self) private var store
    let package: Package

    var body: some View {
        if store.bids.isEmpty {
            Card {
                Text("No bids yet").font(Theme.sans(17, .semibold))
                Text("The first bid will be \(Money.text(package.nextBid)), 1% under the \(Money.text(package.budget, showCents: false)) budget.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate)
            }
        } else {
            Card {
                HStack {
                    Text("\(store.bids.count) bid\(store.bids.count == 1 ? "" : "s")").font(Theme.sans(17, .semibold))
                    Spacer()
                    Text("\(Money.percentUnder(package.current, budget: package.budget)) under budget")
                        .font(Theme.mono(13)).foregroundStyle(Theme.slate)
                }
                let newestFirst = Array(store.bids.reversed())
                ForEach(Array(newestFirst.enumerated()), id: \.element.id) { index, bid in
                    Divider().overlay(Theme.line)
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(store.revealed[bid.bidder] ?? bid.bidder)
                                    .font(Theme.mono(15, .semibold)).foregroundStyle(Theme.ink)
                                if store.isMine(bid.bidder) {
                                    Text("YOU").font(Theme.mono(10, .bold)).foregroundStyle(Theme.navy)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.amber, in: Capsule())
                                }
                            }
                            Text(bid.at.centralText + (index == 0 ? (package.isAwarded ? " · winning bid" : " · current low") : ""))
                                .font(Theme.sans(13)).foregroundStyle(Theme.slate)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.text(bid.amount)).font(Theme.mono(15, .semibold)).foregroundStyle(Theme.ink)
                            Text("\(Money.percentUnder(bid.amount, budget: package.budget)) under").font(Theme.mono(12)).foregroundStyle(Theme.slate)
                        }
                    }
                }
            }
        }
        NoteRow(symbol: "eye.slash", text: package.isAwarded
            ? "Bidding has closed and every bidder is named."
            : "Bidders show as anonymous IDs until bidding closes. Then every name is revealed.")
    }
}
