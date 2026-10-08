// Turns data/source/cards.js into data/cards.json for Godot: the three decks as lists of text.
// A card's number is its position in its list. Re-run after changing cards.js.
const fs = require('fs');
const path = require('path');
const cards = require('../data/source/cards.js');

const out = { performance: cards.performance, settlement: cards.settlement, scandal: cards.scandal };
for (const [name, list] of Object.entries(out)) {
  if (!list.length || list.some((c) => typeof c !== 'string' || !c.trim())) throw new Error(`The ${name} deck has an empty card`);
}
fs.writeFileSync(path.join(__dirname, '../data/cards.json'), JSON.stringify(out, null, 1) + '\n');
console.log('cards.json written: ' + Object.entries(out).map(([n, l]) => `${l.length} ${n}`).join(', '));
