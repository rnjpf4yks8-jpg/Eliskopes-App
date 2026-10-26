// Eliskopes Cloud Functions. Deploy from the firebase folder: firebase deploy --only functions
const admin = require('firebase-admin');

admin.initializeApp();

const bids = require('./bids');

// Bidding: one bid at a time, exactly 1% under the current low (bids.js, rules in rules.js).
exports.placeBid = bids.placeBid;
// Every 5 minutes: award packages whose bidding has closed and reveal bidder names.
exports.awardClosedPackages = bids.awardClosedPackages;
// Signing up or upgrading to staff with the staff code (staff.js).
exports.claimStaff = require('./staff').claimStaff;
