// Security rules: what a phone may read and write directly. Run with `npm test` in this folder.
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection, getDocs, serverTimestamp, arrayUnion } = require('firebase/firestore');

let env;
const P = 'projects/p1';

test.before(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-eliskopes-rules',
    firestore: { host, port: Number(port), rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    const user = (uid, role, approved, trades) => setDoc(doc(db, `users/${uid}`), { uid, name: uid, company: uid, role, approved, trades });
    await user('sub', 'sub', true, ['concrete']);
    await user('pending', 'sub', false, []);
    await user('owner', 'owner', true, []);
    await user('staff', 'staff', true, []);
    await setDoc(doc(db, P), { name: 'Office', status: 'open' });
    await setDoc(doc(db, `${P}/packages/concrete`), { name: 'Concrete', lowBid: 100, bidCount: 1 });
    await setDoc(doc(db, `${P}/packages/concrete/bids/b1`), { bidder: 'B-111', amount: 100 });
    await setDoc(doc(db, `${P}/packages/concrete/questions/q1`), { text: 'Pumping?', askedAt: new Date() });
    await setDoc(doc(db, `${P}/bidders/sub`), { id: 'B-111', company: 'sub' });
    await setDoc(doc(db, `${P}/bidderIndex/B-111`), { uid: 'sub', company: 'sub' });
  });
});

test.after(async () => env.cleanup());

const as = uid => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

test('anyone reads projects, packages, bids and questions', async () => {
  await assertSucceeds(getDoc(doc(as(null), `${P}/packages/concrete`)));
  await assertSucceeds(getDocs(collection(as(null), `${P}/packages/concrete/bids`)));
  await assertSucceeds(getDocs(collection(as(null), `${P}/packages/concrete/questions`)));
});

test('no phone can write a bid, a low bid, an award or a project', async () => {
  await assertFails(addDoc(collection(as('sub'), `${P}/packages/concrete/bids`), { bidder: 'B-111', amount: 1 }));
  await assertFails(updateDoc(doc(as('sub'), `${P}/packages/concrete`), { lowBid: 1 }));
  await assertFails(updateDoc(doc(as('staff'), `${P}/packages/concrete`), { awarded: true }));
  await assertFails(setDoc(doc(as('staff'), `${P}/packages/concrete/reveal/names`), { 'B-111': 'x' }));
  await assertFails(updateDoc(doc(as('staff'), P), { status: 'awarded' }));
});

test('bidder IDs stay anonymous', async () => {
  await assertSucceeds(getDoc(doc(as('sub'), `${P}/bidders/sub`)));
  await assertFails(getDoc(doc(as('pending'), `${P}/bidders/sub`)));
  await assertFails(getDoc(doc(as('sub'), `${P}/bidderIndex/B-111`)));
  await assertSucceeds(getDoc(doc(as('staff'), `${P}/bidderIndex/B-111`)));
});

test('sign-up: your own profile, unapproved, no trades, never staff', async () => {
  const base = { uid: 'new1', name: 'N', company: 'New Co', role: 'sub', approved: false, trades: [] };
  await assertSucceeds(setDoc(doc(as('new1'), 'users/new1'), base));
  await assertFails(setDoc(doc(as('new2'), 'users/new2'), { ...base, uid: 'new2', approved: true }));
  await assertFails(setDoc(doc(as('new3'), 'users/new3'), { ...base, uid: 'new3', trades: ['concrete'] }));
  await assertFails(setDoc(doc(as('new4'), 'users/new4'), { ...base, uid: 'new4', role: 'staff' }));
  await assertFails(setDoc(doc(as('new5'), 'users/other'), { ...base, uid: 'other' }));
});

test('you edit your name, company and push tokens, not your role, approval or trades', async () => {
  await assertSucceeds(updateDoc(doc(as('pending'), 'users/pending'), { fcmTokens: arrayUnion('tok') }));
  await assertSucceeds(updateDoc(doc(as('pending'), 'users/pending'), { company: 'Metro Formwork LLC' }));
  await assertFails(updateDoc(doc(as('pending'), 'users/pending'), { approved: true }));
  await assertFails(updateDoc(doc(as('pending'), 'users/pending'), { trades: ['concrete'] }));
  await assertFails(updateDoc(doc(as('sub'), 'users/sub'), { role: 'staff' }));
  await assertFails(getDoc(doc(as('sub'), 'users/pending')));
});

test('staff approve accounts and list everyone', async () => {
  await assertSucceeds(getDocs(collection(as('staff'), 'users')));
  await assertFails(getDocs(collection(as('sub'), 'users')));
  await assertSucceeds(updateDoc(doc(as('staff'), 'users/pending'), { approved: true, trades: ['haul'] }));
});

