# Eliskopes (iOS)

SwiftUI app for live construction bidding, built the same way as HAINTEL (Backring Buyer). The home screen
shows one bid package of a project: its code, the current low bid and how far it is under budget, and
10 buttons that fit on one iPhone Pro screen. The arrows in the header step through the main contract
and each package. Each button pushes its own screen; Back returns home, and the bar at the bottom steps
to the previous or next button.

Bidding is a reverse auction. Everyone works from the established budget. The first bid is 1% under it,
and each later bid is exactly 1% under the current low, down to the owner's floor. The low bid when
bidding closes wins. Rivals appear only as anonymous IDs (like `B-7Q2`) until the close, when every name
is revealed.

## The 10 buttons
Same count as HAINTEL. All of them are free to read; nothing is sold in the app.

| # | Button | What it shows |
|---|---|---|
| 01 | Package | Scope, trade, who bids, close time; switch packages |
| 02 | Budget | Established budget, current low, owner's floor, progress toward the floor |
| 03 | Quantities | The takeoff, in the units suppliers use |
| 04 | Unit Costs | Price per unit at budget, current low and next bid; worked-out facts; a "check your number" calculator |
| 05 | Plans & Specs | Drawings and specifications |
| 06 | Schedule | Start, milestones, payment terms |
| 07 | Approvals | What's pre-approved before bidding (shop drawings, mix designs, permits) |
| 08 | Q&A | Bidders ask without their name; Eliskopes answers for everyone |
| 09 | Bid History | Every bid by anonymous ID, newest first |
| 10 | Place Bid | The live bid desk: current low, next bid, countdown, Bid button |

## Open and run
1. On a Mac with Xcode 16 or later, open `Eliskopes.xcodeproj`, pick an iPhone 16 Pro simulator, press Run.
2. To run on a phone, set your Team under Signing & Capabilities.

Requires iOS 17. Files are picked up automatically from the `Eliskopes/` folder.

Until `Eliskopes/GoogleService-Info.plist` is added, the app runs in **demo mode** on the sample project
from eliskopes.com (4-Story Office Building, Houston). The account button switches between sample
accounts: a general contractor, a concrete sub, two suppliers, an account waiting for review, the owner
and staff. In demo mode rival bidders sometimes answer your bid within seconds.

## Where things live
- `Models.swift`: projects, packages, bids, questions, roles, trades, the 10 buttons, and `Money.nextBid`
  (the 1% rule, in cents, identical to the server's).
- `Store.swift`: `ProjectStore`, app state. Live package updates, outbid and award notices, who may bid.
- `Backend/ProjectBackend.swift`: what the app reads and writes, and `SampleBackend` (demo mode).
- `Backend/FirebaseBackend.swift`: the same through Firebase, with live listeners.
- `SampleData.swift`: the demo project. The same project loads into Firebase from `firebase/project-template.json`.
- `Push.swift`: "You've been outbid" and award notifications.
- `Theme.swift`: eliskopes.com colors (navy #0B1730, amber #F2B544) and shared components.
- `Views/ProjectView.swift`: package header and the 2×5 button grid.
- `Views/FieldContent.swift`: buttons 01 to 09. `Views/BidDesk.swift`: button 10 and its confirm step.
- `Views/AccountView.swift`: sign in and sign up. `Views/PeopleSheet.swift`: staff approve bidders and trades.
- `Views/StaffSheets.swift`: staff add, edit and delete projects, packages, plan PDFs and people.

## Accounts and roles
People sign up as a **general contractor**, **turnkey subcontractor**, **vendor / supplier**, **project owner**
or **Eliskopes staff** (staff needs the staff code). Every bidder is reviewed by staff and approved for
specific trades (main contract, rebar, post-tensioning, concrete, supports & chairs, dirt haul-off,
miscellaneous) before they can bid or ask questions. Owners watch; they don't bid.

## Server and builds
- Firebase: `firebase/` (setup in `firebase/README.md`). Bids go through the `placeBid` Cloud Function, never
  straight from the phone, so the 1% rule, the deadline and trade approval can't be skipped.
- GitHub Actions: every push to main runs the Firebase tests and a compile check.
- Codemagic: `codemagic.yaml` builds and uploads to TestFlight.
- Everything to set up once, and where it lives: `ELISKOPES-INFO.md`.
