import Foundation

// MARK: - Money

/// Every amount is kept in whole cents, the same as the server, so the app and the
/// placeBid Cloud Function always agree on the next bid to the cent.
enum Money {
    static let locale = Locale(identifier: "en_US")

    /// Each bid is 1% under the current low, rounded to the nearest cent (half a cent rounds up).
    static func nextBid(after cents: Int) -> Int {
        (cents * 99 + 50) / 100
    }

    static func text(_ cents: Int, showCents: Bool = true) -> String {
        let dollars = Decimal(cents) / 100
        // US formatting on every phone: these are US contracts, and amounts must read the same everywhere.
        return dollars.formatted(.currency(code: "USD").locale(Money.locale).precision(.fractionLength(showCents ? 2 : 0)))
    }

    /// "4.0%": how far `cents` is under `budget`.
    static func percentUnder(_ cents: Int, budget: Int) -> String {
        guard budget > 0 else { return "0.0%" }
        let share = Double(budget - cents) / Double(budget) * 100
        return String(format: "%.1f%%", share)
    }
}

// MARK: - People

/// What someone is on Eliskopes. Owners post projects; contractors, subs and suppliers bid;
/// staff run the platform. Every bidder is approved by staff, trade by trade, before they can bid.
enum Role: String, Codable, Hashable, CaseIterable {
    case owner, gc, sub, supplier, staff

    var label: String {
        switch self {
        case .owner: "Project owner"
        case .gc: "General contractor"
        case .sub: "Turnkey subcontractor"
        case .supplier: "Vendor / supplier"
        case .staff: "Eliskopes staff"
        }
    }

    var isBidder: Bool { self == .gc || self == .sub || self == .supplier }

    /// The roles people pick when they sign up, in order. Staff needs the staff code.
    static let signUpChoices: [Role] = [.gc, .sub, .supplier, .owner, .staff]

    /// What someone with this role can do, for the staff People screens.
    var abilities: String {
        switch self {
        case .owner: "Watches their project’s bidding. Owners don’t bid."
        case .gc, .sub, .supplier: "Bids on packages in the trades you approve, and asks questions."
        case .staff: "Runs Eliskopes: adds and deletes projects, packages, plans and people, approves bidders and answers questions."
        }
    }
}

struct AppUser: Codable, Hashable {
    var uid: String
    var name: String
    var company: String
    var role: Role
    var email: String? = nil
    /// Trades staff have approved this bidder for, e.g. ["concrete", "haul"]. Empty until reviewed.
    var trades: [String]? = nil
    /// Staff review every account before it can bid or ask questions.
    var approved: Bool? = nil

    var approvedTrades: [String] { trades ?? [] }
    var isApproved: Bool { approved ?? false }
}

/// The trades a package can be bid under. A bidder is approved for one or more of these.
struct Trade: Hashable {
    let key: String
    let label: String
}

enum Trades {
    static let all: [Trade] = [
        Trade(key: "main", label: "Main contract"),
        Trade(key: "rebar", label: "Rebar"),
        Trade(key: "pt", label: "Post-tensioning"),
        Trade(key: "concrete", label: "Concrete"),
        Trade(key: "chairs", label: "Supports & chairs"),
        Trade(key: "haul", label: "Dirt haul-off"),
        Trade(key: "misc", label: "Miscellaneous"),
        Trade(key: "steel", label: "Structural steel supply"),
        Trade(key: "erection", label: "Steel erection"),
        Trade(key: "deck", label: "Metal deck"),
        Trade(key: "studs", label: "Shear studs")
    ]

    static func label(_ key: String) -> String {
        all.first { $0.key == key }?.label ?? key.capitalized
    }
}

// MARK: - Projects and packages

/// One owner's project in a monthly bidding round. Its packages are bid separately.
struct Project: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var city: String
    /// "November round"
    var round: String
    var owner: String
    /// When the main auction closes. Supplier packages close 3 hours earlier.
    var closesAt: Date
    /// "open" while any package is still bidding, "awarded" once every package is.
    var status: String

    var isOpen: Bool { status == "open" }
}

/// Main auction or the vendor and supplier auction, which closes 3 hours before it.
enum Auction: String, Codable, Hashable {
    case main, supplier

    var label: String { self == .main ? "Main auction" : "Supplier auction" }
}

struct QuantityLine: Codable, Hashable {
    var item: String
    var qty: Double
    var unit: String
}

/// A labeled value Eliskopes worked out for bidders, e.g. "Trucks at 10 CY" · "316".
struct Fact: Codable, Hashable {
    var label: String
    var value: String
}

struct ProjectDocument: Codable, Hashable {
    var name: String
    var detail: String
    /// A link to the PDF. Missing until staff attach one.
    var url: URL? = nil
}

struct Milestone: Codable, Hashable {
    var date: String
    var label: String
}

struct PackageSchedule: Codable, Hashable {
    var start: String
    var duration: String
    var milestones: [Milestone]
    var payment: String
}

/// Something approved before bidding opens: shop drawings, mix designs, permits.
struct ApprovalItem: Codable, Hashable {
    var name: String
    /// true when it's done ("Pre-approved", "Checked"); false when it happens later ("At award").
    var ready: Bool
    var status: String
    var note: String
}

