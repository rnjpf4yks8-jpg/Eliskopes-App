import SwiftUI
import UniformTypeIdentifiers

// Staff tools in the app: add, change and delete projects, packages, plan PDFs and people.
// Bids are never written here: only the placeBid and awardClosedPackages Cloud Functions do that.

/// Largest plan or spec PDF staff can upload (storage.rules allows the same).
private let maxDocumentBytes = 50 * 1024 * 1024

/// Bid closes are entered and shown in Central Time, like the rest of Eliskopes.
private let central = TimeZone(identifier: "America/Chicago") ?? .current

// MARK: - Project

/// Staff add a project (+ on the projects list) or change one (press and hold it). Its packages are added
/// inside the project. Does in the app what `node admin.js load-project` does for the project itself.
struct ProjectSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The project being changed, or nil to add one.
    let editing: Project?
    @State private var name = ""
    @State private var city = ""
    @State private var round = ""
    @State private var owner = ""
    @State private var closesAt = ProjectSheet.defaultClose
    @State private var feature = true
    @State private var tried = false
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var deleting = false

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFeatured: Bool { editing != nil && editing?.id == store.featuredProjectID }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name, e.g. 4-Story Office Building", text: $name)
                        .textInputAutocapitalization(.words)
                    if tried && trimmed(name).isEmpty {
                        Text("Enter the project’s name.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                    }
                    TextField("City, e.g. Houston, TX", text: $city)
                        .textInputAutocapitalization(.words)
                    TextField("Owner, e.g. Bayou Office Partners", text: $owner)
                        .textInputAutocapitalization(.words)
                    TextField("Round, e.g. \(ProjectSheet.roundName(for: closesAt))", text: $round)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Project")
                }

                Section {
                    DatePicker("Bidding closes", selection: $closesAt, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, central)
                } footer: {
                    Text(editing == nil
                         ? "Central Time. Supplier packages close 3 hours earlier."
                         : "Central Time. Changing it moves every package not yet awarded (suppliers 3 hours earlier).")
                }

                Section {
                    if isFeatured {
                        Label("This project shows first in the app.", systemImage: "star.fill").foregroundStyle(Theme.ink)
                    } else {
                        Toggle("Show this project first", isOn: $feature)
                    }
                }

                if editing == nil {
                    Section {
                    } footer: {
                        Text("After adding it, open the project and tap + to add the main contract and each bid package.")
                    }
                } else {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete project", systemImage: "trash")
                        }
                        .disabled(saving || deleting)
                    } footer: {
                        Text("Deletes the project with every package, bid, question and plan PDF.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add project" : "Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button(editing == nil ? "Add" : "Save") { save() } }
                }
            }
            .confirmationDialog("Delete this project?", isPresented: $confirmDelete, titleVisibility: .visible) {
                if let editing {
                    Button("Delete \(editing.name)", role: .destructive) {
                        Task {
                            deleting = true
                            if await store.deleteProject(editing) { dismiss() }
                            deleting = false
                        }
                    }
                }
            } message: {
                if let editing { Text(ProjectSheet.deleteWarning(editing)) }
            }
            .overlay(alignment: .bottom) { ErrorBanner() }
            .overlay { if deleting { DeletingOverlay(text: "Deleting project…") } }
            .interactiveDismissDisabled(deleting)
            .onAppear {
                store.errorMessage = nil
                guard let editing else { return }
                name = editing.name
                city = editing.city
                round = editing.round
                owner = editing.owner
                closesAt = editing.closesAt
                feature = false
            }
        }
    }

    private func save() {
        tried = true
        guard !trimmed(name).isEmpty else { return }
        let taken = Set(store.projects.map(\.id))
        var project = editing ?? Project(id: Slug.make(trimmed(name), taken: taken, fallback: "project"),
                                         name: "", city: "", round: "", owner: "", closesAt: closesAt, status: "open")
        project.name = trimmed(name)
        project.city = trimmed(city)
        project.owner = trimmed(owner)
        project.round = trimmed(round).isEmpty ? ProjectSheet.roundName(for: closesAt) : trimmed(round)
        project.closesAt = closesAt
        Task {
            saving = true
            if await store.save(project, isNew: editing == nil, feature: feature && !isFeatured) { dismiss() }
            saving = false
        }
    }

    static func deleteWarning(_ project: Project) -> String {
        "\(project.name) is deleted for good, with every package, bid, question and plan PDF. Bidders lose it from the app. This can’t be undone."
    }

    /// "November round", from the month bidding closes.
    static func roundName(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = central
        let month = calendar.component(.month, from: date)
        return "\(DateFormatter().monthSymbols[month - 1]) round"
    }

    /// Four weeks from today at 3:00 PM Central.
    static var defaultClose: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = central
        let day = calendar.date(byAdding: .day, value: 28, to: .now) ?? .now
        return calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day) ?? day
    }
}

