// Turns data/source/articles.js into data/articles.json for Godot.
// Each article becomes a list of words: { text, amendable, glue }.
//   amendable: the word was between __ markers, so a Leader may replace it.
//   glue:      no space before this word (punctuation, or text stuck to a marker).
const fs = require('fs');
const path = require('path');
const chapters = require('../data/source/articles.js');

function toWords(raw) {
  const words = [];
  let amendable = false;   // are we inside __ ... __ ?
  let cur = null;          // word being built
  let glue = false;        // does the next word start with no space before it?

  const flush = () => {
    if (cur !== null && cur.text !== '') { words.push(cur); glue = true; }
    cur = null;
  };
  const start = () => { if (cur === null) { cur = { text: '', amendable, glue }; } };

  for (let i = 0; i < raw.length; i++) {
    if (raw.startsWith('__', i)) {          // marker: flip state, break the word
      flush();
      amendable = !amendable;
      i++;
    } else if (raw[i] === ' ') {            // space: next word has a space before it
      flush();
      glue = false;
    } else {
      start();
      cur.text += raw[i];
    }
  }
  flush();
  if (amendable) throw new Error('Unclosed __ marker in: ' + raw);
  return words;
}

// What a bound word may look like. The game reads the same rules (scripts/law.gd).
const PARSERS = {
  int: (word) => (/^\d{1,5}$/.test(word) ? Number(word) : null),
  percent: (word) => (/^\d{1,3}%$/.test(word) ? Number(word.slice(0, -1)) : null),
  enum: (word, b) => (Object.prototype.hasOwnProperty.call(b.values, word.toLowerCase()) ? b.values[word.toLowerCase()] : null),
};

// Check a binding against the article's starting words, and return it ready for the JSON.
function checkBinding(title, words, b, seen) {
  const where = `${title} / ${b.name}`;
  if (seen.has(b.name)) throw new Error(`Binding name used twice: ${b.name}`);
  seen.add(b.name);
  if (!PARSERS[b.type]) throw new Error(`${where}: unknown type ${b.type}`);
  const slots = words.filter((w) => w.amendable);
  if (!slots[b.slot]) throw new Error(`${where}: the article has no highlighted word number ${b.slot}`);
  const value = PARSERS[b.type](slots[b.slot].text, b);
  if (value === null) throw new Error(`${where}: the starting word "${slots[b.slot].text}" is not readable as ${b.type}`);
  const wanted = b.type === 'enum' ? PARSERS.enum(String(b.expect), b) : Number(b.expect);
  if (value !== wanted) throw new Error(`${where}: the text says ${value} but the game data says ${wanted}`);
  if (b.min !== undefined && value < b.min) throw new Error(`${where}: starting value ${value} is below its minimum`);
  if (b.max !== undefined && value > b.max) throw new Error(`${where}: starting value ${value} is above its maximum`);
  return b;
}

let id = 0;
const seen = new Set();
let slotsTotal = 0;
let slotsBound = 0;
const out = { chapters: chapters.map((c) => ({
  title: c.chapter,
  articles: c.articles.map(([title, text, binds = []]) => {
    const words = toWords(text);
    slotsTotal += words.filter((w) => w.amendable).length;
    slotsBound += binds.length;
    const article = { id: ++id, title, words };
    if (binds.length) article.bindings = binds.map((b) => checkBinding(title, words, b, seen));
    return article;
  }),
})) };

// Safety check: rebuilding each article from its words must match the source text.
for (const c of out.chapters) for (const a of c.articles) {
  const rebuilt = a.words.map((w) => (w.glue ? '' : ' ') + w.text).join('').trim();
  const src = chapters.flatMap((x) => x.articles).find((x) => x[0] === a.title)[1].replace(/__/g, '');
  if (rebuilt.replace(/\s+/g, ' ') !== src.replace(/\s+/g, ' '))
    throw new Error(`Round-trip mismatch in "${a.title}":\n${rebuilt}\n${src}`);
}

fs.writeFileSync(path.join(__dirname, '../data/articles.json'), JSON.stringify(out, null, 1) + '\n');
console.log(`${id} articles exported; the game enforces ${slotsBound} of ${slotsTotal} highlighted words`);
