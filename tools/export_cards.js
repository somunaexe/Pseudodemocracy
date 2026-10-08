// Turns data/source/cards.js into data/cards.json for Godot: the three decks as lists of text,
// plus the effects the game applies by itself. A card's number is its position in its list.
// Re-run after changing cards.js. The export fails loudly if an effect doesn't fit its card.
const fs = require('fs');
const path = require('path');
const cards = require('../data/source/cards.js');
const { V } = require('../data/source/game_data.js');

const DECKS = ['performance', 'settlement', 'scandal'];
const out = { performance: cards.performance, settlement: cards.settlement, scandal: cards.scandal, effects: { settlement: {}, scandal: {}, performance: {} } };
for (const name of DECKS) {
  const list = out[name];
  if (!list.length || list.some((c) => typeof c !== 'string' || !c.trim())) throw new Error(`The ${name} deck has an empty card`);
}

const ROLES = V.components.roleCards;
const UNIONS = ['activist', 'agbero'];
const GENDERS = V.genders;
const MONEY_KEYS = ['psd', 'popularity', 'marker'];
const SELF_KEYS = ['psd', 'popularity', 'sick', 'immune', 'no_coup'];

function fail(deck, prefix, message) { throw new Error(`${deck}: "${prefix}": ${message}`); }

// psd / popularity amounts must be whole, non-zero, and appear as a number in the card's own text.
function checkAmounts(deck, prefix, text, effect, allowed) {
  for (const [kind, amount] of Object.entries(effect)) {
    if (kind === 'label') continue;
    if (kind === 'marker') {
      if (amount !== 1) fail(deck, prefix, 'a card gives one marker');
      if (!/corruption marker/.test(text)) fail(deck, prefix, "marker needs 'corruption marker' in the card's text");
      continue;
    }
    if (!allowed.includes(kind)) fail(deck, prefix, `unknown effect "${kind}"`);
    if (!Number.isInteger(amount) || amount === 0) fail(deck, prefix, `has a bad ${kind} amount`);
    if (!new RegExp(`(^|[^0-9])${Math.abs(amount)}([^0-9]|$)`).test(text)) fail(deck, prefix, `${Math.abs(amount)} does not appear in the card's text`);
  }
}

