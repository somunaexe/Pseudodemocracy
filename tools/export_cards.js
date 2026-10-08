// Turns data/source/cards.js into data/cards.json for Godot: the three decks as lists of text.
// A card's number is its position in its list. Re-run after changing cards.js.
const fs = require('fs');
const path = require('path');
const cards = require('../data/source/cards.js');

const out = { performance: cards.performance, settlement: cards.settlement, scandal: cards.scandal, effects: { settlement: {}, scandal: {} } };
for (const name of ['performance', 'settlement', 'scandal']) {
  const list = out[name];
  if (!list.length || list.some((c) => typeof c !== 'string' || !c.trim())) throw new Error(`The ${name} deck has an empty card`);
}
// Effects: find each card by the start of its text and keep its number (position in the deck).
let counted = 0;
for (const deck of ['settlement', 'scandal']) {
  for (const [prefix, effect] of cards.effects[deck]) {
    const found = out[deck].map((t, i) => (t.startsWith(prefix) ? i : -1)).filter((i) => i >= 0);
    if (found.length !== 1) throw new Error(`${deck}: "${prefix}" matches ${found.length} cards, expected exactly 1`);
    const text = out[deck][found[0]];
    for (const [kind, amount] of Object.entries(effect)) {
      if (!['psd', 'popularity'].includes(kind)) throw new Error(`${deck}: unknown effect "${kind}"`);
      if (!Number.isInteger(amount) || amount === 0) throw new Error(`${deck}: "${prefix}" has a bad ${kind} amount`);
      if (!new RegExp(`(^|[^0-9])${Math.abs(amount)}([^0-9]|$)`).test(text)) throw new Error(`${deck}: "${prefix}": ${Math.abs(amount)} does not appear in the card's text`);
    }
    out.effects[deck][found[0]] = effect;
    counted++;
  }
}
fs.writeFileSync(path.join(__dirname, '../data/cards.json'), JSON.stringify(out, null, 1) + '\n');
console.log('cards.json written: ' + ['performance', 'settlement', 'scandal'].map((n) => `${out[n].length} ${n}`).join(', ') + `; ${counted} cards with effects the game applies`);
