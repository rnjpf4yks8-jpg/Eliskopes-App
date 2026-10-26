// Security rules: what a phone may read and write directly. Run with `npm test` in this folder.
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, addDoc, collection, getDocs, serverTimestamp, arrayUnion } = require('firebase/firestore');

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