function validate(deck, prefix, text, effect) {
  const known = [...SELF_KEYS, 'marker', 'choose', 'gain_role', 'swap_with', 'target', 'keep', 'found_union', 'collect_each', 'pay_chosen', 'truce', 'accord', 'skip_draw', 'disband', 'loyalist', 'target_role', 'popularity_per_loyalist', 'defect', 'keys', 'peek', 'peek_rival', 'favor', 'special'];
  const SPECIALS = ['old_boys', 'diaspora', 'hospital', 'flyover', 'statue', 'levy_cut', 'heckler', 'youth_wing', 'free_settlement', 'fundraiser', 'exam_pass', 'salary', 'deck_peek', 'loan', 'halve_loss', 'fee_bonus', 'vote_with', 'reroll', 'pop_floor', 'petrol', 'hero', 'benefits', 'holiday', 'apology', 'seat_debt', 'civilian', 'rally', 'tax_leak', 'flyover_collapse', 'tax_break', 'lost_20v1', 'delayed_reckoning', 'satirist', 'term_limits', 'role_freeze', 'skip_settlement', 'exam_rig', 'covid', 'skip_income', 'extra_performance'];   // the names in scripts/special_cards.gd (a test keeps the two lists equal)
  if ('special' in effect) {
    if (!SPECIALS.includes(effect.special)) fail(deck, prefix, `unknown special "${effect.special}"`);
    for (const key of Object.keys(effect)) if (!['special', 'keep'].includes(key)) fail(deck, prefix, `a special card has no other effects ("${key}")`);
    return;
  }
  const PEEK_KINDS = ['coup', 'bead'];
  for (const key of ['peek', 'peek_rival']) if (key in effect && (!Array.isArray(effect[key].kinds) || !effect[key].kinds.length || effect[key].kinds.some((k) => !PEEK_KINDS.includes(k)))) fail(deck, prefix, `"${key}" needs kinds from ${PEEK_KINDS}`);
  if ('peek' in effect && !(effect.choose && effect.choose.kind === 'player')) fail(deck, prefix, '"peek" needs a player choice');
  if ('favor' in effect && (effect.favor !== true || !(effect.choose && effect.choose.kind === 'player'))) fail(deck, prefix, '"favor" must be true and needs a player choice');
  if ('popularity_per_loyalist' in effect) {
    const spec = effect.popularity_per_loyalist;
    if (!GENDERS.includes(spec.gender)) fail(deck, prefix, `unknown gender "${spec.gender}"`);
    checkAmounts(deck, prefix, text, { popularity: spec.popularity }, ['popularity']);
  }
  if ('loyalist' in effect) {
    checkAmounts(deck, prefix, text, { psd: effect.loyalist.rounds }, ['psd']);
    if (effect.loyalist.rounds <= 0) fail(deck, prefix, 'a loyalty lasts at least one round');
    if (!effect.choose || effect.choose.kind !== 'player') fail(deck, prefix, '"loyalist" needs a player choice');
  }
  if ('target_role' in effect && (effect.target_role !== 'random' || !effect.choose || effect.choose.kind !== 'player')) fail(deck, prefix, '"target_role" must be "random" and needs a player choice');
  if ('defect' in effect && effect.defect !== true) fail(deck, prefix, '"defect" must be true');
  for (const flag of ['truce', 'skip_draw', 'disband', 'keys']) if (flag in effect && effect[flag] !== true) fail(deck, prefix, `"${flag}" must be true`);
  if ('accord' in effect) {
    checkAmounts(deck, prefix, text, { psd: effect.accord.rounds, popularity: effect.accord.loss }, ['psd', 'popularity']);
    if (effect.accord.rounds <= 0 || effect.accord.loss <= 0) fail(deck, prefix, 'an accord needs positive rounds and loss');
  }
  for (const key of ['truce', 'accord', 'skip_draw']) if (key in effect && !(effect.choose && effect.choose.kind === 'player')) fail(deck, prefix, `"${key}" needs a player choice`);
  if ('pay_chosen' in effect) {
    if (!effect.choose || effect.choose.kind !== 'player') fail(deck, prefix, 'pay_chosen needs a player choice');
    checkAmounts(deck, prefix, text, { psd: effect.pay_chosen }, ['psd']);
    if (effect.pay_chosen <= 0) fail(deck, prefix, 'pay_chosen must be positive');
  }
  if ('collect_each' in effect) {
    const spec = effect.collect_each;
    if (!GENDERS.includes(spec.gender)) fail(deck, prefix, `unknown gender "${spec.gender}"`);
    checkAmounts(deck, prefix, text, { psd: spec.amount }, ['psd']);
    if (spec.amount <= 0) fail(deck, prefix, 'collect_each must collect a positive amount');
  }
  if ('keep' in effect) {
    if (effect.keep !== true) fail(deck, prefix, '"keep" must be true');
    for (const key of Object.keys(effect)) if (!['keep', 'found_union', 'choose', 'truce'].includes(key)) fail(deck, prefix, `a kept card can't also have "${key}"`);
    if (!('found_union' in effect) && !('choose' in effect)) fail(deck, prefix, 'a kept card must do something when played');
  }
  if ('found_union' in effect && !UNIONS.includes(effect.found_union)) fail(deck, prefix, `unknown union "${effect.found_union}"`);
  if ('found_union' in effect && 'choose' in effect) fail(deck, prefix, 'a card founds a union directly or by a choice, not both');
  for (const key of Object.keys(effect)) if (!known.includes(key)) fail(deck, prefix, `unknown effect "${key}"`);
  checkAmounts(deck, prefix, text, Object.fromEntries([...SELF_KEYS, 'marker'].filter((k) => k in effect).map((k) => [k, effect[k]])), [...SELF_KEYS, 'marker']);
  for (const k of ['sick', 'immune', 'no_coup']) if (k in effect && effect[k] < 0) fail(deck, prefix, `${k} must be positive`);
  const choose = effect.choose;
  if (!choose) {
    for (const key of ['gain_role', 'swap_with', 'target']) if (key in effect) fail(deck, prefix, `"${key}" needs a "choose"`);
    return;
  }
  if (!['option', 'role', 'player'].includes(choose.kind)) fail(deck, prefix, `unknown choice kind "${choose.kind}"`);
  if ('chooser' in choose && (choose.chooser !== 'leader' || choose.kind !== 'option')) fail(deck, prefix, 'only an option choice can be made by the leader');
  if (choose.kind === 'option') {
    if (!Array.isArray(choose.options) || choose.options.length < 2) fail(deck, prefix, 'an option choice needs at least two options');
    for (const option of choose.options) {
      if (typeof option.label !== 'string' || !option.label) fail(deck, prefix, 'every option needs a label');
      checkAmounts(deck, prefix, text, Object.fromEntries(Object.entries(option).filter(([k]) => !['found_union', 'share', 'then', 'each'].includes(k))), [...SELF_KEYS, 'marker']);
      if ('share' in option && (option.share !== 'half' || !('psd' in effect) || effect.psd <= 0)) fail(deck, prefix, 'share "half" needs a card that pays the drawer');
      if ('then' in option && (option.then.kind !== 'player' || !option.each)) fail(deck, prefix, 'an option with "then" must ask for a player and say what happens to both ("each")');
      if ('each' in option) {
        // what each of the two pays may be half of an amount in the card ("they help you pay half")
        const halved = Object.fromEntries(Object.entries(option.each).map(([k, v]) => [k, (k === 'psd' && !new RegExp(`(^|[^0-9])${Math.abs(v)}([^0-9]|$)`).test(text)) ? v * 2 : v]));
        checkAmounts(deck, prefix, text, halved, [...SELF_KEYS, 'marker']);
      }
      if ('found_union' in option && !UNIONS.includes(option.found_union)) fail(deck, prefix, `unknown union "${option.found_union}"`);
    }
    for (const key of ['gain_role', 'swap_with', 'target']) if (key in effect) fail(deck, prefix, `"${key}" doesn't go with an option choice`);
  }
  if (choose.kind === 'player') {
    if ('who' in choose && !['has_role', 'rival', 'loyalist'].includes(choose.who)) fail(deck, prefix, `unknown "who": ${choose.who}`);
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
for (const [prefix, effect] of cards.effects.performance) {
  const found = out.performance.map((t, i) => (t.startsWith(prefix) ? i : -1)).filter((i) => i >= 0);
  if (found.length !== 1) fail('performance', prefix, `matches ${found.length} cards, expected exactly 1`);
  for (const [key, value] of Object.entries(effect)) if (!['pitch', 'debate'].includes(key) || value !== true) fail('performance', prefix, `unknown or bad effect "${key}"`);
  if (found[0] in out.effects.performance) fail('performance', prefix, 'this card is listed twice');
  out.effects.performance[found[0]] = effect;
  counted++;
}
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
