// The articles of the constitution. __words__ = highlighted (amendable) words.
// Every number comes from game_data.js.
const { V } = require('./game_data');
const [n1, n2, n3] = V.nepoDebuff;

// BINDINGS tie a highlighted word to the rule it controls, so the digital game applies the
// amended law instead of only showing new words. A bound word can only be replaced by a word
// the game understands; highlighted words with no binding stay free text that the table
// enforces, as in the physical game.
//   slot   = which highlighted word of the article (0 = the first one)
//   expect = the starting value; the export fails if the text and the data disagree
//   source = the game_data key the value started from (null if none); the tests use it to
//            stop code reading that number straight from game_data
const percent = (name, slot, label, expect, source) => ({ name, slot, type: 'percent', label, expect, source });
const whole = (name, slot, label, expect, source, min = 0, max = 99999) => ({ name, slot, type: 'int', label, expect, source, min, max });
const choice = (name, slot, label, expect, source, values) => ({ name, slot, type: 'enum', label, expect, source, values });
const MULTIPLIERS = { single: 1, double: 2, triple: 3, quadruple: 4 };
const COMPARISONS = { more: 1, less: -1, fewer: -1 };
const SIGNS = { '\u2212': -1, '-': -1, '+': 1 };

module.exports = [
  { chapter: 'Chapter I — Elections & the Treasury', articles: [
    ['Exam Pass Mark', `Players pass the exam by answering __more__ than __${V.passMark}%__ of questions correctly.`, [choice('passCompare', 0, 'the exam pass comparison', 'more', null, COMPARISONS), percent('passMark', 1, 'the exam pass mark', V.passMark, 'passMark')]],
    ['Tax', `Tax: __${V.taxRate}%__ of income goes to __the treasury__ every __round__.`, [percent('taxRate', 0, 'the tax rate', V.taxRate, 'taxRate')]],
    ['Levy', `__Every__ __player__ __pays__ a levy of __${V.levy.start}__ __PSD__ to __the treasury__ every round, regardless of income. The levy must stay within the levy band.`, [whole('levy', 3, 'the levy', V.levy.start, 'levy.start')]],
    ['Levy Band', `__The Leader__ sets the levy between ${V.levy.bandLow} and ${V.levy.bandHigh} PSD.`],
    ['Levy Band Shift', `When a term __ends__, __a__ __Leader__ below __\u2212__ __${V.levy.trigger}__ __popularity__ __raises__ the levy band by ${V.levy.shift} PSD, and __a__ __Leader__ __above__ __+__ __${V.levy.trigger}__ __popularity__ __lowers__ it by ${V.levy.shift} PSD. The band never drops below ${V.levy.floor} PSD. If the levy ends up outside the band, it moves to the closest value inside it.`],
    ['Malpractice', `An out-of-sync hand is a null vote and a __${V.malpracticeFine}__ PSD fine, paid to __the treasury__.`, [whole('malpracticeFine', 0, 'the malpractice fine', V.malpracticeFine, 'malpracticeFine')]],
  ] },
  { chapter: 'Chapter II — Unions', articles: [
    ['Union Size', `A union starts with __${V.unionStart}__ member and needs __${V.unionMin}__ members to act.`, [whole('unionStart', 0, 'the size a union starts with', V.unionStart, 'unionStart', 1), whole('unionMin', 1, 'the size a union needs to act', V.unionMin, 'unionMin', 1)]],
    ['Recruiting', 'Unions can’t recruit __the Leader__ or a member of __another__ union.'],
    ['Union Turns', 'A union may recruit, kick or act only on __the unionizer’s__ turn and on __the Leader’s__ turn if the Leader is a member.'],
    ['Leaving & Kicking', 'A member may leave on __their__ turn. __The unionizer__ kicks a member just by saying so.'],
    ['Dissolving', `If a union drops to __${V.unionStart}__ member, it dissolves.`, [whole('unionDissolveAt', 0, 'the size at which a union dissolves', V.unionStart, 'unionStart')]],
    ['Activists', 'Activist gains and losses are __shared__, and the union __lingers__ after acting.'],
    ['Agberos', 'Agbero gains and losses are __personal__, and the mob __disperses__ after acting.'],
    ['Activist Confront', `Activists confronting the Leader __${V.activistVote}__ their votes against the Leader.`, [choice('activistVote', 0, 'the Activist vote multiplier', V.activistVote, 'activistVote', MULTIPLIERS)]],
    ['Agbero Confront', `Agberos confronting the Leader block the amendment and steal __${V.agberoSteal}__ × union size.`, [whole('agberoSteal', 0, 'the Agbero steal', V.agberoSteal, 'agberoSteal')]],
    ['Command Performance', 'The Leader performs a scenario scripted by __the unionizer__.'],
    ['Leader in Union', 'If the Leader is in the union, its actions target a rival of __the Leader’s__ choice.'],
  ] },
  { chapter: 'Chapter III — Health', articles: [
    ['Sabotage Guess', '__Anyone__ may guess Sabotage __before__ __the patient__ __takes__ the bead.'],
    ['Right Guess', 'If right, __the Doctor__ __pays__ __the guesser__, gives a real Cure and __loses__ __their licence__.'],
    ['Wrong Guess', 'If wrong, __the guesser__ __pays__ __the Doctor__ the amount __the patient paid__.'],
    ['Sickness', 'Sick players __can’t__ use __role powers__, __write exams__, __vote__ or __be voted for__.'],
    ['Agbo', `Agbo: ±${V.agboRounds} round sick __and__ payment lost.`],
    ['Concoction', `Concoction: ±${V.concoctionRounds} rounds sick __and__ payment lost.`],
    ['Surgery', 'Surgery: instant __cure__ or __elimination__.'],
    ['Elimination', 'Eliminated players’ PSD goes to __the treasury__ and their roles are __rescinded__, unless willed.'],
  ] },
  { chapter: 'Chapter IV — Wills & Inheritance', articles: [
    ['Lawyer', 'The Lawyer signs wills for __an agreed__ fee and collects upkeep every __round__.'],
    ['Will on Hold', 'If you __die__ while your will is __on hold__, it __doesn’t count__.'],
    ['Heirs', 'You can name __the same heir__ or __different heirs__ for your __PSD__ and your __roles__.'],
    ['Unclaimed PSD', 'Unwilled or rejected PSD goes to __the treasury__.'],
    ['Nepo Baby', 'An heir who __accepts__ __an inheritance__ becomes a Nepo Baby.'],
    ['Nepo Baby Debuff', `Nepo Babies get __−__${n1}, __−__${n2} and __−__${n3} __popularity__ over the next ${V.nepoDebuff.length} rounds.`, [choice('nepoSign1', 0, 'the sign of the first Nepo Baby change', '\u2212', null, SIGNS), choice('nepoSign2', 1, 'the sign of the second Nepo Baby change', '\u2212', null, SIGNS), choice('nepoSign3', 2, 'the sign of the third Nepo Baby change', '\u2212', null, SIGNS)]],
  ] },
];
