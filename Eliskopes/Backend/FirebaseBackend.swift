#if canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Firestore layout (see firebase/README.md):
///   config/app                                         { currentProject }
///   users/{uid}                                        AppUser (+ fcmTokens)
///   projects/{projectID}                               Project
///   projects/{projectID}/packages/{packageID}          Package
///   projects/{projectID}/packages/{packageID}/bids/{autoID}       Bid (written only by placeBid)
///   projects/{projectID}/packages/{packageID}/questions/{autoID}  Question
///   projects/{projectID}/packages/{packageID}/reveal/names        { bidderID: company } after the award
///   projects/{projectID}/bidders/{uid}                 { id, company }: the bidder's anonymous ID (private)
@MainActor
final class FirebaseBackend: ProjectBackend {
    let isDemo = false
    private let db = Firestore.firestore()

    // MARK: Account

    func currentUser() async throws -> AppUser? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return try await loadUser(uid)
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        guard let user = try await loadUser(result.user.uid) else {
            throw BackendError(message: "This account has no Eliskopes profile yet. Ask Eliskopes staff to set it up.")
        }
        return user
    }

    /// New accounts start unapproved with no trades (the security rules allow nothing else). Staff accounts
    /// start as owners, which can't bid, and are upgraded by `claimStaff`.
    func createAccount(name: String, company: String, email: String, password: String, role: Role) async throws -> AppUser {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let user = AppUser(uid: result.user.uid, name: name, company: company, role: role == .staff ? .owner : role,
                           email: email, trades: [], approved: false)
        try db.collection("users").document(user.uid).setData(from: user)
        return user
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func savePushToken(_ token: String, uid: String) async throws {
        try await db.collection("users").document(uid).updateData(["fcmTokens": FieldValue.arrayUnion([token])])
    }

    private func loadUser(_ uid: String) async throws -> AppUser? {
        let snap = try await db.collection("users").document(uid).getDocument()
        return snap.exists ? try snap.data(as: AppUser.self) : nil
    }

    /// The claimStaff Cloud Function (firebase/functions/staff.js) checks the code and sets the role.
    func claimStaff(code: String) async throws {
        struct Granted: Decodable { var role: String }
        let _: Granted = try await callFunction("claimStaff", ["code": code])
    }

    // MARK: Projects and packages

    func loadProjects() async throws -> [Project] {
        let snap = try await db.collection("projects").getDocuments()
        return try snap.documents.map { doc in
            var project = try doc.data(as: Project.self)
            project.id = doc.documentID
            return project
        }
    }

    func featuredProjectID() async throws -> String? {
        try await db.collection("config").document("app").getDocument().get("currentProject") as? String
    }

    func packageUpdates(projectID: String) -> AsyncThrowingStream<[Package], Error> {
        listen(packagesRef(projectID).order(by: "order")) { doc in
            var package = try doc.data(as: Package.self)
            package.id = doc.documentID
            return package
        }
    }

    func bidUpdates(projectID: String, packageID: String) -> AsyncThrowingStream<[Bid], Error> {
        listen(packagesRef(projectID).document(packageID).collection("bids").order(by: "at")) { doc in
            var bid = try doc.data(as: Bid.self)
            bid.id = doc.documentID
            return bid
        }
    }

    func questionUpdates(projectID: String, packageID: String) -> AsyncThrowingStream<[Question], Error> {
        listen(packagesRef(projectID).document(packageID).collection("questions").order(by: "askedAt")) { doc in
            // A question just posted from this phone has no server time yet; use the estimate.
            var question = try doc.data(as: Question.self, with: .estimate)
            question.id = doc.documentID
            return question
        }
    }

    func myBidderID(projectID: String, uid: String) async throws -> String? {
        let snap = try await db.collection("projects").document(projectID).collection("bidders").document(uid).getDocument()
        return snap.get("id") as? String
    }

    func revealedNames(projectID: String, packageID: String) async throws -> [String: String] {
        let snap = try await packagesRef(projectID).document(packageID).collection("reveal").document("names").getDocument()
        return (snap.data() as? [String: String]) ?? [:]
    }

    /// Turns a Firestore query into a live stream that ends when the listening screen goes away.
    private func listen<T>(_ query: Query, _ decode: @escaping (QueryDocumentSnapshot) throws -> T) -> AsyncThrowingStream<[T], Error> {
        AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                do {
                    continuation.yield(try snapshot.documents.map(decode))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: Bidding and Q&A

    /// The placeBid Cloud Function (firebase/functions/bids.js) checks the price, the deadline and the
    /// bidder's approval in one transaction, so two phones bidding at the same moment can't both win.
    func placeBid(projectID: String, packageID: String, amount: Int) async throws -> BidReceipt {
        try await callFunction("placeBid", ["projectId": projectID, "packageId": packageID, "amount": amount])
    }

    /// Posted without the asker's name or account, so other bidders can't tell who asked.
    func ask(_ text: String, projectID: String, packageID: String) async throws {
        _ = try await packagesRef(projectID).document(packageID).collection("questions").addDocument(data: [
            "text": text,
            "askedAt": FieldValue.serverTimestamp()
        ])
    }

    func answer(_ text: String, questionID: String, projectID: String, packageID: String) async throws {
        try await packagesRef(projectID).document(packageID).collection("questions").document(questionID).updateData([
            "answer": text,
            "answeredAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: People (staff)

    func loadPeople() async throws -> [AppUser] {
        let snap = try await db.collection("users").getDocuments()
        return try snap.documents.map { try $0.data(as: AppUser.self) }
    }

    func review(uid: String, role: Role, approved: Bool, trades: [String]) async throws {
        try await db.collection("users").document(uid).updateData([
            "role": role.rawValue,
            "approved": approved,
            "trades": trades
        ])
    }

    // MARK: Helpers

    private func packagesRef(_ projectID: String) -> CollectionReference {
        db.collection("projects").document(projectID).collection("packages")
    }

    /// Calls a Firebase callable Cloud Function over HTTPS, signed in as the current user.
    private func callFunction<T: Decodable>(_ name: String, _ data: [String: Any], timeout: TimeInterval = 60) async throws -> T {
        guard let user = Auth.auth().currentUser else { throw BackendError(message: "Sign in first.") }
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://us-central1-\(projectID).cloudfunctions.net/\(name)") else {
            throw BackendError(message: "Firebase isn’t set up in this build.")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])

        let (body, response) = try await URLSession.shared.data(for: request)
        let reply = try? JSONDecoder().decode(CallableReply<T>.self, from: body)
        if let result = reply?.result { return result }
        if let message = reply?.error?.message { throw BackendError(message: message) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw BackendError(message: status == 404
            ? "Bidding isn’t switched on yet. Deploy the Cloud Functions (see firebase/README.md)."
            : "The server couldn’t do that right now (error \(status)). Try again in a minute.")
    }
}

/// What a callable Cloud Function sends back: {"result": …} or {"error": {"message": …}}.
private struct CallableReply<T: Decodable>: Decodable {
    struct Failure: Decodable { var message: String }
    var result: T?
    var error: Failure?
}
#endif
