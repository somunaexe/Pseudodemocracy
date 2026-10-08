// Turns data/source/exam_questions.js into data/exam_questions.json for Godot. Re-run after changing the questions.
const fs = require('fs');
const path = require('path');
const { QUESTIONS } = require('../data/source/exam_questions.js');   // throws if its checks fail

fs.writeFileSync(path.join(__dirname, '../data/exam_questions.json'), JSON.stringify({ questions: QUESTIONS }, null, 1) + '\n');
console.log('exam_questions.json written (' + QUESTIONS.length + ' questions)');
