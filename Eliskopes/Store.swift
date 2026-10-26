import Foundation
import Observation

/// App state. Reads and writes go through a ProjectBackend: Firebase when the app has a
/// GoogleService-Info.plist, otherwise the in-memory sample project.
@MainActor
@Observable
final class ProjectStore {
    let backend: ProjectBackend
    var projects: [Project] = []
    var featuredProjectID: String?
    /// The open project. Its packages stay live while it's open.
    var project: Project?
    var packages: [Package] = []
    var currentPackageID = ""
    var user: AppUser?
    /// The signed-in bidder's anonymous ID per project, e.g. "B-8CW", once they've bid there.
    var bidderIDs: [String: String] = [:]
    /// Live bids and questions for the package on screen.
    var bids: [Bid] = []
    var questions: [Question] = []
    /// After the award: anonymous ID → company, for the package on screen.
    var revealed: [String: String] = [:]
    /// Everyone with an account. Loaded when staff open People.
    var people: [AppUser] = []
    var isLoading = true
    var isBidding = false
    var errorMessage: String?
    /// A short message that slides in at the top: bid placed, outbid, question posted.
    var notice: String?

    private var packagesTask: Task<Void, Never>?
    private var bidsTask: Task<Void, Never>?
    private var questionsTask: Task<Void, Never>?
    private var askedForPush = false

    init(backend: ProjectBackend) {
        self.backend = backend
    }

    var isDemo: Bool { backend.isDemo }

    var currentPackage: Package? {
        packages.first { $0.id == currentPackageID } ?? packages.first
    }

    // MARK: Loading

    func start() async {
        isLoading = true
        defer { isLoading = false }
        await attempt {
            user = try await backend.currentUser()
            try await reloadProjects()
        }
        if user != nil { await askForPush() }
    }

    func reloadProjects() async throws {
        featuredProjectID = try await backend.featuredProjectID()
        projects = try await backend.loadProjects().sorted { ($0.isOpen ? 0 : 1, $0.closesAt) < ($1.isOpen ? 0 : 1, $1.closesAt) }
    }

    func refreshProjects() async {
        await attempt { try await reloadProjects() }
    }