/// One bid package on a project. Staff load the catalog fields from a project file
/// (firebase/project-template.json); the bid fields are written only by the placeBid Cloud Function.
struct Package: Codable, Hashable, Identifiable {
    var id: String
    var order: Int
    /// "Main", "Pkg 1"…
    var code: String
    var name: String
    /// Trade key a bidder must be approved for, see `Trades`.
    var trade: String
    /// Who bids on it: general contractors, turnkey subs or vendors and suppliers.
    var bidderType: Role
    var auction: Auction
    var scope: String
    /// The established budget, in cents. The first bid is 1% under it.
    var budget: Int
    /// The owner's floor (ground rate), in cents. Bidding stops here.
    var floor: Int
    var primaryQty: Double
    var primaryUnit: String
    var quantities: [QuantityLine]
    /// Show a total row under the takeoff (when every line is in the primary unit).
    var showTotal: Bool
    var facts: [Fact]
    var documents: [ProjectDocument]
    var schedule: PackageSchedule
    var approvals: [ApprovalItem]
    var approvedBidders: Int

    // Written by the placeBid and awardClosedPackages Cloud Functions.
    var closesAt: Date
    var lowBid: Int? = nil
    /// The current low bidder's anonymous ID, e.g. "B-7Q2".
    var lowBidder: String? = nil
    var bidCount: Int? = nil
    var awarded: Bool? = nil
    /// The winning company, filled in when bidding closes.
    var winner: String? = nil

    var bids: Int { bidCount ?? 0 }
    var isAwarded: Bool { awarded ?? false }
    /// The current low, or the budget before anyone bids.
    var current: Int { lowBid ?? budget }
    var nextBid: Int { Money.nextBid(after: current) }
    var reachedFloor: Bool { nextBid < floor }

    func isClosed(at now: Date = .now) -> Bool { isAwarded || now >= closesAt }

    /// Price per primary unit for an amount in cents, e.g. "$329.11 / CY".
    func unitRate(_ cents: Int) -> String {
        guard primaryQty > 0 else { return "–" }
        let perUnit = Int((Double(cents) / primaryQty).rounded())
        return "\(Money.text(perUnit)) / \(primaryUnit)"
    }
}

extension Package {
    /// Supplier packages close this long before the main auction (as admin.js and the server do).
    static let supplierLead: TimeInterval = 3 * 60 * 60

    /// When a package closes: the project's main close, or 3 hours earlier in the supplier auction.
    static func close(for auction: Auction, projectClose: Date) -> Date {
        auction == .supplier ? projectClose.addingTimeInterval(-supplierLead) : projectClose
    }

    /// A new package for staff to fill in: no bids, nothing listed yet.
    static func blank(id: String, order: Int, projectClose: Date) -> Package {
        Package(id: id, order: order, code: order == 0 ? "Main" : "Pkg \(order)", name: "", trade: "main",
                bidderType: .gc, auction: .main, scope: "", budget: 0, floor: 0, primaryQty: 0, primaryUnit: "LS",
                quantities: [], showTotal: false, facts: [], documents: [],
                schedule: PackageSchedule(start: "", duration: "", milestones: [], payment: ""),
                approvals: [], approvedBidders: 0, closesAt: projectClose, bidCount: 0, awarded: false)
    }

    /// Bidding has started. Its budget and floor are then fixed (the security rules enforce it too).
    var hasBids: Bool { bids > 0 || lowBid != nil }
}

enum Slug {
    /// "Dirt haul-off" → "dirt-haul-off". `-2`, `-3`… are added if it's taken.
    static func make(_ text: String, taken: Set<String>, fallback: String) -> String {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let base = words.isEmpty ? fallback : String(words.joined(separator: "-").prefix(60))
        var id = base
        var n = 2
        while taken.contains(id) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }
}

/// One bid in a package's history. Bidders appear only by anonymous ID until the award.
struct Bid: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var bidder: String
    var amount: Int
    var at: Date

    // id is the Firestore document ID, set after decoding; it isn't a stored field.
    enum CodingKeys: String, CodingKey { case bidder, amount, at }
}

/// A bidder's question on a package. Posted without the asker's name; every answer goes to all bidders.
struct Question: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var text: String
    var askedAt: Date
    var answer: String? = nil
    var answeredAt: Date? = nil

    var isAnswered: Bool { !(answer ?? "").isEmpty }

    enum CodingKeys: String, CodingKey { case text, askedAt, answer, answeredAt }
}

/// What placeBid returns.
struct BidReceipt: Decodable, Hashable {
    var amount: Int
    var bidder: String
}

// MARK: - Navigation

enum Route: Hashable {
    case project(String)
    case field(PackageField)
}

/// The 10 buttons on a package screen: the same count as HAINTEL's 10 per hip.
/// Every one is free to read; Place Bid is the only one that does anything.
enum PackageField: Int, CaseIterable, Identifiable, Hashable {
    case package, budget, quantities, unitCosts, documents
    case schedule, approvals, questions, bidHistory, placeBid

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .package: "Package"
        case .budget: "Budget"
        case .quantities: "Quantities"
        case .unitCosts: "Unit Costs"
        case .documents: "Plans & Specs"
        case .schedule: "Schedule"
        case .approvals: "Approvals"
        case .questions: "Q&A"
        case .bidHistory: "Bid History"
        case .placeBid: "Place Bid"
        }
    }

    var symbol: String {
        switch self {
        case .package: "shippingbox"
        case .budget: "banknote"
        case .quantities: "ruler"
        case .unitCosts: "function"
        case .documents: "doc.text"
        case .schedule: "calendar"
        case .approvals: "checkmark.shield"
        case .questions: "bubble.left.and.text.bubble.right"
        case .bidHistory: "clock.arrow.circlepath"
        case .placeBid: "chart.line.downtrend.xyaxis"
        }
    }

    var previous: PackageField? { PackageField(rawValue: rawValue - 1) }
    var next: PackageField? { PackageField(rawValue: rawValue + 1) }
}

extension Double {
    /// 3,160 or 1.4: whole numbers without decimals.
    var quantityText: String {
        self == rounded()
            ? Int(self).formatted(.number.locale(Money.locale))
            : formatted(.number.locale(Money.locale).precision(.fractionLength(0...2)))
    }
}
