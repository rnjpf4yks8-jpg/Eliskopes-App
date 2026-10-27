#if canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
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

    /// Security rules let a person create only their own profile, unapproved. So the new sign-in is made on a
    /// second copy of Firebase that signs in as them (staff stay signed in here) and writes their unapproved
    /// profile as them; then staff set their role, approval and trades.
    func addPerson(_ person: AppUser, password: String?) async throws -> AppUser {
        let helper = try Self.helperApp()
        let helperAuth = Auth.auth(app: helper)
        let typed = (password ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let email = person.email ?? ""
        let result = try await helperAuth.createUser(withEmail: email,
                                                     password: typed.isEmpty ? "\(UUID().uuidString)-\(UUID().uuidString)" : typed)
        defer { try? helperAuth.signOut() }

        var added = person
        added.uid = result.user.uid
        let starter = AppUser(uid: added.uid, name: added.name, company: added.company,
                              role: added.role == .staff ? .owner : added.role, email: email, trades: [], approved: false)
        do {
            try await Firestore.firestore(app: helper).collection("users").document(added.uid)
                .setData(Firestore.Encoder().encode(starter))
        } catch {
            // Don't leave a sign-in with no profile behind.
            try? await result.user.delete()
            throw error
        }
        try await review(uid: added.uid, role: added.role, approved: added.isApproved, trades: added.approvedTrades)
        if typed.isEmpty { try await Auth.auth().sendPasswordReset(withEmail: email) }
        return added
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    /// The deleteAccount Cloud Function (firebase/functions/manage.js) also removes the sign-in.
    func deleteAccount(uid: String) async throws {
        struct Deleted: Decodable { var deleted: Bool }
        let _: Deleted = try await callFunction("deleteAccount", ["uid": uid])
    }

    /// The second Firebase app addPerson signs in on. Made once.
    private static func helperApp() throws -> FirebaseApp {
        let name = "addPerson"
        if let app = FirebaseApp.app(name: name) { return app }
        guard let options = FirebaseApp.app()?.options else {
            throw BackendError(message: "Firebase isn’t set up in this build.")
        }
        FirebaseApp.configure(name: name, options: options)
        guard let app = FirebaseApp.app(name: name) else {
            throw BackendError(message: "Couldn’t get ready to add people. Try again.")
        }
        return app
    }

    // MARK: Projects, packages and plans (staff)

    func save(project: Project, isNew: Bool) async throws {
        let ref = db.collection("projects").document(project.id)
        if isNew {
            var open = project
            open.status = "open"
            try await ref.setData(Firestore.Encoder().encode(open))
            return
        }
        let before = try await ref.getDocument().get("closesAt") as? Timestamp
        try await ref.updateData([
            "name": project.name, "city": project.city, "round": project.round, "owner": project.owner,
            "closesAt": Timestamp(date: project.closesAt),
        ])
        // A new close moves every package not yet awarded (suppliers 3 hours earlier), like admin.js set-close.
        guard before?.dateValue() != project.closesAt else { return }
        let packages = try await packagesRef(project.id).getDocuments().documents
        for doc in packages where doc.get("awarded") as? Bool != true {
            let auction = Auction(rawValue: doc.get("auction") as? String ?? "") ?? .main
            try await doc.reference.updateData([
                "closesAt": Timestamp(date: Package.close(for: auction, projectClose: project.closesAt)),
            ])
        }
    }

    func setFeaturedProject(_ projectID: String) async throws {
        try await db.collection("config").document("app").setData(["currentProject": projectID], merge: true)
    }

    /// The deleteProject Cloud Function removes everything under the project, which the rules don't let the app do.
    func deleteProject(_ projectID: String) async throws {
        struct Deleted: Decodable { var deleted: Bool }
        let _: Deleted = try await callFunction("deleteProject", ["projectId": projectID], timeout: 120)
    }

    /// A new package is written whole, with no bids. An existing one gets only its catalog fields, so a bid
    /// placed while staff were editing is never overwritten.
    func save(package: Package, projectID: String, isNew: Bool, moveClose: Bool) async throws {
        let ref = packagesRef(projectID).document(package.id)
        var fields = try Firestore.Encoder().encode(package)
        if isNew {
            fields["bidCount"] = 0
            fields["awarded"] = false
            try await ref.setData(fields)
            return
        }
        var catalog = Set(["order", "code", "name", "trade", "bidderType", "auction", "scope", "budget", "floor",
                           "primaryQty", "primaryUnit", "quantities", "showTotal", "facts", "documents", "schedule",
                           "approvals", "approvedBidders"])
        if moveClose { catalog.insert("closesAt") }
        fields = fields.filter { catalog.contains($0.key) }
        try await ref.updateData(fields)
    }

    func deletePackage(projectID: String, packageID: String) async throws {
        struct Deleted: Decodable { var deleted: Bool }
        let _: Deleted = try await callFunction("deletePackage", ["projectId": projectID, "packageId": packageID])
    }

    /// Saved under projects/{id}/documents/ with a random prefix, so two files with the same name never clash.
    func uploadDocument(_ data: Data, fileName: String, projectID: String) async throws -> URL {
        let safeName = fileName.replacingOccurrences(of: "/", with: "-")
        let ref = Storage.storage().reference(withPath: "projects/\(projectID)/documents/\(UUID().uuidString.prefix(8))-\(safeName)")
        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return try await ref.downloadURL()
    }

    func saveDocuments(_ documents: [ProjectDocument], projectID: String, packageID: String) async throws {
        let encoded = try documents.map { try Firestore.Encoder().encode($0) }
        try await packagesRef(projectID).document(packageID).updateData(["documents": encoded])
    }

    /// Only PDFs in this app's own Storage are deleted; a link to another website just comes off the list.
    func deleteDocumentFile(_ url: URL) async throws {
        let storage = Storage.storage()
        guard url.host() == "firebasestorage.googleapis.com",
              let path = Self.storagePath(url, bucket: storage.reference().bucket) else { return }
        do {
            try await storage.reference(withPath: path).delete()
        } catch let error as NSError where error.domain == StorageErrorDomain
                    && error.code == StorageErrorCode.objectNotFound.rawValue {
            // Already gone.
        }
    }

    /// "projects/p1/documents/plans.pdf" from a download link like
    /// https://firebasestorage.googleapis.com/v0/b/{bucket}/o/projects%2Fp1%2Fdocuments%2Fplans.pdf?alt=media&token=…
    /// (Storage's own reference(forURL:) stops the app on a link from another bucket, so it isn't used.)
    private static func storagePath(_ url: URL, bucket: String) -> String? {
        let decoded = url.path(percentEncoded: false)
        guard let marker = decoded.range(of: "/b/\(bucket)/o/") else { return nil }
        let path = String(decoded[marker.upperBound...])
        return path.isEmpty ? nil : path
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
        if let message = reply?.error?.message {
            // An unexpected crash on the server comes back as just "INTERNAL".
            throw BackendError(message: message == "INTERNAL"
                ? "The server couldn’t do that right now. Try again in a minute; if it keeps happening, tell Eliskopes."
                : message)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw BackendError(message: status == 404
            ? (name == "placeBid"
                ? "Bidding isn’t switched on yet. Deploy the Cloud Functions (see firebase/README.md)."
                : "This isn’t switched on yet. Deploy the Cloud Functions (firebase deploy, see firebase/README.md).")
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
