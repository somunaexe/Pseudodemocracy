// Turns data/source/game_data.js into data/game_data.json for Godot.
// Functions and helpers are dropped; only plain values (including derived
// ones like startMoney) are exported. Re-run after changing game_data.js.
const fs = require('fs');
const path = require('path');
const { V } = require('../data/source/game_data.js');   // throws if its sanity checks fail

fs.writeFileSync(path.join(__dirname, '../data/game_data.json'), JSON.stringify(V, null, 1) + '\n');
console.log('game_data.json written (' + Object.keys(V).filter((k) => typeof V[k] !== 'function').length + ' keys)');
