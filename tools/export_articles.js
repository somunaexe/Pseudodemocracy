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

let id = 0;
const out = { chapters: chapters.map((c) => ({
  title: c.chapter,
  articles: c.articles.map(([title, text]) => ({ id: ++id, title, words: toWords(text) })),
})) };

// Safety check: rebuilding each article from its words must match the source text.
for (const c of out.chapters) for (const a of c.articles) {
  const rebuilt = a.words.map((w) => (w.glue ? '' : ' ') + w.text).join('').trim();
  const src = chapters.flatMap((x) => x.articles).find((x) => x[0] === a.title)[1].replace(/__/g, '');
  if (rebuilt.replace(/\s+/g, ' ') !== src.replace(/\s+/g, ' '))
    throw new Error(`Round-trip mismatch in "${a.title}":\n${rebuilt}\n${src}`);
}

fs.writeFileSync(path.join(__dirname, '../data/articles.json'), JSON.stringify(out, null, 1) + '\n');
console.log(`${id} articles exported`);
