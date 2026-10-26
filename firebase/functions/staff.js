// Makes the signed-in user staff (full administrator rights) when they enter the right staff code.
// The code is a Firebase secret, so it never ships in the app:
//   firebase functions:secrets:set STAFF_CODE
// After 10 wrong tries an account is locked out of this; staff can still set roles on the People screen.
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('node:crypto');

const STAFF_CODE = defineSecret('STAFF_CODE');
const MAX_WRONG_TRIES = 10;

/// Compares without leaking how much of the code matched.
function sameCode(a, b) {
  const hash = text => crypto.createHash('sha256').update(text).digest();
  return crypto.timingSafeEqual(hash(a), hash(b));
}

// invoker 'public': the app can reach it; the function itself requires a signed-in account and the code.
exports.claimStaff = onCall({ secrets: [STAFF_CODE], invoker: 'public' }, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const uid = request.auth.uid;
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const triesRef = db.doc(`staffCodeAttempts/${uid}`);

  const secret = STAFF_CODE.value().trim();
  if (secret.length < 6) {
    throw new HttpsError('failed-precondition', 'Staff codes aren’t set up yet (STAFF_CODE secret, see firebase/README.md).');
  }
  const tries = (await triesRef.get()).get('count') || 0;
  if (tries >= MAX_WRONG_TRIES) {
    throw new HttpsError('resource-exhausted', 'Too many wrong staff codes. Ask Eliskopes staff to set your role.');
  }

  const code = String(request.data?.code ?? '').trim();
  if (!code || !sameCode(code, secret)) {
    await triesRef.set({ count: tries + 1, lastTry: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    logger.warn(`Wrong staff code from ${uid} (${tries + 1} of ${MAX_WRONG_TRIES})`);
    throw new HttpsError('permission-denied', 'That staff code isn’t right.');
  }

  const user = await userRef.get();
  if (!user.exists) throw new HttpsError('failed-precondition', 'Finish creating your account first, then enter the code.');
  await userRef.update({ role: 'staff', approved: true });
  await triesRef.delete();
  logger.info(`${uid} (${user.get('email') || 'no email'}) is now staff`);
  return { role: 'staff' };
});
