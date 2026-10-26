// Eliskopes admin tasks for staff. Needs a Firebase service account key:
//   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
//
//   node admin.js load-project <project.json>          add or update a project and its packages
//   node admin.js feature <projectId>                  show this project first in the app
//   node admin.js set-close <projectId> "<ISO time>"   move the main close (suppliers close 3 hours earlier)
//   node admin.js set-role <email> <owner|gc|sub|supplier|staff> ["Name"] ["Company"]
//   node admin.js approve <email> <trade,trade,...>    approve a bidder for trades, e.g. concrete,haul
//   node admin.js bidders <projectId>                  who is behind each anonymous bidder ID (staff only)
const fs = require('fs');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const { Timestamp } = admin.firestore;

const ROLES = ['owner', 'gc', 'sub', 'supplier', 'staff'];
const BIDDER_TYPES = ['gc', 'sub', 'supplier'];
const KNOWN_TRADES = ['main', 'rebar', 'pt', 'concrete', 'chairs', 'haul', 'misc'];
const SUPPLIER_LEAD_MS = 3 * 60 * 60 * 1000;
// Fields only the placeBid and awardClosedPackages functions write. Re-loading a project never touches them.
const BID_FIELDS = ['lowBid', 'lowBidder', 'bidCount', 'lastBidAt', 'awarded', 'winner', 'awardedAt'];

function closeFor(auction, mainCloseMs) {
  return Timestamp.fromMillis(auction === 'supplier' ? mainCloseMs - SUPPLIER_LEAD_MS : mainCloseMs);
}

async function loadProject(file) {
  if (!file) throw usage();
  const p = JSON.parse(fs.readFileSync(file, 'utf8'));
  for (const key of ['id', 'name', 'city', 'round', 'owner', 'closesAt', 'packages']) {
    if (p[key] === undefined) throw new Error(`The project file needs "${key}". See project-template.json.`);
  }
  const mainCloseMs = Date.parse(p.closesAt);
  if (Number.isNaN(mainCloseMs)) throw new Error(`closesAt "${p.closesAt}" isn't a date. Use the form 2026-11-25T15:00:00-06:00.`);
  const floorPercent = p.floorPercent ?? 85;

  const projectRef = db.collection('projects').doc(p.id);
  const existing = await projectRef.get();
  await projectRef.set({
    id: p.id, name: p.name, city: p.city, round: p.round, owner: p.owner,
    closesAt: Timestamp.fromMillis(mainCloseMs),
    status: existing.exists ? existing.get('status') : 'open',
  }, { merge: true });

  let added = 0, updated = 0;
  for (const [order, pkg] of p.packages.entries()) {
    for (const key of ['id', 'code', 'name', 'trade', 'bidderType', 'auction', 'budget', 'scope', 'primaryQty', 'primaryUnit']) {
      if (pkg[key] === undefined) throw new Error(`Package ${pkg.id || order + 1} needs "${key}".`);
    }
    if (!BIDDER_TYPES.includes(pkg.bidderType)) throw new Error(`Package ${pkg.id}: bidderType must be one of ${BIDDER_TYPES.join(', ')}.`);
    if (!['main', 'supplier'].includes(pkg.auction)) throw new Error(`Package ${pkg.id}: auction must be "main" or "supplier".`);
    if (!KNOWN_TRADES.includes(pkg.trade)) console.warn(`Package ${pkg.id}: trade "${pkg.trade}" is new; approve bidders for it by that name.`);

    const ref = projectRef.collection('packages').doc(pkg.id);
    const before = await ref.get();
    const budget = Math.round(pkg.budget * 100);
    const floor = Math.round((pkg.floor ?? pkg.budget * floorPercent / 100) * 100);
    const catalog = {
      id: pkg.id, order, code: pkg.code, name: pkg.name, trade: pkg.trade,
      bidderType: pkg.bidderType, auction: pkg.auction, scope: pkg.scope,
      budget, floor,
      primaryQty: pkg.primaryQty, primaryUnit: pkg.primaryUnit, showTotal: pkg.showTotal === true,
      quantities: pkg.quantities || [], facts: pkg.facts || [],
      documents: (pkg.documents || []).map(d => (d.url ? { name: d.name, detail: d.detail || '', url: d.url } : { name: d.name, detail: d.detail || '' })),
      schedule: pkg.schedule || { start: '', duration: '', milestones: [], payment: '' },
      approvals: pkg.approvals || [],
      approvedBidders: pkg.approvedBidders || 0,
    };

    if (!before.exists) {
      await ref.set({ ...catalog, closesAt: closeFor(pkg.auction, mainCloseMs), bidCount: 0, awarded: false });
      for (const q of pkg.questions || []) {
        const now = Timestamp.now();
        await ref.collection('questions').add(q.a ? { text: q.q, askedAt: now, answer: q.a, answeredAt: now } : { text: q.q, askedAt: now });
      }
      added++;
      continue;
    }

    const data = before.data();
    if ((data.bidCount || 0) > 0 && (data.budget !== budget || data.floor !== floor)) {
      console.warn(`Package ${pkg.id} already has bids, so its budget and floor stay at ${data.budget / 100} and ${data.floor / 100}.`);
      catalog.budget = data.budget;
      catalog.floor = data.floor;
    }
    for (const field of BID_FIELDS) delete catalog[field];
    if (data.awarded !== true) catalog.closesAt = closeFor(pkg.auction, mainCloseMs);
    await ref.set(catalog, { merge: true });
    updated++;
  }
  await db.collection('config').doc('app').set({ currentProject: p.id }, { merge: true });
  console.log(`Project ${p.id}: ${added} packages added, ${updated} updated. It shows first in the app.`);
}

