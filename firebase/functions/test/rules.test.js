// Run with: npm test (from firebase/functions)
const test = require('node:test');
const assert = require('node:assert/strict');
const { nextBid, checkBid, newBidderId, money } = require('../rules');

const pkg = { name: 'Concrete', trade: 'concrete', budget: 104_000_000, floor: 88_400_000, closesAtMs: Date.now() + 3600e3 };
const sub = { role: 'sub', approved: true, trades: ['concrete', 'haul'], company: 'Gulf Coast Concrete' };

test('each bid is 1% under, in cents, half a cent rounding up', () => {
  assert.equal(nextBid(620_000_000), 613_800_000);
  assert.equal(nextBid(613_800_000), 607_662_000);
  assert.equal(nextBid(607_662_000), 601_585_380);
  assert.equal(nextBid(50), 50); // 49.5 rounds up
  assert.equal(nextBid(150), 149); // 148.5 rounds up
  assert.equal(money(601_585_380), '$6,015,853.80');
});

test('the website example ladder ends where the website says', () => {
  // eliskopes.com: $6,200,000 falls to $5,663,807 after nine 1% steps (website rounds to dollars).
  let c = 620_000_000;
  for (let i = 0; i < 9; i++) c = nextBid(c);
  assert.equal(Math.round(c / 100), 5_663_807);
});

test('first bid is exactly 1% under the budget', () => {
  assert.equal(checkBid({ pkg, user: sub, bidderId: null, amount: 102_960_000, nowMs: Date.now() }), null);
  assert.equal(checkBid({ pkg, user: sub, bidderId: null, amount: 102_000_000, nowMs: Date.now() })[0], 'aborted');
});

test('who may bid', () => {
  const amount = nextBid(pkg.budget);
  const now = Date.now();
  assert.equal(checkBid({ pkg, user: undefined, bidderId: null, amount, nowMs: now })[0], 'failed-precondition');
  assert.equal(checkBid({ pkg, user: { ...sub, role: 'owner' }, bidderId: null, amount, nowMs: now })[0], 'permission-denied');
  assert.equal(checkBid({ pkg, user: { ...sub, role: 'staff' }, bidderId: null, amount, nowMs: now })[0], 'permission-denied');
  assert.equal(checkBid({ pkg, user: { ...sub, approved: false }, bidderId: null, amount, nowMs: now })[0], 'permission-denied');
  assert.equal(checkBid({ pkg, user: { ...sub, trades: ['rebar'] }, bidderId: null, amount, nowMs: now })[0], 'permission-denied');
});

test('closed, awarded, floor and holding the low bid', () => {
  const now = Date.now();
  assert.match(checkBid({ pkg: { ...pkg, closesAtMs: now - 1 }, user: sub, bidderId: null, amount: nextBid(pkg.budget), nowMs: now })[1], /closed/);
  assert.match(checkBid({ pkg: { ...pkg, awarded: true }, user: sub, bidderId: null, amount: nextBid(pkg.budget), nowMs: now })[1], /closed/);
  const atFloor = { ...pkg, lowBid: 88_500_000, lowBidder: 'B-111' };
  assert.match(checkBid({ pkg: atFloor, user: sub, bidderId: 'B-222', amount: nextBid(88_500_000), nowMs: now })[1], /floor/);
  const held = { ...pkg, lowBid: 100_000_000, lowBidder: 'B-8CW' };
  assert.match(checkBid({ pkg: held, user: sub, bidderId: 'B-8CW', amount: nextBid(100_000_000), nowMs: now })[1], /already hold/);
  assert.equal(checkBid({ pkg: held, user: sub, bidderId: 'B-9XX', amount: nextBid(100_000_000), nowMs: now }), null);
});

test('bidder IDs look like B-7Q2 and skip I and O', () => {
  for (let i = 0; i < 500; i++) assert.match(newBidderId(), /^B-[0-9A-HJ-NP-Z]{3}$/);
});