// MARK: - Package

/// Staff add a package to the open project, or change one. Bids are never touched, and once a package
/// has bids its budget and floor stay put.
struct PackageSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The package being changed, or nil to add one.
    let editing: Package?
    @State private var draft: Package
    @State private var budgetText = ""
    @State private var floorText = ""
    @State private var quantityText = ""
    @State private var lines: [EditableLine] = []
    @State private var problem: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var deleting = false

    struct EditableLine: Identifiable {
        let id = UUID()
        var item = ""
        var qty = ""
        var unit = ""
    }

    init(editing: Package?, order: Int, projectClose: Date) {
        self.editing = editing
        let start = editing ?? Package.blank(id: "", order: order, projectClose: projectClose)
        _draft = State(initialValue: start)
        if let editing {
            _budgetText = State(initialValue: Self.dollars(editing.budget))
            _floorText = State(initialValue: Self.dollars(editing.floor))
            _quantityText = State(initialValue: editing.primaryQty > 0 ? editing.primaryQty.quantityText : "")
            _lines = State(initialValue: editing.quantities.map {
                EditableLine(item: $0.item, qty: $0.qty.quantityText, unit: $0.unit)
            })
        }
    }

    private var priceFixed: Bool { editing?.hasBids ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code, e.g. Main or Pkg 3", text: $draft.code)
                    TextField("Name, e.g. Concrete", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    Picker("Trade", selection: $draft.trade) {
                        ForEach(Trades.all, id: \.key) { Text($0.label).tag($0.key) }
                    }
                    Picker("Who bids", selection: $draft.bidderType) {
                        ForEach([Role.gc, .sub, .supplier], id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Auction", selection: $draft.auction) {
                        Text(Auction.main.label).tag(Auction.main)
                        Text(Auction.supplier.label).tag(Auction.supplier)
                    }
                } header: {
                    Text("Package")
                } footer: {
                    Text("Bidders approved for \(Trades.label(draft.trade)) can bid. The supplier auction closes 3 hours before the main one.")
                }

                Section("Scope") {
                    TextField("What the package covers", text: $draft.scope, axis: .vertical).lineLimit(3...8)
                }

                Section {
                    LabeledContent("Budget ($)") {
                        TextField("1,250,000", text: $budgetText)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .onChange(of: budgetText) { _, text in
                                // The floor follows the budget at 85% until staff type their own.
                                guard editing == nil, let budget = Self.cents(text) else { return }
                                floorText = Self.dollars(budget * 85 / 100)
                            }
                    }
                    .disabled(priceFixed)
                    LabeledContent("Owner’s floor ($)") {
                        TextField("1,062,500", text: $floorText)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    .disabled(priceFixed)
                } header: {
                    Text("Budget")
                } footer: {
                    Text(priceFixed
                         ? "Bidding has started, so the budget and floor are fixed."
                         : "The first bid is 1% under the budget; bidding stops at the floor (85% of the budget unless you change it).")
                }

                Section {
                    LabeledContent("Quantity") {
                        TextField("3,160", text: $quantityText)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Unit") {
                        TextField("CY", text: $draft.primaryUnit)
                            .textInputAutocapitalization(.characters).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Unit costs are worked out per")
                } footer: {
                    Text("Bidders see the price per \(draft.primaryUnit.isEmpty ? "unit" : draft.primaryUnit) at the budget, the low bid and the next bid.")
                }

                Section {
                    ForEach($lines) { $line in
                        HStack {
                            TextField("Item", text: $line.item)
                            TextField("Qty", text: $line.qty)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                            TextField("Unit", text: $line.unit)
                                .textInputAutocapitalization(.characters).frame(width: 52)
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    Button { lines.append(EditableLine(unit: draft.primaryUnit)) } label: {
                        Label("Add a line", systemImage: "plus")
                    }
                    if !lines.isEmpty { Toggle("Show a total row", isOn: $draft.showTotal) }
                } header: {
                    Text("Takeoff")
                } footer: {
                    Text("The Quantities screen. Swipe left on a line to remove it. Show a total only when every line is in the same unit.")
                }

                Section("Schedule") {
                    TextField("Start, e.g. Jan 12, 2027", text: $draft.schedule.start)
                    TextField("Duration, e.g. 14 weeks", text: $draft.schedule.duration)
                    TextField("Payment terms", text: $draft.schedule.payment, axis: .vertical).lineLimit(1...4)
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(Theme.red) }
                }

                if let editing {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete package", systemImage: "trash")
                        }
                        .disabled(saving || deleting)
                    } footer: {
                        Text(editing.hasBids
                             ? "It has \(editing.bids) bid\(editing.bids == 1 ? "" : "s"). Deleting removes them with its questions."
                             : "Deletes the package with its questions.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add package" : "Edit \(editing?.code ?? "package")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button(editing == nil ? "Add" : "Save") { save() } }
                }
            }
            .confirmationDialog("Delete this package?", isPresented: $confirmDelete, titleVisibility: .visible) {
                if let editing {
                    Button("Delete \(editing.code) · \(editing.name)", role: .destructive) {
                        Task {
                            deleting = true
                            if await store.deletePackage(editing) { dismiss() }
                            deleting = false
                        }
                    }
                }
            } message: {
                Text("Its bids, questions and award are deleted for good. Plan PDFs other packages still list are kept. This can’t be undone.")
            }
            .overlay(alignment: .bottom) { ErrorBanner() }
            .overlay { if deleting { DeletingOverlay(text: "Deleting package…") } }
            .interactiveDismissDisabled(deleting)
            .onAppear { store.errorMessage = nil }
        }
    }

    private func save() {
        problem = nil
        var package = draft
        package.code = package.code.trimmingCharacters(in: .whitespacesAndNewlines)
        package.name = package.name.trimmingCharacters(in: .whitespacesAndNewlines)
        package.primaryUnit = package.primaryUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !package.code.isEmpty, !package.name.isEmpty else {
            problem = "Enter the package’s code and name."
            return
        }
        guard let budget = Self.cents(budgetText), budget > 0 else {
            problem = "Enter the established budget in dollars."
            return
        }
        guard let floor = Self.cents(floorText), floor > 0, floor <= budget else {
            problem = "The owner’s floor is more than $0 and no more than the budget."
            return
        }
        if !priceFixed {
            package.budget = budget
            package.floor = floor
        }
        package.primaryQty = Self.number(quantityText) ?? 0
        if package.primaryUnit.isEmpty { package.primaryUnit = "LS" }
        package.quantities = lines.compactMap { line in
            let item = line.item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { return nil }
            return QuantityLine(item: item, qty: Self.number(line.qty) ?? 0,
                                unit: line.unit.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if package.quantities.isEmpty { package.showTotal = false }

        let projectClose = store.project?.closesAt ?? package.closesAt
        var moveClose = false
        if editing == nil {
            package.id = Slug.make(package.name, taken: Set(store.packages.map(\.id)), fallback: "package")
            package.closesAt = Package.close(for: package.auction, projectClose: projectClose)
        } else if let editing, editing.auction != package.auction, !editing.isAwarded {
            package.closesAt = Package.close(for: package.auction, projectClose: projectClose)
            moveClose = true
        }
        Task {
            saving = true
            if await store.save(package, isNew: editing == nil, moveClose: moveClose) { dismiss() }
            saving = false
        }
    }

    /// "1,250,000" or "1250000.50" → cents.
    static func cents(_ text: String) -> Int? {
        number(text).map { Int(($0 * 100).rounded()) }
    }

    static func number(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    /// Cents as dollars for typing: "1250000" or "1250000.50".
    static func dollars(_ cents: Int) -> String {
        cents % 100 == 0 ? String(cents / 100) : String(format: "%.2f", Double(cents) / 100)
    }
}

// MARK: - Plans and specs

/// Staff upload a plan or spec PDF to the package on screen, or to every package in the project. Given a
/// listed document still waiting for its file ("Coming soon"), the PDF goes on that document.
struct DocumentSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// A document already listed (waiting for its PDF, or getting a new one), or nil to add one.
    let replacing: ProjectDocument?
    @State private var name = ""
    @State private var detail = ""
    @State private var everyPackage = false
    @State private var file: (data: Data, name: String)?
    @State private var choosing = false
    @State private var problem: String?
    @State private var uploading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { choosing = true } label: {
                        if let file {
                            HStack(spacing: 12) {
                                Text("PDF")
                                    .font(Theme.mono(10, .semibold)).foregroundStyle(Theme.blue)
                                    .frame(width: 36, height: 42)
                                    .background(Theme.blueTint, in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name).foregroundStyle(Theme.ink).lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                                        .font(.footnote).foregroundStyle(Theme.slate)
                                }
                            }
                        } else {
                            Label("Choose PDF from Files", systemImage: "doc.badge.plus")
                        }
                    }
                } footer: {
                    Text("Up to 50 MB. Anyone can open it from the Plans & Specs button, like the rest of the project.")
                }

                Section {
                    TextField("Name, e.g. Structural plans", text: $name)
                        .textInputAutocapitalization(.sentences)
                    TextField("Detail, e.g. S-001 to S-501, 24 sheets", text: $detail)
                }

                if store.packages.count > 1 {
                    Section {
                        Toggle("Add to every package", isOn: $everyPackage)
                    } footer: {
                        Text(everyPackage
                             ? "All \(store.packages.count) packages in \(store.project?.name ?? "this project") list it."
                             : "Only \(store.currentPackage.map { "\($0.code) · \($0.name)" } ?? "this package") lists it.")
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(Theme.red) }
                }
            }
            .navigationTitle(replacing == nil ? "Add PDF" : "Attach PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(uploading) }
                ToolbarItem(placement: .confirmationAction) {
                    if uploading { ProgressView() } else { Button("Upload") { upload() } }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): read(url)
                case .failure(let error): problem = error.localizedDescription
                }
            }
            .interactiveDismissDisabled(uploading)
            .onAppear {
                guard let replacing else { return }
                name = replacing.name
                detail = replacing.detail
            }
        }
    }

    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= maxDocumentBytes else {
                problem = "That PDF is \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)). PDFs can be up to 50 MB."
                return
            }
            file = (data, url.lastPathComponent)
            problem = nil
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            problem = "Couldn’t read that file: \(error.localizedDescription)"
        }
    }

    private func upload() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let file else {
            problem = "Choose the PDF first."
            return
        }
        guard !trimmedName.isEmpty else {
            problem = "Give the document a name."
            return
        }
        uploading = true
        Task {
            let done = await store.addDocument(file.data, fileName: file.name, name: trimmedName,
                                               detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                                               replacing: replacing, toEveryPackage: everyPackage)
            uploading = false
            if done {
                store.notice = "\(trimmedName) uploaded."
                dismiss()
            } else {
                problem = store.errorMessage ?? "Couldn’t upload it. Try again."
                store.errorMessage = nil
            }
        }
    }
}

