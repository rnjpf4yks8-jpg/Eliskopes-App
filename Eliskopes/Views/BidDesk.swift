import SwiftUI

/// Button 10: the live bid desk. Shows the current low and the next bid (1% lower), counts down to the
/// close, and places the bid after a confirmation that states what the bidder is committing to.
struct BidDesk: View {
    @Environment(ProjectStore.self) private var store
    let package: Package
    @State private var confirming = false
    @State private var showAccount = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            desk(now: context.date)
        }
        Card {
            Eyebrow(text: "How bidding works")
            NoteRow(symbol: "chart.line.downtrend.xyaxis", text: "Each new bid is exactly 1% under the current low. You confirm; the app does the math.")
            NoteRow(symbol: "clock.badge.exclamationmark", text: "A bid in the last 5 minutes adds 5 minutes to the clock. No sniping.")
            NoteRow(symbol: "eye.slash", text: "Rivals stay anonymous until bidding closes. The low bid wins and every name is revealed.")
            NoteRow(symbol: "flag.checkered", text: "Closes \(package.closesAt.centralText)\(package.auction == .supplier ? ", 3 hours before the main auction" : "").")
        }
        .sheet(isPresented: $confirming) { ConfirmBidSheet(package: package) }
        .sheet(isPresented: $showAccount) { AccountView() }
    }

    private func desk(now: Date) -> some View {
        let block = store.bidBlock(package, now: now)
        let youHoldLow = store.isMine(package.lowBidder)
        return HeroCard {
            HStack {
                Eyebrow(text: package.isAwarded ? "Winning bid" : "Current low", color: Theme.amber)
                Spacer()
                if !package.isClosed(at: now) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.greenDot).frame(width: 7, height: 7)
                        Text("LIVE").font(Theme.mono(11, .semibold)).foregroundStyle(.white)
                    }
                }
            }
            Text(package.lowBid.map { Money.text($0) } ?? Money.text(package.budget, showCents: false))
                .font(Theme.mono(34, .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: package.current)
            Text(lowLine(youHoldLow: youHoldLow))
                .font(Theme.sans(14)).foregroundStyle(Theme.mist)
            InfoRow(label: "Next bid, 1% lower", value: package.reachedFloor ? "–" : Money.text(package.nextBid), mono: true, onNavy: true)
            InfoRow(label: package.isClosed(at: now) ? "Closed" : "Closes in",
                    value: package.isClosed(at: now) ? package.closesAt.centralText : Countdown.text(to: package.closesAt, from: now, long: true),
                    mono: true, onNavy: true)
            action(block: block)
                .padding(.top, 6)
        }
    }

    private func lowLine(youHoldLow: Bool) -> String {
        if package.isAwarded { return package.winner.map { "Won by \($0)" } ?? "No bids were placed" }
        guard let bidder = package.lowBidder, package.lowBid != nil else { return "No bids yet · starting price" }
        return "\(bidder)\(youHoldLow ? " (you)" : "") · \(Money.percentUnder(package.current, budget: package.budget)) under budget"
    }

    @ViewBuilder
    private func action(block: String?) -> some View {
        if let block {
            if block == "Sign in to bid" {
                Button(block) { showAccount = true }.buttonStyle(AmberButtonStyle())
            } else {
                Button(block) {}.buttonStyle(AmberButtonStyle()).disabled(true)
                if let user = store.user, user.role.isBidder, user.isApproved, !user.approvedTrades.contains(package.trade) {
                    Text("\(user.company) is approved for \(user.approvedTrades.map(Trades.label).joined(separator: " and ")).")
                        .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                }
            }
        } else {
            Button {
                confirming = true
            } label: {
                if store.isBidding { ProgressView().tint(Theme.navy) } else { Text("Bid \(Money.text(package.nextBid))") }
            }
            .buttonStyle(AmberButtonStyle())
            .disabled(store.isBidding)
        }
    }
}

/// States exactly what the bidder commits to before the bid goes in, like the website's confirm step.
struct ConfirmBidSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let package: Package

    /// The live package, so the price shown is the price that will be bid.
    private var live: Package { store.packages.first { $0.id == package.id } ?? package }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeroCard {
                        Eyebrow(text: "\(live.code) · \(live.name)", color: Theme.amber)
                        Text(Money.text(live.nextBid)).font(Theme.mono(34, .bold)).foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("\(Money.percentUnder(live.nextBid, budget: live.budget)) under the \(Money.text(live.budget, showCents: false)) budget")
                            .font(Theme.sans(14)).foregroundStyle(Theme.mist)
                    }
                    Card {
                        InfoRow(label: "Current low", value: live.lowBid.map { Money.text($0) } ?? "No bids yet", mono: true)
                        InfoRow(label: "Your bid, 1% lower", value: Money.text(live.nextBid), mono: true)
                        InfoRow(label: "Per \(live.primaryUnit)", value: live.unitRate(live.nextBid), mono: true)
                        InfoRow(label: "Bidding as", value: store.myBidderID.map { "\($0), anonymous" } ?? "New anonymous ID", mono: true)
                    }
                    Text("By placing this bid you agree to perform this package at this price if you hold the low bid when bidding closes.")
                        .font(Theme.sans(14)).foregroundStyle(Theme.slate)
                    Button {
                        Task {
                            await store.placeBid(on: live)
                            dismiss()
                        }
                    } label: {
                        if store.isBidding { ProgressView().tint(Theme.navy) } else { Text("Place bid") }
                    }
                    .buttonStyle(AmberButtonStyle())
                    .disabled(store.isBidding || store.bidBlock(live) != nil)
                }
                .padding(16)
            }
            .background(Theme.page)
            .navigationTitle("Confirm your bid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

/// A bidder asks about the package on screen. Posted without their name.
struct AskSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your question", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                } header: {
                    Text(store.currentPackage.map { "\($0.code) · \($0.name)" } ?? "Question")
                } footer: {
                    Text("Posted without your name or company. Eliskopes answers it for every bidder.")
                }
                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(Theme.red) }
                }
            }
            .navigationTitle("Ask a question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        working = true
                        Task {
                            if await store.ask(text.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
                            working = false
                        }
                    }
                    .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// Staff answer a question. Every bidder sees the answer.
struct AnswerSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let question: Question
    @State private var text = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") { Text(question.text) }
                Section {
                    TextField("Answer", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                } footer: {
                    Text("Shared with every bidder on this package.")
                }
                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(Theme.red) }
                }
            }
            .navigationTitle("Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        working = true
                        Task {
                            if await store.answer(text.trimmingCharacters(in: .whitespacesAndNewlines), question: question) { dismiss() }
                            working = false
                        }
                    }
                    .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
