import Foundation

/// The example project from eliskopes.com: a 4-story office building in Houston with a main contract and
/// six packages. Budgets match the website; quantities, schedule and Q&A are sample data.
/// The same project loads into Firebase from firebase/project-template.json.
enum SampleData {
    /// Bidding closes about a month from launch, at 3:00 PM Central, so the demo is always live.
    static let mainClose: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let day = calendar.date(byAdding: .day, value: 30, to: .now) ?? .now
        return calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day) ?? day
    }()
    static let supplierClose = mainClose.addingTimeInterval(-3 * 3600)

    static let project = Project(
        id: "office-houston", name: "4-Story Office Building", city: "Houston, TX",
        round: "Monthly round", owner: "Bayou Office Partners", closesAt: mainClose, status: "open")

    static let people: [AppUser] = [
        AppUser(uid: "lsb", name: "R. Alvarez", company: "Lone Star Builders", role: .gc,
                email: "bids@lonestarbuilders.example", trades: ["main"], approved: true),
        AppUser(uid: "gcc", name: "D. Price", company: "Gulf Coast Concrete", role: .sub,
                email: "estimating@gulfcoastconcrete.example", trades: ["concrete", "haul", "misc"], approved: true),
        AppUser(uid: "ilr", name: "M. Chen", company: "Ironline Rebar", role: .supplier,
                email: "quotes@ironlinerebar.example", trades: ["rebar", "chairs"], approved: true),
        AppUser(uid: "tsy", name: "K. Osei", company: "Tensile Systems", role: .supplier,
                email: "sales@tensilesystems.example", trades: ["pt", "chairs"], approved: true),
        AppUser(uid: "mfw", name: "J. Ruiz", company: "Metro Formwork", role: .sub,
                email: "office@metroformwork.example", trades: [], approved: false),
        AppUser(uid: "own", name: "S. Patel", company: "Bayou Office Partners", role: .owner,
                email: "owner@bayouoffice.example", trades: [], approved: true),
        AppUser(uid: "staff", name: "Richa", company: "Eliskopes", role: .staff,
                email: "richa@eliskopes.example", trades: [], approved: true)
    ]

    /// Each sample bidder's anonymous ID on the project.
    static let bidderIDs: [String: String] = ["lsb": "B-5XJ", "gcc": "B-8CW", "ilr": "B-3RN", "tsy": "B-6TP", "mfw": "B-2LD"]
    static let rivals = ["B-7Q2", "B-K19", "B-2MR", "B-H08", "B-T44", "B-C21", "B-9FA", "B-0PL", "B-D5K", "B-W70"]

    private static func milestones(_ pairs: [(String, String)]) -> [Milestone] {
        pairs.map { Milestone(date: $0.0, label: $0.1) }
    }

    private static func lines(_ rows: [(String, Double, String)]) -> [QuantityLine] {
        rows.map { QuantityLine(item: $0.0, qty: $0.1, unit: $0.2) }
    }

    private static func facts(_ pairs: [(String, String)]) -> [Fact] {
        pairs.map { Fact(label: $0.0, value: $0.1) }
    }

    private static func docs(_ pairs: [(String, String)]) -> [ProjectDocument] {
        pairs.map { ProjectDocument(name: $0.0, detail: $0.1) }
    }

    private static func approvals(_ rows: [(String, Bool, String, String)]) -> [ApprovalItem] {
        rows.map { ApprovalItem(name: $0.0, ready: $0.1, status: $0.2, note: $0.3) }
    }

    private static func package(
        _ id: String, order: Int, code: String, name: String, trade: String, bidder: Role, auction: Auction,
        budget dollars: Int, scope: String, primary: (Double, String), total: Bool,
        quantities: [(String, Double, String)], facts f: [(String, String)], docs d: [(String, String)],
        schedule: (String, String, [(String, String)], String), approvals a: [(String, Bool, String, String)],
        approvedBidders: Int
    ) -> Package {
        let budget = dollars * 100
        return Package(
            id: id, order: order, code: code, name: name, trade: trade, bidderType: bidder, auction: auction,
            scope: scope, budget: budget, floor: budget * 85 / 100,
            primaryQty: primary.0, primaryUnit: primary.1, quantities: lines(quantities), showTotal: total,
            facts: facts(f), documents: docs(d),
            schedule: PackageSchedule(start: schedule.0, duration: schedule.1, milestones: milestones(schedule.2), payment: schedule.3),
            approvals: approvals(a), approvedBidders: approvedBidders,
            closesAt: auction == .supplier ? supplierClose : mainClose)
    }

    private static let catalog: [Package] = [
        package("main", order: 0, code: "Main", name: "Main contract", trade: "main", bidder: .gc, auction: .main,
                budget: 6_200_000,
                scope: "Turnkey construction of a 4-story, 60,000 SF post-tensioned concrete office building, from site work through certificate of occupancy.",
                primary: (60_000, "SF"), total: false,
                quantities: [("Gross floor area", 60_000, "SF"), ("Levels above grade", 4, "EA"), ("Typical floor plate", 15_000, "SF"),
                             ("Site area", 1.4, "AC"), ("Surface parking", 120, "STALLS"), ("Passenger elevators", 2, "EA"), ("Height to roof", 62, "FT")],
                facts: [("Budget per level", "$1,550,000"), ("Parking ratio", "2.0 per 1,000 SF"), ("Average monthly draw", "$539,000 over 11.5 months")],
                docs: [("Architectural", "A-series · 48 sheets · Rev 2"), ("Structural", "S-series · 31 sheets · Rev 2"),
                       ("MEP", "M, E and P series · 36 sheets · Rev 1"), ("Civil", "C-series · 12 sheets · Rev 1"),
                       ("Specifications", "Divisions 01 to 33 · 412 pages"), ("Geotechnical report", "64 pages"),
                       ("Sample contract", "AIA A102 basis · 38 pages"), ("Construction schedule", "50 weeks · 214 activities"),
                       ("Project financing", "Lender commitment letter")],
                schedule: ("Jan 4, 2027", "50 weeks",
                           [("Jan 4", "Notice to proceed"), ("Feb 26", "Foundations complete"), ("Jun 18", "Structure topped out"),
                            ("Aug 13", "Building dried in"), ("Dec 17", "Substantial completion")],
                           "Monthly draws against the schedule of values. 10% retainage, reduced to 5% at 50% complete."),
                approvals: [("Code review", true, "Checked", "IBC 2021 with City of Houston amendments"),
                            ("Building permit", true, "Issued", "Oct 9, 2026"),
                            ("Deferred submittals", true, "Pre-approved", "Fire sprinkler, fire alarm, storefront"),
                            ("Schedule of values", true, "Ready", "Loaded at award"),
                            ("Utility will-serve letters", true, "On file", "Water, sewer, power")],
                approvedBidders: 7),
        package("rebar", order: 1, code: "Pkg 1", name: "Rebar", trade: "rebar", bidder: .supplier, auction: .supplier,
                budget: 612_000,
                scope: "Furnish, fabricate and deliver ASTM A615 Grade 60 reinforcing to site, tagged by placing drawing and pour.",
                primary: (380, "TON"), total: true,
                quantities: [("#3 bars", 22, "TON"), ("#4 bars", 64, "TON"), ("#5 bars", 78, "TON"), ("#6 bars", 46, "TON"),
                             ("#7 bars", 38, "TON"), ("#8 bars", 52, "TON"), ("#10 bars", 48, "TON"), ("#11 bars", 32, "TON")],
                facts: [("Total weight", "760,000 lb"), ("Truckloads at 22 tons", "18"), ("Reinforcing per CY of concrete", "240 lb")],
                docs: [("Structural", "S-series · 31 sheets · Rev 2"), ("Rebar placing drawings", "64 sheets · pre-approved"),
                       ("CNC bending schedules", "aSa and BVBS files"), ("Specification 03 21 00", "9 pages")],
                schedule: ("Jan 18, 2027", "20 weeks of deliveries",
                           [("Jan 18", "Piers and grade beams"), ("Mar 15", "Level 2 deck"), ("Apr 12", "Level 3 deck"),
                            ("May 10", "Level 4 deck"), ("Jun 7", "Roof deck")],
                           "Paid on delivery tickets, net 30."),
                approvals: [("Placing drawings", true, "Pre-approved", "Engineer of record stamped Oct 14, 2026"),
                            ("Bending schedules", true, "Pre-approved", "CNC files included"),
                            ("Code review", true, "Checked", "ACI 318-19"),
                            ("Mill certificates", false, "At delivery", "One set with each load")],
                approvedBidders: 4),
        package("pt", order: 2, code: "Pkg 2", name: "Post-tensioning", trade: "pt", bidder: .supplier, auction: .supplier,
                budget: 248_000,
                scope: "Furnish encapsulated unbonded tendons, anchorages and stressing for four elevated decks, per pre-approved PT shop drawings.",
                primary: (60_000, "SF"), total: false,
                quantities: [("Elevated PT deck area", 60_000, "SF"), ("0.5 in strand, 270 ksi", 54_000, "LB"),
                             ("Unbonded tendons", 1_180, "EA"), ("Anchorages", 2_360, "EA"), ("Stressing pours", 8, "EA")],
                facts: [("Strand per SF of deck", "0.90 lb"), ("Tendons per level", "295"), ("Average tendon length", "88 ft")],
                docs: [("PT shop drawings", "24 sheets · pre-approved"), ("Elongation calculations", "Per tendon, by pour"),
                       ("Structural", "S-series · 31 sheets · Rev 2"), ("Specification 03 38 00", "11 pages")],
                schedule: ("Mar 8, 2027", "14 weeks",
                           [("Mar 8", "Level 2 tendons on site"), ("Apr 5", "Level 3"), ("May 3", "Level 4"), ("May 31", "Roof"), ("Jun 11", "Final stressing")],
                           "Paid on delivery and stressing records, net 30."),
                approvals: [("PT shop drawings", true, "Pre-approved", "Engineer of record stamped Oct 14, 2026"),
                            ("Elongation calcs", true, "Pre-approved", "Included"),
                            ("Stressing record format", true, "Ready", "Template provided"),
                            ("Installer certification", false, "At award", "PTI Level 2 field supervisor")],
                approvedBidders: 3),
        package("concrete", order: 3, code: "Pkg 3", name: "Concrete", trade: "concrete", bidder: .sub, auction: .main,
                budget: 1_040_000,
                scope: "Furnish, place, finish and cure all structural concrete, pumping included. Pour sequence drawings are prepared and pre-approved.",
                primary: (3_160, "CY"), total: true,
                quantities: [("Drilled piers", 620, "CY"), ("Grade beams", 280, "CY"), ("Slab on grade, 5 in", 230, "CY"),
                             ("Elevated PT slabs, 8 in", 1_480, "CY"), ("Columns", 210, "CY"), ("Shear walls and cores", 340, "CY")],
                facts: [("Trucks at 10 CY", "316"), ("Finished slab area", "75,000 SF"), ("Planned pours", "26")],
                docs: [("Structural", "S-series · 31 sheets · Rev 2"), ("Pour sequence drawings", "14 sheets · pre-approved"),
                       ("Mix designs", "4,000, 5,000 and 6,000 psi"), ("Specification 03 30 00", "18 pages")],
                schedule: ("Jan 25, 2027", "21 weeks",
                           [("Jan 25", "Piers begin"), ("Feb 26", "Slab on grade"), ("Mar 22", "Level 2 deck"), ("May 17", "Roof deck"), ("Jun 18", "Topped out")],
                           "Monthly against the schedule of values. 10% retainage."),
                approvals: [("Mix designs", true, "Pre-approved", "Three mixes on file"),
                            ("Pour sequence", true, "Pre-approved", "14 sheets"),
                            ("Joint layout", true, "Pre-approved", "Sheets S-201 to S-204"),
                            ("Code review", true, "Checked", "ACI 301 and 318-19"),
                            ("Testing lab", true, "Owner hired", "Not in your price")],
                approvedBidders: 5),
        package("chairs", order: 4, code: "Pkg 4", name: "Supports & chairs", trade: "chairs", bidder: .supplier, auction: .supplier,
                budget: 10_400,
                scope: "Furnish bar supports, tendon chairs and spacers for all decks, slab on grade and piers.",
                primary: (60_000, "SF"), total: false,
                quantities: [("Supported deck area", 60_000, "SF"), ("Slab bolster upper, 3 in", 6_800, "LF"),
                             ("High chairs, 2-1/4 in", 4_200, "EA"), ("Tendon support chairs", 9_600, "EA"),
                             ("Concrete dobies, 3 in", 2_400, "EA"), ("Pier wheel spacers", 1_900, "EA")],
                facts: [("Pieces, not counting bolster", "18,100"), ("Tendon chairs per tendon", "8.1"), ("Deliveries", "5, one per level")],
                docs: [("Rebar placing drawings", "64 sheets · support layout shown"), ("PT shop drawings", "24 sheets · chair heights shown"),
                       ("Specification 03 21 00", "9 pages")],
                schedule: ("Jan 18, 2027", "20 weeks of deliveries",
                           [("Jan 18", "Piers and grade beams"), ("Mar 15", "Level 2"), ("Apr 12", "Level 3"), ("May 10", "Level 4"), ("Jun 7", "Roof")],
                           "Paid on delivery tickets, net 30."),
                approvals: [("Support layout", true, "Pre-approved", "On the placing drawings"),
                            ("Product data", true, "Pre-approved", "Plastic tipped in exposed areas")],
                approvedBidders: 3),
        package("haul", order: 5, code: "Pkg 5", name: "Dirt haul-off", trade: "haul", bidder: .sub, auction: .main,
                budget: 52_000,
                scope: "Load, haul and dispose of excavation spoils at an approved fill site 12 miles away, with a disposal ticket for every load.",
                primary: (3_250, "LCY"), total: false,
                quantities: [("Pier spoils", 1_050, "BCY"), ("Grade beam and pit excavation", 820, "BCY"), ("Site cut", 730, "BCY"),
                             ("Loose volume after 25% swell", 3_250, "LCY")],
                facts: [("Truckloads at 14 CY", "233"), ("Days at 25 loads a day", "10 working days"), ("One-way haul", "12 mi")],
                docs: [("Civil", "C-series · 12 sheets · Rev 1"), ("Geotechnical report", "64 pages · native clay, no contamination"),
                       ("Haul route plan", "1 sheet · pre-approved")],
                schedule: ("Jan 25, 2027", "6 weeks, as piers are drilled",
                           [("Jan 25", "Pier spoils begin"), ("Feb 12", "Grade beams and pits"), ("Mar 5", "Site cut complete")],
                           "Paid weekly on disposal tickets."),
                approvals: [("Haul route", true, "Pre-approved", "City of Houston"),
                            ("Soil classification", true, "Clean", "No contamination found"),
                            ("Ticket format", true, "Ready", "Template provided")],
                approvedBidders: 6),
        package("misc", order: 6, code: "Pkg 6", name: "Miscellaneous", trade: "misc", bidder: .sub, auction: .main,
                budget: 6_200,
                scope: "Furnish and set anchor bolts and embeds; furnish vapor retarder, joint filler and curing compound.",
                primary: (60_000, "SF"), total: false,
                quantities: [("Anchor bolts, 3/4 × 18 in", 96, "EA"), ("Embed plates", 64, "EA"), ("Vapor retarder, 15 mil", 16_500, "SF"),
                             ("Expansion joint filler, 1/2 in", 1_200, "LF"), ("Curing compound", 140, "GAL")],
                facts: [("Building area basis", "60,000 SF"), ("Vapor retarder rolls, 10 × 150 ft", "11"), ("Embeds per level", "16")],
                docs: [("Structural", "S-series · 31 sheets · Rev 2"), ("Embed schedule", "2 sheets · pre-approved"),
                       ("Specification 07 26 00", "4 pages")],
                schedule: ("Jan 25, 2027", "With concrete",
                           [("Jan 25", "Anchor bolts at piers"), ("Feb 22", "Vapor retarder at slab on grade"), ("Mar 22", "Embeds, level by level")],
                           "Paid on delivery, net 30."),
                approvals: [("Embed schedule", true, "Pre-approved", "2 sheets"),
                            ("Vapor retarder", true, "Pre-approved", "ASTM E1745 Class A")],
                approvedBidders: 4)
    ]

    /// Earlier bids per package: bidder IDs and how many hours ago. Each is 1% under the one before.
    private static let history: [String: [(String, Double)]] = [
        "main": [("B-7Q2", 104), ("B-K19", 79), ("B-7Q2", 60)],
        "rebar": [("B-2MR", 106), ("B-H08", 82), ("B-2MR", 29)],
        "pt": [("B-T44", 56)],
        "concrete": [("B-C21", 108), ("B-9FA", 102), ("B-C21", 59), ("B-0PL", 31)],
        "haul": [("B-D5K", 85), ("B-W70", 33)]
    ]

    static let bids: [String: [Bid]] = {
        var result: [String: [Bid]] = [:]
        for package in catalog {
            var amount = package.budget
            result[package.id] = (history[package.id] ?? []).map { bidder, hoursAgo in
                amount = Money.nextBid(after: amount)
                return Bid(bidder: bidder, amount: amount, at: Date.now.addingTimeInterval(-hoursAgo * 3600))
            }
        }
        return result
    }()

    static let packages: [Package] = catalog.map { package in
        var p = package
        if let last = bids[p.id]?.last {
            p.lowBid = last.amount
            p.lowBidder = last.bidder
            p.bidCount = bids[p.id]?.count
        }
        return p
    }

    static let questions: [String: [Question]] = {
        func q(_ text: String, _ answer: String, hoursAgo: Double) -> Question {
            let asked = Date.now.addingTimeInterval(-hoursAgo * 3600)
            return Question(text: text, askedAt: asked, answer: answer, answeredAt: asked.addingTimeInterval(3 * 3600))
        }
        return [
            "main": [q("Is the site survey current?", "Yes. The ALTA survey dated Aug 2026 is in the Civil set, sheet C-001.", hoursAgo: 100),
                     q("Who carries builder’s risk insurance?", "The owner. See the sample contract, section 11.3.", hoursAgo: 76),
                     q("Are there liquidated damages?", "Yes, $1,500 per calendar day after substantial completion. Sample contract, section 8.4.", hoursAgo: 50)],
            "rebar": [q("Any epoxy-coated bar?", "No. All black bar, ASTM A615 Grade 60.", hoursAgo: 98),
                      q("Where do we unload?", "East laydown area, 80 × 40 ft. See sheet C-101.", hoursAgo: 74)],
            "pt": [q("Is a fully encapsulated system required?", "Yes, per ACI 423.7, at every level.", hoursAgo: 52)],
            "concrete": [q("Is pumping in our price?", "Yes. Include all pumping.", hoursAgo: 80),
                         q("Who pays for cylinder testing?", "The owner hires the testing lab directly.", hoursAgo: 78)],
            "haul": [q("Is any of the spoil contaminated?", "No. The geotechnical report found clean native clay throughout.", hoursAgo: 54)]
        ]
    }()
}
