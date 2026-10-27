// Staff deleting projects, packages and accounts (functions/manage.js), against the Firebase emulators.
// Run with `npm test` in this folder. The handlers run in this process through firebase-functions' run().
const test = require('node:test');
const assert = require('node:assert/strict');

const PROJECT = 'demo-eliskopes';
process.env.GCLOUD_PROJECT = PROJECT;
// The functions' own copy of firebase-admin, so the handlers below share its app.
const admin = require('../functions/node_modules/firebase-admin');
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const { deleteProject, deletePackage, deleteAccount, storagePath } = require('../functions/manage');

const P = 'manage-test';
let staff, bidder;

async function call(fn, uid, data) {
  try {
    return { result: await fn.run({ auth: uid ? { uid } : undefined, data }) };
  } catch (error) {
    return { error: { code: error.code, message: error.message } };
  }
}

async function person(email, role) {
  const user = await admin.auth().createUser({ email, password: 'secret123' });
  await db.doc(`users/${user.uid}`).set({ uid: user.uid, name: role, company: `${role} Co`, role, email, trades: [], approved: true });
  return user.uid;
}

/** A fresh project with two packages, each with a bid and a question. */
async function seedProject() {
  const project = db.doc(`projects/${P}`);
  await db.recursiveDelete(project);
  await project.set({ id: P, name: 'Clinic', city: 'Austin', round: 'December round', owner: 'Owner Co', status: 'open',
    closesAt: admin.firestore.Timestamp.fromMillis(Date.now() + 864e5) });
  for (const id of ['concrete', 'rebar']) {
    const pkg = project.collection('packages').doc(id);
    await pkg.set({ id, name: id, budget: 100, floor: 85, bidCount: 1, lowBid: 99, lowBidder: 'B-111',
      documents: [{ name: 'Plans', detail: '', url: `https://firebasestorage.googleapis.com/v0/b/x/o/${encodeURIComponent(`projects/${P}/documents/plans.pdf`)}?alt=media&token=t` }] });
    await pkg.collection('bids').add({ bidder: 'B-111', amount: 99, at: admin.firestore.Timestamp.now() });
    await pkg.collection('questions').add({ text: 'Pumping?', askedAt: admin.firestore.Timestamp.now() });
  }
  await project.collection('bidders').doc('someone').set({ id: 'B-111', company: 'Sub Co' });
  await project.collection('bidderIndex').doc('B-111').set({ uid: 'someone', company: 'Sub Co' });
  await db.doc('config/app').set({ currentProject: P }, { merge: true });
}

test.before(async () => {
  staff = await person('staff.manage@example.com', 'staff');
  bidder = await person('sub.manage@example.com', 'sub');
});

test('reads the Storage path out of a download link', () => {
  assert.equal(storagePath('https://firebasestorage.googleapis.com/v0/b/b/o/projects%2Fp1%2Fdocuments%2Fa%20b.pdf?alt=media&token=x'),
    'projects/p1/documents/a b.pdf');
  assert.equal(storagePath('https://example.com/plans.pdf'), null);
});

test('only staff delete projects, packages and accounts', async () => {
  await seedProject();
  assert.equal((await call(deleteProject, null, { projectId: P })).error.code, 'unauthenticated');
  assert.equal((await call(deleteProject, bidder, { projectId: P })).error.code, 'permission-denied');
  assert.equal((await call(deletePackage, bidder, { projectId: P, packageId: 'concrete' })).error.code, 'permission-denied');
  assert.equal((await call(deleteAccount, bidder, { uid: staff })).error.code, 'permission-denied');
  assert.ok((await db.doc(`projects/${P}`).get()).exists);
});

test('deleting a package removes its bids and questions and leaves the rest', async () => {
  await seedProject();
  const { result } = await call(deletePackage, staff, { projectId: P, packageId: 'concrete' });
  assert.deepEqual(result, { deleted: true });
  const pkg = db.doc(`projects/${P}/packages/concrete`);
  assert.equal((await pkg.get()).exists, false);
  assert.equal((await pkg.collection('bids').get()).size, 0);
  assert.equal((await pkg.collection('questions').get()).size, 0);
  assert.ok((await db.doc(`projects/${P}/packages/rebar`).get()).exists);
  assert.equal((await db.doc(`projects/${P}/packages/rebar`).collection('bids').get()).size, 1);
});

test('deleting a project removes everything under it and un-features it', async () => {
  await seedProject();
  const { result, error } = await call(deleteProject, staff, { projectId: P });
  assert.equal(error, undefined);
  assert.deepEqual(result, { deleted: true });
  assert.equal((await db.doc(`projects/${P}`).get()).exists, false);
  assert.equal((await db.collection(`projects/${P}/packages`).get()).size, 0);
  assert.equal((await db.collection(`projects/${P}/packages/rebar/bids`).get()).size, 0);
  assert.equal((await db.collection(`projects/${P}/bidders`).get()).size, 0);
  assert.equal((await db.collection(`projects/${P}/bidderIndex`).get()).size, 0);
  assert.equal((await db.doc('config/app').get()).get('currentProject'), undefined);
});

test('deleting an account removes the sign-in and profile, never your own', async () => {
  assert.equal((await call(deleteAccount, staff, { uid: staff })).error.code, 'failed-precondition');
  const { result } = await call(deleteAccount, staff, { uid: bidder });
  assert.deepEqual(result, { deleted: true });
  assert.equal((await db.doc(`users/${bidder}`).get()).exists, false);
  await assert.rejects(admin.auth().getUser(bidder), error => error.code === 'auth/user-not-found');
});
