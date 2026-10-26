// The auction rules, kept free of Firebase so they can be tested on their own (npm test).
// The app uses the same math (Money.nextBid in Models.swift), so both always agree to the cent.

/** Each bid is 1% under the current low, in whole cents, half a cent rounding up. */
function nextBid(cents) {
  return Math.floor((cents * 99 + 50) / 100);
}

/** A bid in the last 5 minutes pushes the close out 5 minutes. No sniping. */
const EXTEND_MS = 5 * 60 * 1000;

const BIDDER_ROLES = ['gc', 'sub', 'supplier'];

function money(cents) {
  return '$' + (cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/**
 * Checks one bid. Returns null when it may be placed, or [errorCode, message for the bidder].
 *   pkg       package document data, with closesAtMs
 *   user      the bidder's users/{uid} data (may be undefined)
 *   bidderId  the bidder's anonymous ID on this project, or null before their first bid
 *   amount    what the app offered, in cents; must be exactly the next bid
 */
function checkBid({ pkg, user, bidderId, amount, nowMs }) {
  if (!user) return ['failed-precondition', 'Finish creating your account before bidding.'];
  if (!BIDDER_ROLES.includes(user.role)) return ['permission-denied', 'Only contractors, subcontractors and suppliers can bid.'];
  if (user.approved !== true) return ['permission-denied', 'Your account is waiting for approval by Eliskopes.'];
  if (!(user.trades || []).includes(pkg.trade)) {
    return ['permission-denied', `${user.company || 'Your company'} isn’t approved to bid on ${pkg.name}.`];
  }
  if (pkg.awarded === true || nowMs >= pkg.closesAtMs) return ['failed-precondition', `Bidding on ${pkg.name} has closed.`];
  const current = pkg.lowBid ?? pkg.budget;
  const next = nextBid(current);
  if (next < pkg.floor) return ['failed-precondition', `Bidding on ${pkg.name} has reached the owner’s floor.`];
  if (bidderId && pkg.lowBidder === bidderId) return ['failed-precondition', `You already hold the low bid on ${pkg.name}.`];
  if (amount !== next) {
    return ['aborted', `The low bid just changed to ${money(current)}. The next bid is now ${money(next)}.`];
  }
  return null;
}

// No I or O, so IDs read clearly aloud and on screen.
const ID_LETTERS = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';

/** A new anonymous bidder ID like "B-7Q2". */
function newBidderId(random = Math.random) {
  let id = 'B-';
  for (let i = 0; i < 3; i++) id += ID_LETTERS[Math.floor(random() * ID_LETTERS.length)];
  return id;
}

module.exports = { nextBid, EXTEND_MS, BIDDER_ROLES, money, checkBid, newBidderId };