// MARK: - People

/// Staff make an account for someone else, with their role and trades, so they don't have to sign up and
/// wait for review. They get an email to choose their password, or staff give them one.
struct AddPersonSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var role: Role = .sub
    @State private var approved = true
    @State private var trades: Set<String> = []
    @State private var password = ""
    @State private var tried = false
    @State private var working = false
    @State private var problem: String?
    @State private var added: AppUser?
    @State private var emailed = false

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailLooksRight: Bool {
        let parts = trimmed(email).split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !trimmed(email).contains(" ")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let added {
                    Section {
                        Label("\(added.company.isEmpty ? added.name : added.company) is set up as \(added.role == .staff ? "Eliskopes staff" : "a \(added.role.label.lowercased())").",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        Text(emailed
                             ? "They’ll get an email with a link to choose their password (ask them to check junk mail). Then they sign in on the Account screen with \(added.email ?? "their email")."
                             : "Give them the password you typed. They sign in on the Account screen with \(added.email ?? "their email").")
                            .foregroundStyle(Theme.slate)
                    }
                    Section { Button("Add another person") { reset() } }
                } else {
                    Section {
                        TextField("Name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                        TextField("Company", text: $company).textContentType(.organizationName).textInputAutocapitalization(.words)
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if tried && (trimmed(name).isEmpty || !emailLooksRight) {
                            Text("Enter their name and email address.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                        }
                    } header: {
                        Text("Person")
                    }

                    Section {
                        Picker("Role", selection: $role) {
                            ForEach(Role.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        if role.isBidder { Toggle("Approved to bid", isOn: $approved) }
                    } footer: {
                        Text(role.abilities)
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

                    Section {
                        SecureField("Password (optional)", text: $password).textContentType(.newPassword)
                        if tried && !password.isEmpty && password.count < 6 {
                            Text("Passwords are at least 6 characters.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                        }
                    } footer: {
                        Text("Leave blank and they’ll get an email to choose their own password. Or type one (at least 6 characters) to give them yourself.")
                    }

                    if let problem {
                        Section { Text(problem).foregroundStyle(Theme.red) }
                    }
                }
            }
            .navigationTitle("Add person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if added == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if working { ProgressView() } else { Button("Add") { add() } }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .interactiveDismissDisabled(working)
        }
    }

    private func add() {
        tried = true
        problem = nil
        guard !trimmed(name).isEmpty, emailLooksRight, password.isEmpty || password.count >= 6 else { return }
        if store.people.contains(where: { $0.email?.lowercased() == trimmed(email).lowercased() }) {
            problem = "\(trimmed(email)) already has an account. Find them in the list to change their role or trades."
            return
        }
        let bidder = role.isBidder
        let person = AppUser(uid: "", name: trimmed(name), company: trimmed(company), role: role, email: trimmed(email),
                             trades: bidder ? Trades.all.map(\.key).filter { trades.contains($0) } : [],
                             approved: bidder ? approved : true)
        working = true
        Task {
            let saved = await store.addPerson(person, password: password)
            working = false
            if let saved {
                emailed = password.isEmpty
                added = saved
            } else {
                problem = store.errorMessage ?? "Couldn’t add them. Try again."
                store.errorMessage = nil
            }
        }
    }

    private func reset() {
        name = ""
        company = ""
        email = ""
        password = ""
        role = .sub
        approved = true
        trades = []
        tried = false
        problem = nil
        added = nil
    }
}

// MARK: - Shared

/// Shown while a delete that can take a while (a whole project) runs.
struct DeletingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(text).font(Theme.sans(15, .semibold)).foregroundStyle(Theme.ink)
                Text("Keep the app open until it’s done.").font(Theme.sans(13)).foregroundStyle(Theme.slate)
            }
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
