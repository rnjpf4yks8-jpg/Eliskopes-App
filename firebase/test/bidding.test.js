// End-to-end bidding against the Firebase emulators: the real placeBid handler, real Firestore
// transactions, real accounts, and admin.js. Run with `npm test` in this folder (starts the emulators,
// runs, stops them). placeBid runs in this process through firebase-functions' run(), the same code the
// deployed function runs.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const PROJECT = 'demo-eliskopes';
process.env.GCLOUD_PROJECT = PROJECT;
// The functions' own copy of firebase-admin, so the handlers below share its app.
const admin = require('../functions/node_modules/firebase-admin');
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const { nextBid } = require('../functions/rules');
const { placeBid, awardDue } = require('../functions/bids');

const P = 'office-houston';

function adminCli(...args) {
  return execFileSync('node', [path.join(__dirname, '..', 'admin.js'), ...args], { env: process.env, encoding: 'utf8' });
}

/** Creates an account in the Auth emulator, sets its profile with admin.js, and returns its uid. */
async function account(email, role, company, trades) {
  const user = await admin.auth().createUser({ email, password: 'secret123' });
  // What the app writes at sign-up, before staff review.
  await db.doc(`users/${user.uid}`).set({ uid: user.uid, name: company.split(' ')[0], company, role, email, trades: [], approved: false });
  adminCli('set-role', email, role, company.split(' ')[0], company);
  if (trades) adminCli('approve', email, trades);
  return user.uid;
}

/** Calls placeBid the way the app does and returns {result} or {error: {code, message}}. */
async function bid(uid, packageId, amount) {
  try {
    return { result: await placeBid.run({ auth: { uid }, data: { projectId: P, packageId, amount } }) };
  } catch (error) {
    return { error: { code: error.code, message: error.message } };
  }
}

const pkgRef = id => db.doc(`projects/${P}/packages/${id}`);
const pkg = async id => (await pkgRef(id).get()).data();

let gulf, bayou, coastal, ironline, metro, lonestar;

test.before(async () => {
  console.log(adminCli('load-project', path.join(__dirname, '..', 'project-template.json')).trim());
  // The template's November close may be in the past when this runs: keep bidding open.
  adminCli('set-close', P, new Date(Date.now() + 7 * 864e5).toISOString());
  gulf = await account('gulf@example.com', 'sub', 'Gulf Coast Concrete', 'concrete,haul,misc');
  bayou = await account('bayou@example.com', 'sub', 'Bayou Paving', 'concrete');
  coastal = await account('coastal@example.com', 'sub', 'Coastal Concrete', 'concrete');
  ironline = await account('ironline@example.com', 'supplier', 'Ironline Rebar', 'rebar,chairs');
  lonestar = await account('lonestar@example.com', 'gc', 'Lone Star Builders', 'main');
  metro = await account('metro@example.com', 'sub', 'Metro Formwork', null);
});

test('the project loads with every package and its catalog', async () => {
  const packages = await db.collection(`projects/${P}/packages`).orderBy('order').get();
  assert.deepEqual(packages.docs.map(d => d.id), ['main', 'rebar', 'pt', 'concrete', 'chairs', 'haul', 'misc']);
  const concrete = packages.docs[3].data();
  assert.equal(concrete.budget, 104_000_000);
  assert.equal(concrete.floor, 88_400_000);
  assert.equal(concrete.bidCount, 0);
  const main = packages.docs[0].data();
  const rebar = packages.docs[1].data();
  assert.equal(main.closesAt.toMillis() - rebar.closesAt.toMillis(), 3 * 3600e3, 'suppliers close 3 hours early');
  const questions = await pkgRef('concrete').collection('questions').get();
  assert.equal(questions.size, 2);
});

test('an account waiting for review cannot bid', async () => {
  const r = await bid(metro, 'concrete', nextBid(104_000_000));
  assert.match(r.error.message, /waiting for approval/);
});

test('a bidder cannot bid outside their approved trades', async () => {
  const r = await bid(ironline, 'concrete', nextBid(104_000_000));
  assert.match(r.error.message, /isn’t approved to bid on Concrete/);
});

