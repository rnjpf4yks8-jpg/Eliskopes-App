# Eliskopes app: where everything is

## The app
- App name: Eliskopes (iPhone, iOS 17+)
- Bundle ID: com.example.eliskopes (change in Xcode, codemagic.yaml and Firebase together if you pick another)
- Apple team ID (App ID prefix): 8P44VXJJ7X, the same team as HAINTEL
- Capabilities: Push Notifications (for outbid and award alerts)
- Nothing is sold in the app, so there is no in-app purchase to set up

## Code
- GitHub repo: https://github.com/rnjpf4yks8-jpg/Eliskopes-App (branch: main)
- Every push to main runs the Firebase tests and a compile check on GitHub's cloud Mac (Actions tab)
- Clickable preview (no Xcode needed): the "Eliskopes App" artifact in Claude

## One-time setup, in order
1. **Apple Developer** (https://developer.apple.com/account/resources)
   - Identifiers → + → App IDs → App → Bundle ID `com.example.eliskopes`, and tick **Push Notifications**.
   - Keys → + → Apple Push Notifications service → download the .p8 (keep it private; Firebase needs it in step 3).
   - Profiles → + → App Store → pick `com.example.eliskopes` and the "HAINTEL" distribution certificate.
     Name it **Eliskopes**. Make the profile after Push Notifications is ticked, or the build fails.
2. **App Store Connect** (https://appstoreconnect.apple.com) → Apps → + → New App: name Eliskopes,
   bundle ID com.example.eliskopes, SKU ELISKOPES001.
3. **Firebase**: follow `firebase/README.md` (new project, the plist, sign-in, Firestore, the APNs key,
   deploy functions and rules, staff code).
4. **Codemagic** (https://codemagic.io) → Add application → GitHub → Eliskopes-App. It finds
   `codemagic.yaml` and its workflow "Eliskopes → TestFlight".
   - The App Store Connect key "HAINTEL ASC" is already in Codemagic and works for this app too.
   - Code signing identities: upload the **Eliskopes** provisioning profile (the HAINTEL certificate is already there).
   - Firebase config: commit `Eliskopes/GoogleService-Info.plist`, or add it base64-encoded as the secure
     variable `GOOGLE_SERVICE_INFO_PLIST`.
   - Start a build. It uploads to TestFlight; internal testers get it without beta review.

## Data (Firebase)
- Config file: Eliskopes/GoogleService-Info.plist (until it's there, the app runs the demo project)
- Load a project: `node admin.js load-project my-project.json` (start from firebase/project-template.json)
- Approve bidders: in the app (People button) or `node admin.js approve <email> <trades>`
- Staff code: the STAFF_CODE Firebase secret

## Who does what in the app
- General contractors, turnkey subs and suppliers: read everything free, ask questions, bid on approved trades
- Project owners: watch their project's bidding
- Eliskopes staff: approve accounts and trades, answer questions

## Keep private (never commit or share)
- Apple .p8 key files
- Firebase service account key (.json) used by admin.js
- The staff code
