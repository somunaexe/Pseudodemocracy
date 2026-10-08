// ============================================================
// THE single source of truth for every number in Pseudodemocracy.
// Rules, articles and the Quick-Start Summary all read from here.
// Change a value once here and every document updates.
// ============================================================

const V = {
  minPlayers: 3,
  boxPlayers: 10,                 // the box holds money for this many players

  // Money
  playerNotes:   { 1: 10, 5: 10, 10: 10, 20: 12, 50: 6, 100: 3 },   // per player
  treasuryNotes: { 1: 50, 5: 20, 10: 10, 20: 15, 50: 10, 100: 15 }, // extra reserve in the box

  // Popularity
  popMin: -50, popMax: 50,
  cancelledAt: -50,                                         // CANCELLED at or below this popularity

  // Exam
  examQuestions: 5, examOptions: 2, passMark: 50,            // passMark is an article

  // Treasury income
  taxRate: 20,                                              // article
  levy: { start: 25, bandLow: 25, bandHigh: 50, shift: 10, trigger: 20, floor: 25 },

  // Coups (locked rules)
  coupCost: 300, coupGap: 20, coupedScore: '½',

  // Cards: after a Performance card, draw a Result card
  goodCard: 'Settlement', badCard: 'Scandal',
  corruption: { limit: 3, pop: 30, fine: 200, wait: 3 },   // corruption markers (card glossary)

  // Votes
  discussionMinutes: 1, malpracticeFine: 25,                // fine is an article
  amendPenalty: 100,                                        // failed amendment check
  swing: [['3', 10], ['4', 7], ['5', 6], ['6', 5], ['7', 4], ['8–10', 3], ['11+', 1]],

  // Physical components (print run)
  components: {
    leaderCards: { Dictator: 1, President: 3, Commander: 1 },
    roleCards: ['Doctor', 'Lawyer', 'Secret Agent', 'Activist', 'Agbero'], roleCopies: 5,
    willCards: 8, corruptionTokens: 15, coupStickers: 10,
  },

  // Health
  beads: { cure: 'blue', poison: 'red' },                   // Doctor's Cure/Poison beads (replace prescription cards)
  doctorCharges: 2, agboRounds: 1, concoctionRounds: 2,

  // Unions
  unionStart: 1, unionMin: 2, agberoSteal: 50, activistVote: 'double',

  // Inheritance
  nepoDebuff: [30, 20, 10],

  // Elections (digital version)
  electionRunoffs: 1,             // a tied vote is re-run among the tied candidates this many times, then decided by lot
  examMaxQuestions: 20, examMaxOptions: 6, examTextMax: 200,   // limits on what a Leader may write in an exam

  // Debt (digital version)
  debtMaxTerms: 3,                // eliminated when still in debt at the end of this many of their own turns
};

// ---- Derived values (computed, never typed) ----
const sum = (notes) => Object.entries(notes).reduce((a, [d, n]) => a + Number(d) * n, 0);
V.startMoney = sum(V.playerNotes);
V.treasuryReserve = sum(V.treasuryNotes);
V.boxTotal = V.startMoney * V.boxPlayers + V.treasuryReserve;
V.highestNote = Math.max(...Object.keys(V.playerNotes).map(Number));
V.treasuryFor = (players) => V.boxTotal - V.startMoney * players;
V.midTermAfter = (players) => Math.ceil(players / 2);
V.tieBreakShift = -V.popMin + 1;   // tie-break score = (popularity + this) x PSD; the +1 keeps a CANCELLED player (-50) above 0

// ---- Fail fast: sanity checks ----
const EXPECTED_START_MONEY = 1000; // change this on purpose if you change starting money
if (V.startMoney !== EXPECTED_START_MONEY)
  throw new Error(`Starting money is ${V.startMoney} PSD, expected ${EXPECTED_START_MONEY}. Check the note counts, or update EXPECTED_START_MONEY if the change is intentional.`);
if (V.cancelledAt < V.popMin || V.cancelledAt >= V.popMax) throw new Error('CANCELLED threshold must be inside the popularity range');
if (V.coupCost > V.startMoney) throw new Error('Coup cost is more than a player starts with');
if (V.levy.start < V.levy.bandLow || V.levy.start > V.levy.bandHigh) throw new Error('Starting levy is outside the levy band');

// ---- Formatting helpers ----
const fmt = (n) => n.toLocaleString('en-GB');
const ord = (n) => n + (['th', 'st', 'nd', 'rd'][(n % 100 - 20) % 10] || ['th', 'st', 'nd', 'rd'][n % 100] || 'th');
const notesList = (notes) => {
  const parts = Object.entries(notes).map(([d, n]) => `${d} (${n}×)`);
  return parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1];
};

module.exports = { V, fmt, ord, notesList };
