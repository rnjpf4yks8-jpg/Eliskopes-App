import Foundation

/// Everything the app reads or writes. FirebaseBackend talks to Firebase; SampleBackend keeps
/// sample data in memory so the app runs (and can be demoed) before Firebase is set up.
@MainActor
protocol ProjectBackend: AnyObject {
    var isDemo: Bool { get }

    // Account
    func currentUser() async throws -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    /// New accounts start unapproved. Staff review each one and approve its trades.
    func createAccount(name: String, company: String, email: String, password: String, role: Role) async throws -> AppUser
    /// Makes the signed-in user staff if `code` is the staff code (checked on the server).
    func claimStaff(code: String) async throws
    func signOut() throws
    /// Saves this phone's push token so the server can send "You've been outbid" and award alerts.
    func savePushToken(_ token: String, uid: String) async throws

    // Projects and packages
    func loadProjects() async throws -> [Project]
    /// The project featured now (config/app.currentProject), if one is set.
    func featuredProjectID() async throws -> String?
    /// Live: yields the project's packages again whenever any of them changes (a new low bid, an award).
    func packageUpdates(projectID: String) -> AsyncThrowingStream<[Package], Error>
    /// Live: a package's bids, oldest first.
    func bidUpdates(projectID: String, packageID: String) -> AsyncThrowingStream<[Bid], Error>
    /// Live: a package's questions, oldest first.
    func questionUpdates(projectID: String, packageID: String) -> AsyncThrowingStream<[Question], Error>
    /// The signed-in bidder's anonymous ID on a project, once they've bid there.
    func myBidderID(projectID: String, uid: String) async throws -> String?
    /// After the award: anonymous bidder ID → company name.
    func revealedNames(projectID: String, packageID: String) async throws -> [String: String]

    // Bidding and Q&A
    /// Bids `amount` (cents) on a package. The server checks it is exactly 1% under the current low.
    func placeBid(projectID: String, packageID: String, amount: Int) async throws -> BidReceipt
    func ask(_ text: String, projectID: String, packageID: String) async throws
    /// Staff only.
    func answer(_ text: String, questionID: String, projectID: String, packageID: String) async throws

    // People (staff)
    func loadPeople() async throws -> [AppUser]
    func review(uid: String, role: Role, approved: Bool, trades: [String]) async throws
}

struct BackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// In-memory backend with the sample project from eliskopes.com. Nothing is saved between launches.
/// Rival bidders sometimes answer a bid within seconds, so the reverse auction can be felt in a demo.
@MainActor
final class SampleBackend: ProjectBackend {
    let isDemo = true
    /// Demo mode has no passwords: the Account screen picks who is signed in.
    var demoUser: AppUser?

    private var projects = [SampleData.project]
    private var packages: [String: [Package]] = [SampleData.project.id: SampleData.packages]
    private var bids: [String: [Bid]] = SampleData.bids
    private var questions: [String: [Question]] = SampleData.questions
    private var people = SampleData.people
    private var packageListeners: [UUID: AsyncThrowingStream<[Package], Error>.Continuation] = [:]
    private var bidListeners: [UUID: (key: String, continuation: AsyncThrowingStream<[Bid], Error>.Continuation)] = [:]
    private var questionListeners: [UUID: (key: String, continuation: AsyncThrowingStream<[Question], Error>.Continuation)] = [:]

    // MARK: Account

    func currentUser() async throws -> AppUser? { demoUser }

    func signIn(email: String, password: String) async throws -> AppUser {
        throw BackendError(message: "Demo mode has no passwords. Pick a sample account instead.")
    }

    func createAccount(name: String, company: String, email: String, password: String, role: Role) async throws -> AppUser {
        throw BackendError(message: "Demo mode can't create accounts. Pick a sample account instead.")
    }

    func claimStaff(code: String) async throws {
        throw BackendError(message: "Demo mode has no staff codes. Pick the sample staff account instead.")
    }

    func signOut() throws { demoUser = nil }

    func savePushToken(_ token: String, uid: String) async throws {}

    // MARK: Projects and packages

    func loadProjects() async throws -> [Project] { projects }

    func featuredProjectID() async throws -> String? { SampleData.project.id }

