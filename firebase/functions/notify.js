// Push notifications through Firebase Cloud Messaging. The app saves each phone's token in
// users/{uid}.fcmTokens; tokens Apple no longer accepts are removed here.
const admin = require('firebase-admin');

const DEAD_TOKEN = ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'];

async function notify(uid, title, body, data = {}) {
  if (!uid) return;
  const ref = admin.firestore().doc(`users/${uid}`);
  const tokens = (await ref.get()).get('fcmTokens') || [];
  if (!tokens.length) return;
  const reply = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    apns: { payload: { aps: { sound: 'default' } } },
  });
  const dead = tokens.filter((_, i) => !reply.responses[i].success && DEAD_TOKEN.includes(reply.responses[i].error?.code));
  if (dead.length) await ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead) });
}

module.exports = { notify };