    /// Opens a project and keeps its packages live: every new low bid shows up on every phone.
    func open(projectID: String) async {
        guard let picked = projects.first(where: { $0.id == projectID }) else { return }
        if picked.id != project?.id {
            project = picked
            packages = []
            currentPackageID = ""
            bids = []
            questions = []
            packagesTask?.cancel()
            let stream = backend.packageUpdates(projectID: picked.id)
            packagesTask = Task { [weak self] in
                do {
                    for try await list in stream {
                        self?.receive(list.sorted { $0.order < $1.order })
                    }
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
        await loadBidderID()
    }

    private func receive(_ list: [Package]) {
        let mine = myBidderID
        for package in list {
            guard let mine, let before = packages.first(where: { $0.id == package.id }) else { continue }
            if before.lowBidder == mine, package.lowBidder != mine, !package.isAwarded {
                notice = "Outbid on \(package.name). New low \(Money.text(package.current)), next bid \(Money.text(package.nextBid))."
            }
            if !before.isAwarded, package.isAwarded, package.lowBidder == mine {
                notice = "You won \(package.name) at \(Money.text(package.current))."
            }
        }
        let firstLoad = packages.isEmpty
        packages = list
        if firstLoad || !list.contains(where: { $0.id == currentPackageID }) {
            currentPackageID = list.first?.id ?? ""
            watchCurrentPackage()
        } else if let current = currentPackage, current.isAwarded, revealed.isEmpty {
            Task { await loadRevealed() }
        }
    }

    /// Follows the bids and questions of the package on screen.
    private func watchCurrentPackage() {
        bidsTask?.cancel()
        questionsTask?.cancel()
        bids = []
        questions = []
        revealed = [:]
        guard let project, !currentPackageID.isEmpty else { return }
        let bidStream = backend.bidUpdates(projectID: project.id, packageID: currentPackageID)
        let questionStream = backend.questionUpdates(projectID: project.id, packageID: currentPackageID)
        bidsTask = Task { [weak self] in
            do { for try await list in bidStream { self?.bids = list } } catch { self?.errorMessage = error.localizedDescription }
        }
        questionsTask = Task { [weak self] in
            do { for try await list in questionStream { self?.questions = list } } catch { self?.errorMessage = error.localizedDescription }
        }
        if currentPackage?.isAwarded == true { Task { await loadRevealed() } }
    }

    private func loadRevealed() async {
        guard let project, let package = currentPackage, package.isAwarded else { return }
        await attempt { revealed = try await backend.revealedNames(projectID: project.id, packageID: package.id) }
    }

    private func loadBidderID() async {
        guard let project, let user, user.role.isBidder, bidderIDs[project.id] == nil else { return }
        if let id = try? await backend.myBidderID(projectID: project.id, uid: user.uid) { bidderIDs[project.id] = id }
    }

    // MARK: Navigation

    var currentIndex: Int { packages.firstIndex { $0.id == currentPackageID } ?? 0 }
    var hasPreviousPackage: Bool { currentIndex > 0 }
    var hasNextPackage: Bool { currentIndex < packages.count - 1 }

    func stepPackage(_ delta: Int) {
        let target = currentIndex + delta
        guard packages.indices.contains(target) else { return }
        select(packages[target].id)
    }

    func select(_ packageID: String) {
        guard packageID != currentPackageID else { return }
        currentPackageID = packageID
        watchCurrentPackage()
    }

    // MARK: Account

    func signIn(email: String, password: String) async {
        await attempt { user = try await backend.signIn(email: email, password: password) }
        await afterSignIn()
    }

    /// Staff sign-up makes an owner account first (it can't bid), then upgrades it with the staff code.
    func createAccount(name: String, company: String, email: String, password: String, role: Role, staffCode: String = "") async {
        await attempt {
            user = try await backend.createAccount(name: name, company: company, email: email, password: password, role: role)
        }
        guard user != nil else { return }
        if role == .staff, !(await claimStaff(code: staffCode)) {
            errorMessage = (errorMessage ?? "That staff code didn’t work.")
                + " Your account was created; enter the staff code below to try again."
        }
        await afterSignIn()
    }

    func claimStaff(code: String) async -> Bool {
        var granted = false
        await attempt {
            try await backend.claimStaff(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            user?.role = .staff
            user?.approved = true
            granted = true
        }
        return granted
    }

    /// Demo mode only: switch between the sample accounts without a password.
    func signInDemo(as person: AppUser?) async {
        (backend as? SampleBackend)?.demoUser = person
        user = person
        await afterSignIn()
    }

    func signOut() async {
        await attempt {
            try backend.signOut()
            user = nil
            bidderIDs = [:]
        }
    }

    /// Re-reads the account, so a bidder sees their approval as soon as staff give it.
    func refreshUser() async {
        await attempt { user = try await backend.currentUser() }
    }

    private func afterSignIn() async {
        bidderIDs = [:]
        await loadBidderID()
        if user != nil { await askForPush() }
    }

    /// Asks once per launch for permission to send outbid and award alerts, then saves the push token.
    private func askForPush() async {
        guard !isDemo, !askedForPush else { return }
        askedForPush = true
        PushRelay.shared.onToken = { [weak self] token in
            Task { @MainActor in
                guard let self, let uid = self.user?.uid else { return }
                try? await self.backend.savePushToken(token, uid: uid)
            }
        }
        await PushRelay.shared.register()
    }

    // MARK: Permissions

    var isStaff: Bool { user?.role == .staff }
    var myBidderID: String? { project.flatMap { bidderIDs[$0.id] } }

    func isMine(_ bidder: String?) -> Bool {
        guard let bidder, let mine = myBidderID else { return false }
        return bidder == mine
    }

    /// Why the signed-in person can't bid on a package right now, or nil if they can.
    func bidBlock(_ package: Package, now: Date = .now) -> String? {
        if package.isClosed(at: now) { return "Bidding closed" }
        if package.reachedFloor { return "Bidding reached the owner’s floor" }
        guard let user else { return "Sign in to bid" }
        guard user.role.isBidder else { return user.role == .owner ? "Owners watch; bidders bid" : "Staff accounts can’t bid" }
        guard user.isApproved else { return "Your account is waiting for approval" }
        guard user.approvedTrades.contains(package.trade) else { return "Not approved for \(Trades.label(package.trade))" }
        if isMine(package.lowBidder) { return "You hold the low bid" }
        return nil
    }

    var canAsk: Bool { (user?.role.isBidder ?? false) && (user?.isApproved ?? false) }

    // MARK: Bidding

    /// Bids exactly 1% under the current low. If someone else bid first, the server says so and nothing is placed.
    func placeBid(on package: Package) async {
        guard let project else { return }
        isBidding = true
        defer { isBidding = false }
        await attempt {
            let receipt = try await backend.placeBid(projectID: project.id, packageID: package.id, amount: package.nextBid)
            bidderIDs[project.id] = receipt.bidder
            notice = "Bid placed: \(Money.text(receipt.amount)) on \(package.name). You hold the low bid."
        }
    }

    // MARK: Q&A

    func ask(_ text: String) async -> Bool {
        guard let project, let package = currentPackage else { return false }
        var posted = false
        await attempt {
            try await backend.ask(text, projectID: project.id, packageID: package.id)
            notice = "Question posted. Eliskopes answers it for every bidder."
            posted = true
        }
        return posted
    }

    func answer(_ text: String, question: Question) async -> Bool {
        guard let project, let package = currentPackage else { return false }
        var posted = false
        await attempt {
            try await backend.answer(text, questionID: question.id, projectID: project.id, packageID: package.id)
            posted = true
        }
        return posted
    }

    // MARK: People (staff)

    func loadPeople() async {
        await attempt {
            people = try await backend.loadPeople().sorted {
                ($0.isApproved ? 1 : 0, $0.company.lowercased()) < ($1.isApproved ? 1 : 0, $1.company.lowercased())
            }
        }
    }

    var waitingForReview: Int { people.filter { !$0.isApproved && $0.role != .staff }.count }

    func review(_ person: AppUser, role: Role, approved: Bool, trades: [String]) async -> Bool {
        var saved = false
        await attempt {
            try await backend.review(uid: person.uid, role: role, approved: approved, trades: trades)
            if let i = people.firstIndex(where: { $0.uid == person.uid }) {
                people[i].role = role
                people[i].approved = approved
                people[i].trades = trades
            }
            if user?.uid == person.uid { user = people.first { $0.uid == person.uid } }
            saved = true
        }
        return saved
    }

    private func attempt(_ work: () async throws -> Void) async {
        do {
            errorMessage = nil
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Home screen tiles

extension ProjectStore {
    /// One-line value under each of the 10 buttons.
    func tileSummary(_ field: PackageField, package: Package, now: Date) -> String {
        switch field {
        case .package: return package.bidderType.label
        case .budget: return Money.text(package.budget, showCents: false)
        case .quantities: return "\(package.primaryQty.quantityText) \(package.primaryUnit)"
        case .unitCosts: return "\(package.unitRate(package.budget)) at budget"
        case .documents: return "\(package.documents.count) documents · free"
        case .schedule: return "Starts \(package.schedule.start.replacingOccurrences(of: ", 2027", with: ""))"
        case .approvals:
            let ready = package.approvals.filter(\.ready).count
            return "\(ready) of \(package.approvals.count) ready"
        case .questions:
            let open = questions.filter { !$0.isAnswered }.count
            if questions.isEmpty { return "No questions yet" }
            return "\(questions.count - open) answered" + (open > 0 ? " · \(open) open" : "")
        case .bidHistory:
            guard package.bids > 0 else { return "No bids yet" }
            return "\(package.bids) bid\(package.bids == 1 ? "" : "s") · \(Money.percentUnder(package.current, budget: package.budget)) under"
        case .placeBid:
            if package.isAwarded { return package.winner.map { "Won by \($0)" } ?? "Closed, no bids" }
            if package.isClosed(at: now) { return "Bidding closed" }
            if package.reachedFloor { return "At the floor" }
            return "Next \(Money.text(package.nextBid))"
        }
    }
}
