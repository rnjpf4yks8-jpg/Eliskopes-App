import SwiftUI

/// Staff only: add people, review new accounts and choose the trades each bidder may bid on, and delete
/// accounts. Accounts waiting for review are listed first.
struct PeopleSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { adding = true } label: { Label("Add a person", systemImage: "person.badge.plus") }
                } footer: {
                    Text("Make an account for a bidder, owner or staff member yourself, approved for their trades. They get an email to set their password.")
                }
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
            .sheet(isPresented: $adding) { AddPersonSheet() }
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
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var sendingReset = false
    @State private var resetSent = false

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
            if person.uid != store.user?.uid {
                if let email = person.email, !email.isEmpty {
                    Section {
                        Button {
                            sendingReset = true
                            Task {
                                resetSent = await store.sendPasswordReset(email: email)
                                sendingReset = false
                            }
                        } label: {
                            if sendingReset {
                                ProgressView()
                            } else if resetSent {
                                Label("Password email sent", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                            } else {
                                Label("Email a link to set their password", systemImage: "envelope")
                            }
                        }
                        .disabled(sendingReset || resetSent)
                    } footer: {
                        Text("For someone you added who didn’t get the first email, or who forgot their password. Ask them to check junk mail.")
                    }
                }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if deleting { ProgressView() } else { Label("Delete account", systemImage: "trash") }
                    }
                    .disabled(deleting)
                } footer: {
                    Text("Removes their sign-in and profile. Bids they already placed stay in the history under their anonymous ID.")
                }
            }
            if let message = store.errorMessage {
                Section { Text(message).foregroundStyle(Theme.red) }
            }
        }
        .confirmationDialog("Delete \(person.company.isEmpty ? person.name : person.company)’s account?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                deleting = true
                Task {
                    let deleted = await store.deleteAccount(person)
                    deleting = false
                    if deleted { dismiss() }
                }
            }
        } message: {
            Text("They won’t be able to sign in with this account again. This can’t be undone.")
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
