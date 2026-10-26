import SwiftUI

/// Staff only: review new accounts and choose the trades each bidder may bid on.
/// Accounts waiting for review are listed first.
struct PeopleSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.people.isEmpty {
                    Text("No accounts yet.").foregroundStyle(Theme.slate)
                }
                ForEach(store.people, id: \.uid) { person in
                    NavigationLink {
                        PersonReview(person: person)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(person.company).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                if !person.isApproved, person.role != .staff {
                                    StatusBadge(text: "Review", ready: false)
                                }
                            }
                            Text("\(person.name) · \(person.role.label)").font(Theme.sans(13)).foregroundStyle(Theme.slate)
                            if person.role.isBidder, !person.approvedTrades.isEmpty {
                                Text(person.approvedTrades.map(Trades.label).joined(separator: ", "))
                                    .font(Theme.sans(13)).foregroundStyle(Theme.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle(store.waitingForReview > 0 ? "People · \(store.waitingForReview) to review" : "People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await store.loadPeople() }
            .refreshable { await store.loadPeople() }
        }
    }
}

private struct PersonReview: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: AppUser
    @State private var role: Role = .gc
    @State private var approved = false
    @State private var trades: Set<String> = []
    @State private var saving = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Name", value: person.name)
                LabeledContent("Company", value: person.company)
                if let email = person.email { LabeledContent("Email", value: email) }
            }
            Section {
                Picker("Role", selection: $role) {
                    ForEach(Role.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Approved", isOn: $approved)
            } footer: {
                Text("Approved bidders can bid on packages in their trades and ask questions. Owners and staff don’t bid.")
            }
            if role.isBidder {
                Section("May bid on") {
                    ForEach(Trades.all, id: \.key) { trade in
                        Toggle(trade.label, isOn: Binding(
                            get: { trades.contains(trade.key) },
                            set: { on in if on { trades.insert(trade.key) } else { trades.remove(trade.key) } }))
                    }
                }
            }
            if let message = store.errorMessage {
                Section { Text(message).foregroundStyle(Theme.red) }
            }
        }
        .navigationTitle(person.company)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saving = true
                    Task {
                        let kept = role.isBidder ? Trades.all.map(\.key).filter { trades.contains($0) } : []
                        if await store.review(person, role: role, approved: approved, trades: kept) { dismiss() }
                        saving = false
                    }
                }
                .disabled(saving)
            }
        }
        .onAppear {
            role = person.role
            approved = person.isApproved
            trades = Set(person.approvedTrades)
        }
    }
}