    func packageUpdates(projectID: String) -> AsyncThrowingStream<[Package], Error> {
        let (stream, continuation) = AsyncThrowingStream<[Package], Error>.makeStream()
        let id = UUID()
        packageListeners[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.packageListeners[id] = nil } }
        continuation.yield(packages[projectID] ?? [])
        return stream
    }

    func bidUpdates(projectID: String, packageID: String) -> AsyncThrowingStream<[Bid], Error> {
        let (stream, continuation) = AsyncThrowingStream<[Bid], Error>.makeStream()
        let id = UUID()
        bidListeners[id] = (packageID, continuation)
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.bidListeners[id] = nil } }
        continuation.yield(bids[packageID] ?? [])
        return stream
    }

    func questionUpdates(projectID: String, packageID: String) -> AsyncThrowingStream<[Question], Error> {
        let (stream, continuation) = AsyncThrowingStream<[Question], Error>.makeStream()
        let id = UUID()
        questionListeners[id] = (packageID, continuation)
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.questionListeners[id] = nil } }
        continuation.yield(questions[packageID] ?? [])
        return stream
    }

    func myBidderID(projectID: String, uid: String) async throws -> String? {
        SampleData.bidderIDs[uid]
    }

    func revealedNames(projectID: String, packageID: String) async throws -> [String: String] { [:] }

    // MARK: Bidding

    func placeBid(projectID: String, packageID: String, amount: Int) async throws -> BidReceipt {
        guard let user = demoUser, let bidder = SampleData.bidderIDs[user.uid] else {
            throw BackendError(message: "Sign in as an approved bidder to bid.")
        }
        guard var list = packages[projectID], let i = list.firstIndex(where: { $0.id == packageID }) else {
            throw BackendError(message: "That package isn't in this project.")
        }
        let package = list[i]
        guard user.isApproved, user.approvedTrades.contains(package.trade) else {
            throw BackendError(message: "\(user.company) isn't approved to bid on \(package.name).")
        }
        guard !package.isClosed() else { throw BackendError(message: "Bidding on \(package.name) has closed.") }
        guard package.lowBidder != bidder else { throw BackendError(message: "You already hold the low bid on \(package.name).") }
        guard !package.reachedFloor else { throw BackendError(message: "Bidding on \(package.name) has reached the owner's floor.") }
        guard amount == package.nextBid else {
            throw BackendError(message: "The low bid just changed. The next bid is now \(Money.text(package.nextBid)).")
        }
        try await Task.sleep(for: .milliseconds(400))
        record(Bid(bidder: bidder, amount: amount, at: .now), packageID: packageID, projectID: projectID, list: &list, index: i)
        scheduleRivalReply(projectID: projectID, packageID: packageID, after: bidder)
        return BidReceipt(amount: amount, bidder: bidder)
    }

    private func record(_ bid: Bid, packageID: String, projectID: String, list: inout [Package], index i: Int) {
        list[i].lowBid = bid.amount
        list[i].lowBidder = bid.bidder
        list[i].bidCount = list[i].bids + 1
        // A bid in the last 5 minutes pushes the close out 5 minutes, like the server.
        if list[i].closesAt.timeIntervalSinceNow < 300 { list[i].closesAt = list[i].closesAt.addingTimeInterval(300) }
        packages[projectID] = list
        bids[packageID, default: []].append(bid)
        packageListeners.values.forEach { $0.yield(list) }
        bidListeners.values.filter { $0.key == packageID }.forEach { $0.continuation.yield(bids[packageID] ?? []) }
    }

    /// Two times in three, a rival undercuts the demo bidder 6 to 14 seconds later.
    private func scheduleRivalReply(projectID: String, packageID: String, after bidder: String) {
        guard Double.random(in: 0..<1) < 0.65 else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 6...14)))
            guard let self, var list = self.packages[projectID], let i = list.firstIndex(where: { $0.id == packageID }) else { return }
            let package = list[i]
            guard package.lowBidder == bidder, !package.isClosed(), !package.reachedFloor else { return }
            let earlier = Set((self.bids[packageID] ?? []).map(\.bidder)).subtracting(SampleData.bidderIDs.values)
            let rival = earlier.randomElement() ?? SampleData.rivals.randomElement() ?? "B-7Q2"
            self.record(Bid(bidder: rival, amount: package.nextBid, at: .now), packageID: packageID, projectID: projectID, list: &list, index: i)
        }
    }

    // MARK: Q&A

    func ask(_ text: String, projectID: String, packageID: String) async throws {
        questions[packageID, default: []].append(Question(text: text, askedAt: .now))
        notifyQuestions(packageID)
    }

    func answer(_ text: String, questionID: String, projectID: String, packageID: String) async throws {
        guard let i = questions[packageID]?.firstIndex(where: { $0.id == questionID }) else { return }
        questions[packageID]?[i].answer = text
        questions[packageID]?[i].answeredAt = .now
        notifyQuestions(packageID)
    }

    private func notifyQuestions(_ packageID: String) {
        questionListeners.values.filter { $0.key == packageID }.forEach { $0.continuation.yield(questions[packageID] ?? []) }
    }

    // MARK: People

    func loadPeople() async throws -> [AppUser] { people }

    func review(uid: String, role: Role, approved: Bool, trades: [String]) async throws {
        guard let i = people.firstIndex(where: { $0.uid == uid }) else { return }
        people[i].role = role
        people[i].approved = approved
        people[i].trades = trades
        if demoUser?.uid == uid { demoUser = people[i] }
    }
}
