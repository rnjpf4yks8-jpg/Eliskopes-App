// Bidding, run on the server so it is fair:
//   placeBid             callable: one bid, exactly 1% under the current low, checked in a transaction
//   awardClosedPackages  every 5 minutes: awards packages whose bidding has closed and reveals the names
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const { nextBid, EXTEND_MS, money, checkBid, newBidderId } = require('./rules');
const { notify } = require('./notify');

const { FieldValue, Timestamp } = admin.firestore;

// invoker 'public': the app can reach it; the function itself checks who is signed in and approved.
exports.placeBid = onCall({ invoker: 'public' }, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to bid.');
  const uid = request.auth.uid;
  const { projectId, packageId } = request.data || {};
  const amount = Number(request.data?.amount);
  if (typeof projectId !== 'string' || typeof packageId !== 'string' || !Number.isInteger(amount) || amount <= 0) {
    throw new HttpsError('invalid-argument', 'That bid is missing its project, package or amount.');
  }

  const db = admin.firestore();
  const projectRef = db.doc(`projects/${projectId}`);
  const packageRef = projectRef.collection('packages').doc(packageId);
  const bidderRef = projectRef.collection('bidders').doc(uid);

  const outcome = await placeInTransaction(db, projectRef, packageRef, bidderRef, uid, amount);

  logger.info(`Bid ${money(amount)} on ${projectId}/${packageId} by ${outcome.bidderId}${outcome.extended ? ' (clock extended)' : ''}`);
  await alertOutbid(projectRef, projectId, packageId, outcome, amount);
  return { amount, bidder: outcome.bidderId };
});

async function placeInTransaction(db, projectRef, packageRef, bidderRef, uid, amount) {
  try {
    return await runBid(db, projectRef, packageRef, bidderRef, uid, amount);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error(`placeBid failed: ${error.message}`, error);
    throw new HttpsError('internal', 'The server couldn’t place your bid right now. Nothing was bid. Try again in a minute.');
  }
}

function runBid(db, projectRef, packageRef, bidderRef, uid, amount) {
  return db.runTransaction(async tx => {
    // Every read comes before any write, as Firestore transactions require.
    const [packageSnap, userSnap, bidderSnap] = await Promise.all([
      tx.get(packageRef), tx.get(db.doc(`users/${uid}`)), tx.get(bidderRef),
    ]);
    if (!packageSnap.exists) throw new HttpsError('not-found', 'That package isn’t open for bidding.');
    const pkg = packageSnap.data();
    const user = userSnap.exists ? userSnap.data() : undefined;
    let bidderId = bidderSnap.exists ? bidderSnap.get('id') : null;
    const nowMs = Date.now();
    const closesAtMs = pkg.closesAt.toMillis();

    const problem = checkBid({ pkg: { ...pkg, closesAtMs }, user, bidderId, amount, nowMs });
    if (problem) throw new HttpsError(problem[0], problem[1]);

    // First bid on this project: give the bidder an anonymous ID no one else on the project has.
    const isNewBidder = !bidderId;
    for (let tries = 0; !bidderId && tries < 8; tries++) {
      const candidate = newBidderId();
      const taken = await tx.get(projectRef.collection('bidderIndex').doc(candidate));
      if (!taken.exists) bidderId = candidate;
    }
    if (!bidderId) throw new HttpsError('unavailable', 'Couldn’t assign your bidder ID. Try again.');

    const now = Timestamp.now();
    if (isNewBidder) {
      tx.set(bidderRef, { id: bidderId, company: user.company || '', createdAt: now });
      tx.set(projectRef.collection('bidderIndex').doc(bidderId), { uid, company: user.company || '' });
    }
    const update = { lowBid: amount, lowBidder: bidderId, bidCount: FieldValue.increment(1), lastBidAt: now };
    const extended = closesAtMs - nowMs < EXTEND_MS;
    if (extended) update.closesAt = Timestamp.fromMillis(closesAtMs + EXTEND_MS);
    tx.update(packageRef, update);
    tx.set(packageRef.collection('bids').doc(), { bidder: bidderId, amount, at: now });
    return { bidderId, previousBidder: pkg.lowBidder || null, name: pkg.name, extended };
  });
}

/// Tells whoever held the low bid. A failed alert never undoes the bid.
async function alertOutbid(projectRef, projectId, packageId, outcome, amount) {
  if (outcome.previousBidder && outcome.previousBidder !== outcome.bidderId) {
    try {
      const index = await projectRef.collection('bidderIndex').doc(outcome.previousBidder).get();
      if (index.exists) {
        await notify(index.get('uid'), `Outbid on ${outcome.name}`,
          `New low ${money(amount)}. The next bid is ${money(nextBid(amount))}.`, { projectId, packageId });
      }
    } catch (error) {
      logger.warn(`Outbid alert failed: ${error.message}`);
    }
  }
}

exports.awardClosedPackages = onSchedule({ schedule: 'every 5 minutes', timeZone: 'America/Chicago' }, async () => {
  await awardDue(admin.firestore(), Date.now());
});

/** Awards every package whose bidding has closed. Exported for the admin script and tests. */
async function awardDue(db, nowMs) {
  const projects = await db.collection('projects').where('status', '==', 'open').get();
  let awarded = 0;
  for (const project of projects.docs) {
    const due = await project.ref.collection('packages').where('closesAt', '<=', Timestamp.fromMillis(nowMs)).get();
    for (const doc of due.docs) {
      if (doc.get('awarded') !== true && await awardPackage(db, project.ref, doc.ref, nowMs)) awarded++;
    }
    const all = await project.ref.collection('packages').get();
    if (!all.empty && all.docs.every(d => d.get('awarded') === true)) await project.ref.update({ status: 'awarded' });
  }
  return awarded;
}

async function awardPackage(db, projectRef, packageRef, nowMs) {
  const result = await db.runTransaction(async tx => {
    const snap = await tx.get(packageRef);
    const pkg = snap.data();
    // A late bid may have pushed the close out since the query ran.
    if (!pkg || pkg.awarded === true || pkg.closesAt.toMillis() > nowMs) return null;
    const bids = await tx.get(packageRef.collection('bids'));
    const ids = [...new Set(bids.docs.map(b => b.get('bidder')))];
    const index = await Promise.all(ids.map(id => tx.get(projectRef.collection('bidderIndex').doc(id))));
    const names = {};
    const uids = {};
    index.forEach((s, i) => {
      if (s.exists) {
        names[ids[i]] = s.get('company') || ids[i];
        uids[ids[i]] = s.get('uid');
      }
    });
    const winner = pkg.lowBidder ? (names[pkg.lowBidder] || pkg.lowBidder) : null;
    tx.update(packageRef, { awarded: true, winner, awardedAt: Timestamp.now() });
    tx.set(packageRef.collection('reveal').doc('names'), names);
    return { name: pkg.name, amount: pkg.lowBid ?? null, winnerBidder: pkg.lowBidder || null, winner, uids };
  });
  if (!result) return false;
  logger.info(`Awarded ${packageRef.path} to ${result.winner || 'nobody (no bids)'}`);

  for (const [bidderId, uid] of Object.entries(result.uids)) {
    const won = bidderId === result.winnerBidder;
    try {
      await notify(uid, won ? `You won ${result.name}` : `${result.name} was awarded`,
        won ? `Your bid of ${money(result.amount)} is the winning bid.`
            : `${result.winner} won at ${money(result.amount)}.`,
        { projectId: projectRef.id, packageId: packageRef.id });
    } catch (error) {
      logger.warn(`Award alert failed: ${error.message}`);
    }
  }
  return true;
}

exports.awardDue = awardDue;