async function feature(projectId) {
  if (!projectId) throw usage();
  if (!(await db.collection('projects').doc(projectId).get()).exists) throw new Error(`No project ${projectId}.`);
  await db.collection('config').doc('app').set({ currentProject: projectId }, { merge: true });
  console.log(`${projectId} now shows first in the app.`);
}

async function setClose(projectId, when) {
  const ms = Date.parse(when || '');
  if (!projectId || Number.isNaN(ms)) throw usage();
  const projectRef = db.collection('projects').doc(projectId);
  await projectRef.update({ closesAt: Timestamp.fromMillis(ms) });
  const packages = await projectRef.collection('packages').get();
  let moved = 0;
  for (const doc of packages.docs) {
    if (doc.get('awarded') === true) continue;
    await doc.ref.update({ closesAt: closeFor(doc.get('auction'), ms) });
    moved++;
  }
  console.log(`${moved} packages now close ${new Date(ms).toISOString()} (suppliers 3 hours earlier).`);
}

async function userByEmail(email) {
  const authUser = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!authUser) throw new Error(`No account for ${email}. They need to create one in the app first.`);
  return authUser;
}

async function setRole(email, role, name, company) {
  if (!email || !ROLES.includes(role)) throw usage();
  const authUser = await userByEmail(email);
  const ref = db.collection('users').doc(authUser.uid);
  const existing = await ref.get();
  const update = { uid: authUser.uid, email, role };
  if (name) update.name = name; else if (!existing.exists) update.name = authUser.displayName || email;
  if (company) update.company = company; else if (!existing.exists) update.company = '';
  if (!existing.exists) update.trades = [];
  if (role === 'staff' || role === 'owner') update.approved = true;
  else if (!existing.exists) update.approved = false;
  await ref.set(update, { merge: true });
  console.log(`${email} is now ${role}.${BIDDER_TYPES.includes(role) ? ' Approve their trades with: node admin.js approve ' + email + ' <trades>' : ''}`);
}

async function approve(email, tradeList) {
  if (!email || !tradeList) throw usage();
  const trades = tradeList.split(',').map(t => t.trim()).filter(Boolean);
  for (const t of trades) if (!KNOWN_TRADES.includes(t)) console.warn(`"${t}" isn't one of ${KNOWN_TRADES.join(', ')}. Using it anyway.`);
  const authUser = await userByEmail(email);
  const ref = db.collection('users').doc(authUser.uid);
  const snap = await ref.get();
  if (!snap.exists) throw new Error(`${email} hasn't finished creating their profile in the app.`);
  if (!BIDDER_TYPES.includes(snap.get('role'))) throw new Error(`${email} is ${snap.get('role')}, not a bidder. Use set-role first.`);
  await ref.update({ approved: true, trades });
  console.log(`${snap.get('company') || email} can now bid on: ${trades.join(', ')}.`);
}

async function bidders(projectId) {
  if (!projectId) throw usage();
  const index = await db.collection('projects').doc(projectId).collection('bidderIndex').get();
  if (index.empty) return console.log('No bids yet.');
  for (const doc of index.docs) console.log(`${doc.id}  ${doc.get('company')}`);
}

function usage() {
  return new Error('Usage: see the top of admin.js, or firebase/README.md.');
}

const [command, ...args] = process.argv.slice(2);
const commands = {
  'load-project': loadProject, feature, 'set-close': setClose, 'set-role': setRole, approve, bidders,
};
if (!commands[command]) {
  console.error(usage().message);
  process.exit(1);
}
commands[command](...args).then(() => process.exit(0), error => {
  console.error(error.message);
  process.exit(1);
});
