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
  discussionMinutes: 1, malpracticeFine: 25,
  performanceSeconds: 60,         // (digital version) a player performs their card for this long
  choiceSeconds: 10,              // (digital version) a player who is asked to choose has this long; then the server chooses at random for them
  performanceVoteSeconds: 15,     // then everyone else has this long to vote Good or Bad; no vote, no count                // fine is an article
  amendPenalty: 100,                                        // failed amendment check
  swing: [['3', 10], ['4', 7], ['5', 6], ['6', 5], ['7', 4], ['8–10', 3], ['11+', 1]],

  // Physical components (print run)
  components: {
    leaderCards: { Dictator: 1, President: 1, Commander: 1 },
    roleCards: ['Doctor', 'Lawyer', 'Secret Agent', 'Activist', 'Agbero'], roleCopies: 5,
    willCards: 8, corruptionTokens: 15, coupStickers: 10,
  },

  // Income, paid from the treasury on the player's own turn (tax is taken from it, rounded down). Roles stack.
  leaderIncome: 100,
  viceIncome: 90,                 // a Vice (a second Leader, made by a card) earns this; not built yet
  roleIncome: { 'Doctor': 70, 'Lawyer': 50, 'Secret Agent': 80, 'Activist': 0, 'Agbero': 0 },   // Activists and Agberos earn nothing

  // Gender (digital version): players enter it before the game so the gendered cards can work
  genders: ['female', 'male'],

  // Health
  beads: { cure: 'blue', poison: 'red' },                   // Doctor's Cure/Poison beads (replace prescription cards)
  doctorCharges: 2, agboRounds: 1, concoctionRounds: 2,
  doseOfferSeconds: 30,           // (digital version) a patient has this long to accept or reject a dose; silence is a rejection
  doseGuessSeconds: 10,           // (digital version) after a cure is accepted, anyone may guess Sabotage for this long
  commandVoteMultiplier: 2,      // in a Command Performance the commanding union's or mob's total popularity vote is doubled (Article 16)
  amendCosignSeconds: 30,        // (digital version) the Leader or the Vice has this long to agree to the other's proposal to amend; silence is a refusal
  agentOfferSeconds: 30,         // (digital version) a Secret Agent has this long to accept a hire; silence is a refusal
  agentPriceMax: 5000,           // (digital version) the most a Secret Agent may charge for a check
  scenarioMax: 280,              // (digital version) the most characters in a scenario a union or mob scripts for a Command Performance
  unionInviteSeconds: 30,         // (digital version) a player asked to join a union has this long to answer; silence is a refusal
  willOfferSeconds: 30,           // (digital version) a Lawyer has this long to accept a will; silence is a refusal
  willPriceMax: 5000,             // (digital version) the most a Lawyer may ask as a fee, or as upkeep a round
  dosePriceMax: 5000,             // (digital version) the most a Doctor may ask for a dose

  // Unions
  unionStart: 1, unionMin: 2, agberoSteal: 50, activistVote: 'double',

  // Inheritance
  nepoDebuff: [30, 20, 10],

  // Elections (digital version)
  electionRunoffs: 1,             // a tied vote is re-run among the tied candidates this many times, then decided by lot
  examMaxQuestions: 10, examMaxOptions: 3, examTextMax: 200,   // limits on what a Leader may write in an exam

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
for (const role of V.components.roleCards) if (typeof V.roleIncome[role] !== 'number') throw new Error(`The role ${role} has no income (use 0 for none)`);
if (V.levy.start < V.levy.bandLow || V.levy.start > V.levy.bandHigh) throw new Error('Starting levy is outside the levy band');

// ---- Formatting helpers ----
const fmt = (n) => n.toLocaleString('en-GB');
const ord = (n) => n + (['th', 'st', 'nd', 'rd'][(n % 100 - 20) % 10] || ['th', 'st', 'nd', 'rd'][n % 100] || 'th');
const notesList = (notes) => {
  const parts = Object.entries(notes).map(([d, n]) => `${d} (${n}×)`);
  return parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1];
};

module.exports = { V, fmt, ord, notesList };
