// Turns data/source/cards.js into data/cards.json for Godot: the three decks as lists of text,
// plus the effects the game applies by itself. A card's number is its position in its list.
// Re-run after changing cards.js. The export fails loudly if an effect doesn't fit its card.
const fs = require('fs');
const path = require('path');
const cards = require('../data/source/cards.js');
const { V } = require('../data/source/game_data.js');

const DECKS = ['performance', 'settlement', 'scandal'];
const out = { performance: cards.performance, settlement: cards.settlement, scandal: cards.scandal, effects: { settlement: {}, scandal: {} } };
for (const name of DECKS) {
  const list = out[name];
  if (!list.length || list.some((c) => typeof c !== 'string' || !c.trim())) throw new Error(`The ${name} deck has an empty card`);
}

const ROLES = V.components.roleCards;
const UNIONS = ['activist', 'agbero'];
const MONEY_KEYS = ['psd', 'popularity'];
const SELF_KEYS = ['psd', 'popularity', 'sick', 'immune'];   // what a card can do to its drawer (sick and immune must be positive)

function fail(deck, prefix, message) { throw new Error(`${deck}: "${prefix}": ${message}`); }

// psd / popularity amounts must be whole, non-zero, and appear as a number in the card's own text.
function checkAmounts(deck, prefix, text, effect, allowed) {
  for (const [kind, amount] of Object.entries(effect)) {
    if (kind === 'label') continue;
    if (!allowed.includes(kind)) fail(deck, prefix, `unknown effect "${kind}"`);
    if (!Number.isInteger(amount) || amount === 0) fail(deck, prefix, `has a bad ${kind} amount`);
    if (!new RegExp(`(^|[^0-9])${Math.abs(amount)}([^0-9]|$)`).test(text)) fail(deck, prefix, `${Math.abs(amount)} does not appear in the card's text`);
  }
}

function validate(deck, prefix, text, effect) {
  const known = [...SELF_KEYS, 'choose', 'gain_role', 'swap_with', 'target', 'keep', 'found_union'];
  if ('keep' in effect) {
    if (effect.keep !== true) fail(deck, prefix, '"keep" must be true');
    for (const key of Object.keys(effect)) if (!['keep', 'found_union', 'choose'].includes(key)) fail(deck, prefix, `a kept card can't also have "${key}"`);
    if (!('found_union' in effect) && !('choose' in effect)) fail(deck, prefix, 'a kept card must do something when played');
  }
  if ('found_union' in effect && !UNIONS.includes(effect.found_union)) fail(deck, prefix, `unknown union "${effect.found_union}"`);
  if ('found_union' in effect && 'choose' in effect) fail(deck, prefix, 'a card founds a union directly or by a choice, not both');
  for (const key of Object.keys(effect)) if (!known.includes(key)) fail(deck, prefix, `unknown effect "${key}"`);
  checkAmounts(deck, prefix, text, Object.fromEntries(SELF_KEYS.filter((k) => k in effect).map((k) => [k, effect[k]])), SELF_KEYS);
  for (const k of ['sick', 'immune']) if (k in effect && effect[k] < 0) fail(deck, prefix, `${k} must be positive`);
  const choose = effect.choose;
  if (!choose) {
    for (const key of ['gain_role', 'swap_with', 'target']) if (key in effect) fail(deck, prefix, `"${key}" needs a "choose"`);
    return;
  }
  if (!['option', 'role', 'player'].includes(choose.kind)) fail(deck, prefix, `unknown choice kind "${choose.kind}"`);
  if (choose.kind === 'option') {
    if (!Array.isArray(choose.options) || choose.options.length < 2) fail(deck, prefix, 'an option choice needs at least two options');
    for (const option of choose.options) {
      if (typeof option.label !== 'string' || !option.label) fail(deck, prefix, 'every option needs a label');
      checkAmounts(deck, prefix, text, Object.fromEntries(Object.entries(option).filter(([k]) => k !== 'found_union')), SELF_KEYS);
      if ('found_union' in option && !UNIONS.includes(option.found_union)) fail(deck, prefix, `unknown union "${option.found_union}"`);
    }
    for (const key of ['gain_role', 'swap_with', 'target']) if (key in effect) fail(deck, prefix, `"${key}" doesn't go with an option choice`);
  }
  if (choose.kind === 'player') {
    if ('who' in choose && choose.who !== 'has_role') fail(deck, prefix, `unknown "who": ${choose.who}`);
    if (effect.gain_role === '$choice') fail(deck, prefix, '"$choice" for a role needs a role choice');
    if ('swap_with' in effect && effect.swap_with !== '$choice') fail(deck, prefix, 'swap_with must be "$choice"');
    if ('target' in effect) checkAmounts(deck, prefix, text, effect.target, MONEY_KEYS);
  }
  if (choose.kind === 'role') {
    if (effect.gain_role !== '$choice') fail(deck, prefix, 'a role choice needs gain_role: "$choice"');
    for (const key of ['swap_with', 'target']) if (key in effect) fail(deck, prefix, `"${key}" doesn't go with a role choice`);
  }
  if ('gain_role' in effect && effect.gain_role !== '$choice' && !ROLES.includes(effect.gain_role)) fail(deck, prefix, `no such role "${effect.gain_role}"`);
}

// Find each card by the start of its text and keep its number (position in the deck).
let counted = 0;
for (const deck of ['settlement', 'scandal']) {
  for (const [prefix, effect] of cards.effects[deck]) {
    const found = out[deck].map((t, i) => (t.startsWith(prefix) ? i : -1)).filter((i) => i >= 0);
    if (found.length !== 1) fail(deck, prefix, `matches ${found.length} cards, expected exactly 1`);
    validate(deck, prefix, out[deck][found[0]], effect);
    if (found[0] in out.effects[deck]) fail(deck, prefix, 'this card is listed twice');
    out.effects[deck][found[0]] = effect;
    counted++;
  }
}
fs.writeFileSync(path.join(__dirname, '../data/cards.json'), JSON.stringify(out, null, 1) + '\n');
console.log('cards.json written: ' + DECKS.map((n) => `${out[n].length} ${n}`).join(', ') + `; ${counted} cards with effects the game applies`);