test('approved bidders ask questions without a name; staff answer', async () => {
  const qs = db => collection(db, `${P}/packages/concrete/questions`);
  await assertSucceeds(addDoc(qs(as('sub')), { text: 'Winter protection?', askedAt: serverTimestamp() }));
  await assertFails(addDoc(qs(as('sub')), { text: 'Signed', askedAt: serverTimestamp(), askedBy: 'sub' }));
  await assertFails(addDoc(qs(as('sub')), { text: 'Backdated', askedAt: new Date(2020, 1, 1) }));
  await assertFails(addDoc(qs(as('owner')), { text: 'Owner?', askedAt: serverTimestamp() }));
  await assertFails(addDoc(qs(as(null)), { text: 'Anon?', askedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('sub'), `${P}/packages/concrete/questions/q1`), { answer: 'Yes' }));
  await assertSucceeds(updateDoc(doc(as('staff'), `${P}/packages/concrete/questions/q1`), { answer: 'Yes', answeredAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('staff'), `${P}/packages/concrete/questions/q1`), { text: 'Edited' }));
});

// What staff write when they add a project and a package in the app.
const newProject = { id: 'p2', name: 'Clinic', city: 'Austin', round: 'December round', owner: 'Owner Co',
  closesAt: new Date(Date.now() + 7 * 864e5), status: 'open' };
const newPackage = {
  id: 'concrete', order: 0, code: 'Pkg 1', name: 'Concrete', trade: 'concrete', bidderType: 'sub', auction: 'main',
  scope: 'Slabs on grade', budget: 100000000, floor: 85000000, primaryQty: 3160, primaryUnit: 'CY',
  quantities: [], showTotal: false, facts: [], documents: [],
  schedule: { start: '', duration: '', milestones: [], payment: '' }, approvals: [], approvedBidders: 0,
  closesAt: new Date(Date.now() + 7 * 864e5), bidCount: 0, awarded: false,
};

test('staff add and edit projects; status and deleting stay with the server', async () => {
  await assertFails(setDoc(doc(as('sub'), 'projects/p2'), newProject));
  await assertFails(setDoc(doc(as(null), 'projects/p2'), newProject));
  await assertFails(setDoc(doc(as('staff'), 'projects/p2'), { ...newProject, status: 'awarded' }));
  await assertFails(setDoc(doc(as('staff'), 'projects/p2'), { ...newProject, name: '' }));
  await assertSucceeds(setDoc(doc(as('staff'), 'projects/p2'), newProject));
  await assertSucceeds(updateDoc(doc(as('staff'), 'projects/p2'), { name: 'Clinic, phase 2', closesAt: new Date(Date.now() + 9 * 864e5) }));
  await assertFails(updateDoc(doc(as('staff'), 'projects/p2'), { status: 'awarded' }));
  await assertFails(updateDoc(doc(as('sub'), 'projects/p2'), { name: 'Mine' }));
  await assertFails(deleteDoc(doc(as('staff'), 'projects/p2')));
});

test('staff add packages with no bids and edit them, never the bid fields', async () => {
  const ref = db => doc(db, 'projects/p2/packages/concrete');
  await assertFails(setDoc(ref(as('sub')), newPackage));
  await assertFails(setDoc(ref(as('staff')), { ...newPackage, lowBid: 1 }));
  await assertFails(setDoc(ref(as('staff')), { ...newPackage, bidCount: 3 }));
  await assertFails(setDoc(ref(as('staff')), { ...newPackage, awarded: true }));
  await assertFails(setDoc(ref(as('staff')), { ...newPackage, floor: newPackage.budget + 1 }));
  await assertFails(setDoc(ref(as('staff')), { ...newPackage, bidderType: 'owner' }));
  await assertFails(setDoc(doc(as('staff'), 'projects/no-such-project/packages/concrete'), newPackage));
  await assertSucceeds(setDoc(ref(as('staff')), newPackage));
  await assertSucceeds(updateDoc(ref(as('staff')), {
    scope: 'Slabs and walls', budget: 110000000, floor: 93500000,
    documents: [{ name: 'Structural plans', detail: 'S-001 to S-501', url: 'https://example.com/plans.pdf' }],
  }));
  await assertFails(updateDoc(ref(as('staff')), { lowBid: 5, bidCount: 1 }));
  await assertFails(updateDoc(ref(as('staff')), { awarded: true, winner: 'Me' }));
  await assertFails(updateDoc(ref(as('sub')), { scope: 'Cheaper' }));
  await assertFails(deleteDoc(ref(as('staff'))));
});

test('once a package has bids, its budget and floor stay put', async () => {
  await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), 'projects/p2/packages/rebar'),
    { ...newPackage, id: 'rebar', trade: 'rebar', bidCount: 2, lowBid: 98010000, lowBidder: 'B-222' }));
  const ref = doc(as('staff'), 'projects/p2/packages/rebar');
  await assertFails(updateDoc(ref, { budget: 120000000 }));
  await assertFails(updateDoc(ref, { floor: 80000000 }));
  await assertSucceeds(updateDoc(ref, { scope: 'Rebar #4 to #8, tied' }));
});

test('staff feature a project; nobody else changes the app settings', async () => {
  await assertSucceeds(setDoc(doc(as('staff'), 'config/app'), { currentProject: 'p2' }, { merge: true }));
  await assertFails(setDoc(doc(as('sub'), 'config/app'), { currentProject: 'p1' }, { merge: true }));
  await assertFails(setDoc(doc(as(null), 'config/app'), { currentProject: 'p1' }, { merge: true }));
});
