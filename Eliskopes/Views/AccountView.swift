import SwiftUI

/// Sign in, or create an account as a general contractor, turnkey sub, vendor/supplier, owner or staff
/// (with the staff code). In demo mode, switch between the sample accounts instead.
struct AccountView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: Role = .gc
    @State private var staffCode = ""
    @State private var working = false
    @State private var claiming = false
    /// "You're now Eliskopes staff", shown at the top after the code works.
    @State private var confirmation: String?
    @State private var resetSent = false

    var body: some View {
        NavigationStack {
            Form {
                if let message = store.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.red)
                    }
                }
                if let confirmation {
                    Section {
                        Label(confirmation, systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.green)
                    }
                }

                if let user = store.user {
                    signedIn(user)
                }

                if store.isDemo {
                    demoPeople
                } else if store.user == nil {
                    signInForm
                }

                if !store.isDemo, let user = store.user, user.role != .staff {
                    Section {
                        SecureField("Staff code", text: $staffCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            hideKeyboard()
                            confirmation = nil
                            claiming = true
                            Task {
                                if await store.claimStaff(code: staffCode) {
                                    staffCode = ""
                                    confirmation = "You’re now Eliskopes staff. Add projects with + and people with the People button on the projects list."
                                }
                                claiming = false
                            }
                        } label: {
                            if claiming {
                                HStack(spacing: 8) { ProgressView(); Text("Checking the code…") }
                            } else {
                                Text("Become staff")
                            }
                        }
                        .disabled(claiming || staffCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    } header: {
                        Text("Eliskopes staff")
                    } footer: {
                        Text("Staff add and delete projects, packages, plans and people, approve bidders, answer questions and run the bidding rounds. Ask Eliskopes for the staff code.")
                    }
                }

                if !store.isDemo, store.user != nil {
                    Section {
                        Button("Sign out", role: .destructive) {
                            Task {
                                await store.signOut()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                store.errorMessage = nil
                if store.user != nil, !store.isDemo { await store.refreshUser() }
            }
        }
    }

    @ViewBuilder
    private func signedIn(_ user: AppUser) -> some View {
        Section("Signed in") {
            LabeledContent("Name", value: user.name)
            LabeledContent("Company", value: user.company)
            LabeledContent("Role", value: user.role.label)
            if user.role.isBidder {
                LabeledContent("Status", value: user.isApproved ? "Approved" : "Waiting for review")
                LabeledContent("Approved trades", value: user.approvedTrades.isEmpty ? "None yet" : user.approvedTrades.map(Trades.label).joined(separator: ", "))
                if let id = store.myBidderID {
                    LabeledContent("Anonymous ID on this project", value: id)
                }
            }
        }
        if user.role.isBidder, !user.isApproved {
            Section {
                Text("Eliskopes reviews every account before it can bid. You’ll be approved for the trades you work in, usually within one business day.")
                    .font(Theme.sans(14)).foregroundStyle(Theme.slate)
            }
        }
    }

    private var demoPeople: some View {
        Section {
            Button {
                Task {
                    await store.signInDemo(as: nil)
                    dismiss()
                }
            } label: {
                personRow(title: "Not signed in", detail: "Browse only", selected: store.user == nil)
            }
            ForEach(SampleData.people, id: \.uid) { person in
                Button {
                    Task {
                        await store.signInDemo(as: person)
                        dismiss()
                    }
                } label: {
                    personRow(title: person.company, detail: detail(person), selected: store.user?.uid == person.uid)
                }
            }
        } header: {
            Text("Demo: sign in as")
        } footer: {
            Text("Firebase isn’t connected yet, so the app runs on the sample project and nothing is saved after you close it.")
        }
    }

    private func personRow(title: String, detail: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.slate)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.blue) }
        }
    }

    private func detail(_ person: AppUser) -> String {
        guard person.role.isBidder else { return person.role.label }
        guard person.isApproved else { return "\(person.role.label) · waiting for review" }
        return "\(person.role.label) · bids on \(person.approvedTrades.map(Trades.label).joined(separator: ", "))"
    }

    @ViewBuilder
    private var signInForm: some View {
        Section {
            Picker("", selection: $creating) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)
            if creating {
                TextField("Your name", text: $name).textContentType(.name)
                TextField("Company", text: $company).textContentType(.organizationName)
                Picker("I am a", selection: $role) {
                    ForEach(Role.signUpChoices, id: \.self) { Text(roleName($0)).tag($0) }
                }
                if role == .staff {
                    SecureField("Staff code", text: $staffCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(creating ? .newPassword : .password)
        } footer: {
            Text("Free to join. Every bidder is reviewed and approved for their trades before they can bid. Plans, quantities and calculations are free to everyone.")
        }
        Section {
            Button {
                hideKeyboard()
                working = true
                Task {
                    if creating {
                        await store.createAccount(name: name, company: company, email: email, password: password,
                                                  role: role, staffCode: staffCode)
                    } else {
                        await store.signIn(email: email, password: password)
                    }
                    working = false
                    if store.user != nil, store.errorMessage == nil { dismiss() }
                }
            } label: {
                if working { ProgressView() } else { Text(creating ? "Create account" : "Sign in") }
            }
            .disabled(!canSubmit)
            if !creating {
                Button(resetSent ? "Password email sent. Check your inbox (and junk mail)." : "Forgot password? Email me a link") {
                    Task { resetSent = await store.sendPasswordReset(email: email) }
                }
                .font(.footnote)
                .disabled(resetSent || !email.contains("@"))
            }
        }
    }

    private var canSubmit: Bool {
        guard !working, !email.isEmpty, password.count >= 6 else { return false }
        guard creating else { return true }
        if name.isEmpty || company.isEmpty { return false }
        return role != .staff || !staffCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func roleName(_ role: Role) -> String {
        role == .staff ? "Eliskopes staff (needs code)" : role.label
    }
}
