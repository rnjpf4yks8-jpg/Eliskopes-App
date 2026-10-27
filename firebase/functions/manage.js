// Staff tools that remove things for good. The security rules don't let the app delete these directly,
// because each one has records under it (bids, questions, bidder IDs, PDFs) that must go with it.
//   deleteProject   a project with its packages, bids, questions, award names, bidder IDs and plan PDFs
//   deletePackage   one package with its bids, questions and award names (and PDFs no other package uses)
//   deleteAccount   a person's sign-in and profile. Their anonymous bidder IDs stay, so bid history still reads.
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

const validId = id => typeof id === 'string' && id.length > 0 && id.length <= 200 && !id.includes('/');

async function requireStaff(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const caller = await admin.firestore().doc(`users/${request.auth.uid}`).get();
  if (caller.get('role') !== 'staff') throw new HttpsError('permission-denied', 'Only Eliskopes staff can do that.');
}

/** Turns unexpected failures into a message the app can show; HttpsErrors pass through. */
function guarded(name, handler) {
  return onCall({ invoker: 'public' }, async request => {
    try {
      return await handler(request);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error(`${name} failed: ${error.message}`, error);
      throw new HttpsError('internal', 'The server couldn’t delete that right now. Nothing more was removed. Try again in a minute.');
    }
  });
}

/** The Storage path inside a Firebase download link, e.g. projects/p1/documents/plans.pdf. */
function storagePath(url) {
  const match = /\/o\/([^?]+)/.exec(String(url || ''));
  return match ? decodeURIComponent(match[1]) : null;
}

/** Deletes Storage files. Failures (a file already gone, no bucket in the emulator) are logged, not fatal. */
async function deleteFiles({ prefix, paths = [] }) {
  let bucket;
  try {
    bucket = admin.storage().bucket();
  } catch (error) {
    logger.warn(`No Storage bucket, files left in place: ${error.message}`);
    return;
  }
  if (prefix) {
    try {
      await bucket.deleteFiles({ prefix });
    } catch (error) {
      logger.warn(`Couldn't delete files under ${prefix}: ${error.message}`);
    }
  }
  await Promise.all(paths.map(p => bucket.file(p).delete({ ignoreNotFound: true }).catch(error => {
    logger.warn(`Couldn't delete ${p}: ${error.message}`);
  })));
}

exports.deleteProject = guarded('deleteProject', async request => {
  await requireStaff(request);
  const projectId = request.data?.projectId;
  if (!validId(projectId)) throw new HttpsError('invalid-argument', 'Which project?');
  const db = admin.firestore();
  const ref = db.doc(`projects/${projectId}`);

  // PDFs linked from the packages, wherever they were uploaded, plus everything under the project's folder.
  const packages = await ref.collection('packages').get();
  const linked = packages.docs.flatMap(d => (d.get('documents') || []).map(x => storagePath(x.url)))
    .filter(p => p && p.startsWith(`projects/${projectId}/`));
  await db.recursiveDelete(ref);
  await deleteFiles({ prefix: `projects/${projectId}/`, paths: [...new Set(linked)] });

  const config = db.doc('config/app');
  if ((await config.get()).get('currentProject') === projectId) {
    await config.update({ currentProject: admin.firestore.FieldValue.delete() });
  }
  logger.info(`${request.auth.uid} deleted project ${projectId} (${packages.size} packages)`);
  return { deleted: true };
});

exports.deletePackage = guarded('deletePackage', async request => {
  await requireStaff(request);
  const { projectId, packageId } = request.data || {};
  if (!validId(projectId) || !validId(packageId)) throw new HttpsError('invalid-argument', 'Which package?');
  const db = admin.firestore();
  const projectRef = db.doc(`projects/${projectId}`);
  const ref = projectRef.collection('packages').doc(packageId);
  const snap = await ref.get();
  if (!snap.exists) return { deleted: true };

  // A PDF attached to every package (attach-doc … all) stays while another package still lists it.
  const others = (await projectRef.collection('packages').get()).docs.filter(d => d.id !== packageId);
  const stillUsed = new Set(others.flatMap(d => (d.get('documents') || []).map(x => storagePath(x.url))));
  const unused = (snap.get('documents') || []).map(x => storagePath(x.url))
    .filter(p => p && p.startsWith(`projects/${projectId}/`) && !stillUsed.has(p));

  await db.recursiveDelete(ref);
  await deleteFiles({ paths: [...new Set(unused)] });
  logger.info(`${request.auth.uid} deleted package ${projectId}/${packageId}`);
  return { deleted: true };
});

exports.deleteAccount = guarded('deleteAccount', async request => {
  await requireStaff(request);
  const uid = request.data?.uid;
  if (!validId(uid)) throw new HttpsError('invalid-argument', 'Whose account?');
  if (uid === request.auth.uid) throw new HttpsError('failed-precondition', 'You can’t delete your own account here.');
  const db = admin.firestore();
  const profile = await db.doc(`users/${uid}`).get();
  await db.recursiveDelete(db.doc(`users/${uid}`));
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  logger.info(`${request.auth.uid} deleted account ${uid} (${profile.get('email') || 'no email'})`);
  return { deleted: true };
});

exports.storagePath = storagePath;
