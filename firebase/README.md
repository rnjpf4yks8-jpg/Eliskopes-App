# Eliskopes on Firebase

Until these steps are done the app runs in demo mode on the sample project.

## One-time setup (about 30 minutes)
1. Firebase project: **eliskopes**, project ID `eliskopes-2fac8` (already in `.firebaserc`).
   Console: https://console.firebase.google.com/project/eliskopes-2fac8
2. **Upgrade to the Blaze (pay as you go) plan.** Cloud Functions need it. At this size it costs cents a month.
3. **Add an iOS app** with bundle ID `com.example.eliskopes` (or your own; change it in Xcode to match).
   Done: `Eliskopes/GoogleService-Info.plist` is in the repo, so builds use Firebase, not demo data.
4. **Authentication** → Sign-in method → turn on **Email/Password**.
5. **Firestore Database** → Create database (production mode).
6. **Push notifications** (outbid and award alerts): in the Apple Developer site make an APNs key
   (Keys → + → Apple Push Notifications service; Environment: Sandbox & Production; Key restriction:
   Team Scoped). In Firebase: Project settings → Cloud Messaging →
   Apple app configuration → upload that .p8 key with its Key ID and your Team ID (8P44VXJJ7X).
7. With the Firebase CLI (`npm install -g firebase-tools`, then `firebase login`), from this folder:
   ```
   cd functions && npm install && cd ..
   firebase functions:secrets:set STAFF_CODE        # at least 6 characters, keep it private
   firebase deploy --only functions,firestore:rules,storage
   ```
   **Storage** must be switched on once (console → Storage → Get started) for plan PDFs.
8. **Permissions for the functions** (new Google Cloud projects no longer grant these automatically).
   Open https://console.cloud.google.com/iam-admin/iam?project=eliskopes-2fac8, find the principal
   `430655934585-compute@developer.gserviceaccount.com`, click its pencil, and make sure it has:
   **Cloud Build Service Account**, **Cloud Datastore User**, **Firebase Cloud Messaging API Admin**,
   **Cloud Run Invoker** and **Logs Writer**. Without these, deploys fail or every function answers
   "The server couldn’t … right now".
9. **Project settings → Service accounts → Generate new private key.** Keep that file private, never commit it.
   Then:
   ```
   npm install
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/that-key.json
   ```

## Staff tools in the app
Signed in as staff (Account → staff code), everything below works from the phone. It needs the
functions and rules from October 2026 deployed: `firebase deploy --only functions,firestore:rules,storage`.
- **Projects:** + on the projects list adds one (name, city, owner, round, close in Central Time). Press and
  hold a project to edit or delete it. Changing the close moves every package not yet awarded, like
  `set-close`. Deleting runs the `deleteProject` function: packages, bids, questions, bidder IDs and PDFs go.
- **Packages:** inside a project, + → Add package (code, name, trade, who bids, auction, scope, budget, floor,
  unit, takeoff, schedule) or Edit the one on screen; Delete package is at the bottom of Edit. Once a package
  has bids, its budget and floor are fixed, and the bid fields are never written from the app.
- **Plans & Specs:** Add PDF uploads a PDF (up to 50 MB) to the package, or to every package. Press and
  hold a document to replace or delete its PDF; tap a "Coming soon" document to attach its PDF.
- **People:** the People button (projects list, or inside a project) → Add a person makes an account with
  its role, approval and trades; they get an email to choose their password (it can land in junk mail).
  On a person: email the password link again, or Delete account (the `deleteAccount` function).

## Load a project
Copy `project-template.json`, change it for the real project, then:
```
node admin.js load-project my-project.json
```
- Budgets are whole dollars. `floorPercent` sets the owner's floor (default 85% of each budget); a package
  can set its own `"floor"` in dollars.
- `closesAt` is the main auction close, in Central Time with its offset (`2026-11-25T15:00:00-06:00`).
  Packages with `"auction": "supplier"` close 3 hours earlier.
- `trade` decides who may bid: bidders are approved for trades by name.
- Link each document's PDF with
  `node admin.js attach-doc <projectId> <packageId|all> "<document name>" <file.pdf>`. It uploads the file to
  Firebase Storage and saves a private link on the document; re-loading the project keeps the link.
  Anyone who can see the project in the app can open the link, so don't keep links in this public repo.
- `questions` with answers are posted once, when a package is first loaded (a ready-made FAQ).
- Loading the same file again updates the catalog and keeps every bid. Once a package has bids, its
  budget and floor no longer change.
- The project loaded last shows first in the app. `node admin.js feature <projectId>` changes that.
- `node admin.js set-close <projectId> "2026-12-23T15:00:00-06:00"` moves the deadline for packages not yet awarded.

## People
Everyone creates their own account in the app. New accounts start **unapproved**. Staff approve them in
the app (People button on a project, top right) or from here:
```
node admin.js approve estimating@gulfcoastconcrete.com concrete,haul,misc
node admin.js approve bids@lonestarbuilders.com main
node admin.js set-role richa@eliskopes.com staff "Richa" "Eliskopes"
```
Trades: `main`, `rebar`, `pt`, `concrete`, `chairs`, `haul`, `misc`, `steel` (structural steel supply), `erection`, `deck`, `studs`.

Anyone signed in can also become staff by entering the staff code on the Account screen. After 10 wrong
codes an account is locked out of that.

## How bidding works on the server
- **placeBid** (callable): checks, in one Firestore transaction, that the bidder is approved for the
  package's trade, bidding is open, the price is exactly 1% under the current low (in cents), it is above
  the floor, and the bidder doesn't already hold the low bid. A bid in the last 5 minutes adds 5 minutes to
  the close. Two bidders at the same instant can't both win: one gets "the low bid just changed".
  The previous low bidder gets a push notification.
- **awardClosedPackages** (every 5 minutes): marks closed packages awarded, records the winning company and
  writes every bidder's company name so the app can show them. Bidders get a push with the result.
- Anonymous IDs: `projects/{id}/bidders/{uid}` (readable only by that bidder and staff) and
  `projects/{id}/bidderIndex/{bidderId}` (staff only). `node admin.js bidders <projectId>` lists them.

## Who can see what (firestore.rules, storage.rules)
- Projects, packages, bid amounts (by anonymous ID), questions and answers, plan PDFs: everyone.
- Bidder identities: the bidder themselves and staff, until the award reveals them.
- Staff add and edit projects and packages (catalog fields only) and upload plan PDFs.
- Nothing about a bid, a low bid or an award can be written from a phone; only the Cloud Functions write them.
  Deleting a project, a package or an account also goes through Cloud Functions (`manage.js`).

## Tests
```
npm test --prefix functions      # the auction rules
npm test --prefix test           # bidding end to end and the security rules, in the Firebase emulators (needs Java)
```
GitHub Actions runs both on every push to main.