test('first bid is 1% under budget and gets an anonymous ID', async () => {
  const r = await bid(gulf, 'concrete', 102_960_000);
  assert.equal(r.result.amount, 102_960_000);
  assert.match(r.result.bidder, /^B-[0-9A-HJ-NP-Z]{3}$/);
  const p = await pkg('concrete');
  assert.equal(p.lowBid, 102_960_000);
  assert.equal(p.lowBidder, r.result.bidder);
  assert.equal(p.bidCount, 1);
  const mine = await db.doc(`projects/${P}/bidders/${gulf}`).get();
  assert.equal(mine.get('id'), r.result.bidder);
});

test('you cannot undercut your own low bid', async () => {
  const r = await bid(gulf, 'concrete', nextBid(102_960_000));
  assert.match(r.error.message, /already hold the low bid/);
});

test('a stale price is refused with the new next bid', async () => {
  const r = await bid(bayou, 'concrete', 102_960_000);
  assert.equal(r.error.code, 'aborted');
  assert.match(r.error.message, /next bid is now \$1,019,304\.00/);
});

test('two bidders at the same instant: exactly one wins the price', async () => {
  const price = nextBid(102_960_000);
  const [a, b] = await Promise.all([bid(bayou, 'concrete', price), bid(coastal, 'concrete', price)]);
  const ok = [a, b].filter(r => r.result);
  const refused = [a, b].filter(r => r.error);
  assert.equal(ok.length, 1, JSON.stringify([a, b]));
  assert.equal(refused.length, 1);
  const p = await pkg('concrete');
  assert.equal(p.lowBid, price);
  assert.equal(p.bidCount, 2);
  const bids = await pkgRef('concrete').collection('bids').orderBy('at').get();
  assert.deepEqual(bids.docs.map(d => d.get('amount')), [102_960_000, price]);
  assert.equal(new Set(bids.docs.map(d => d.get('bidder'))).size, 2, 'different anonymous IDs');
});

test('a bid in the last 5 minutes adds 5 minutes to the clock', async () => {
  const soon = Date.now() + 2 * 60e3;
  await pkgRef('main').update({ closesAt: admin.firestore.Timestamp.fromMillis(soon) });
  const r = await bid(lonestar, 'main', nextBid(620_000_000));
  assert.equal(r.result.amount, 613_800_000);
  const p = await pkg('main');
  assert.equal(p.closesAt.toMillis(), soon + 5 * 60e3);
});

test('bidding stops at the owner’s floor', async () => {
  await pkgRef('haul').update({ lowBid: 4_430_000, lowBidder: 'B-ZZZ', bidCount: 9 });
  const r = await bid(gulf, 'haul', nextBid(4_430_000));
  assert.match(r.error.message, /reached the owner’s floor/);
});

test('a closed package refuses bids, then is awarded and its bidders named', async () => {
  await pkgRef('concrete').update({ closesAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
  const late = await bid(gulf, 'concrete', nextBid((await pkg('concrete')).lowBid));
  assert.match(late.error.message, /has closed/);

  const count = await awardDue(db, Date.now());
  assert.ok(count >= 1);
  const p = await pkg('concrete');
  assert.equal(p.awarded, true);
  assert.ok(['Bayou Paving', 'Coastal Concrete'].includes(p.winner), p.winner);
  const names = (await pkgRef('concrete').collection('reveal').doc('names').get()).data();
  assert.equal(Object.keys(names).length, 2);
  assert.ok(Object.values(names).includes('Gulf Coast Concrete'));
  const project = (await db.doc(`projects/${P}`).get()).data();
  assert.equal(project.status, 'open', 'other packages are still bidding');
});

test('re-loading the project keeps the bids', async () => {
  adminCli('load-project', path.join(__dirname, '..', 'project-template.json'));
  const p = await pkg('concrete');
  assert.equal(p.bidCount, 2);
  assert.equal(p.awarded, true);
});
