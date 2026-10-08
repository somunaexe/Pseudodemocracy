// The prepared exam questions. The Leader picks 5 to 10 of them and says, for each, what THEIR true answer is; the takers then
// guess. They are all about the Leader as a person, so the ones who know them best pass. Plain data: a question and 2 or 3
// options. Re-run `node tools/export_exam_questions.js` after changing this file (it checks the rules below).
const QUESTIONS = [
  ['What does the Leader do first when the power goes out?', ['Starts the generator', 'Lights a candle and complains', 'Goes straight to sleep']],
  ['Which meal does the Leader order first at a buka?', ['Jollof rice', 'Pounded yam and egusi', 'Suya']],
  ['How does the Leader take their tea?', ['With plenty of sugar', 'With no sugar', 'The Leader does not drink tea']],
  ['What would the Leader do with an unexpected 50,000 naira?', ['Save it', 'Spend it the same day', 'Share it with friends']],
  ['Where would the Leader rather spend a holiday?', ['At the beach', 'In the village', 'Abroad']],
  ['How does the Leader get to a wedding?', ['Early', 'Exactly on time', 'Two hours late']],
  ['What does the Leader do in traffic?', ['Stays calm and plays music', 'Hoots endlessly', 'Looks for a shortcut']],
  ['Which football team does the Leader support?', ['A Nigerian club', 'A European club', 'None, the Leader hates football']],
  ['What is the Leader\'s favourite way to relax?', ['Watching Nollywood', 'Sleeping', 'Meeting friends']],
  ['How does the Leader answer a call from an unknown number?', ['Picks up straight away', 'Lets it ring out', 'Sends a text instead']],
  ['What does the Leader do when a bill arrives?', ['Pays it at once', 'Pays on the last day', 'Pretends not to see it']],
  ['Which of these would the Leader never miss?', ['Sunday service or Friday prayers', 'A good party', 'A big match']],
  ['How does the Leader eat pepper soup?', ['As hot as possible', 'Mild, please', 'The Leader does not like it']],
  ['When the Leader gets lost, what happens?', ['Asks for directions', 'Checks the map app', 'Drives around hoping']],
  ['What is the Leader\'s morning routine?', ['Up at 5, ready for the day', 'Snoozes the alarm three times', 'The Leader is a night person']],
  ['What does the Leader do at a long meeting?', ['Takes notes', 'Checks their phone', 'Quietly dozes off']],
  ['What kind of music does the Leader play most?', ['Afrobeats', 'Gospel or highlife', 'Something else entirely']],
  ['How does the Leader behave at a bargain market?', ['Haggles hard', 'Pays the first price', 'Sends a friend to bargain']],
  ['What would the Leader take to a desert island?', ['A phone charger', 'A good book', 'Plenty of food']],
  ['Who does the Leader call first with good news?', ['A parent', 'A best friend', 'Nobody, they keep it quiet']],
  ['What does the Leader do with leftover jollof?', ['Eats it cold at midnight', 'Packs it for lunch', 'Gives it away']],
  ['How does the Leader handle a heated argument?', ['Shouts back', 'Walks away', 'Cracks a joke']],
  ['What is the Leader\'s best trait, in their own opinion?', ['Generosity', 'Intelligence', 'Humour']],
  ['Which would the Leader pick for a Saturday night?', ['A house party', 'A quiet dinner', 'An early night']],
  ['How does the Leader dress for a special occasion?', ['In full traditional attire', 'In a sharp suit', 'In whatever is clean']],
  ['What does the Leader say when asked "How far?"', ['"I dey"', '"Fine, thank you"', '"Don\'t ask me"']],
  ['What does the Leader do when they win a game?', ['Celebrates loudly', 'Stays modest', 'Reminds everyone for a week']],
  ['What does the Leader do when they lose a game?', ['Demands a rematch', 'Blames the rules', 'Laughs it off']],
  ['Which drink does the Leader choose?', ['Zobo or chapman', 'Malt', 'Plain water']],
  ['How early does the Leader get to the airport?', ['Three hours before', 'One hour before', 'Just as the gate closes']],
  ['How does the Leader take a photo?', ['Smiling widely', 'Serious and posed', 'Never, they hide from cameras']],
  ['What would the Leader do first if they became president for a day?', ['Fix the roads', 'Declare a holiday', 'Give themselves a raise']],
  ['What does the Leader do with a chain message?', ['Forwards it to everyone', 'Reads it and ignores it', 'Deletes it at once']],
  ['What is the Leader\'s favourite snack?', ['Puff puff', 'Suya', 'Plantain chips']],
  ['How does the Leader feel about Mondays?', ['Ready for them', 'Dreads them', 'Does not notice them']],
  ['What does the Leader do when a friend asks for a loan?', ['Lends it with a smile', 'Makes an excuse', 'Gives less and says it is a gift']],
  ['Which sound does the Leader find the most annoying?', ['A neighbour\'s generator', 'Loud phone calls on the bus', 'Someone chewing loudly']],
  ['How does the Leader fix something that breaks at home?', ['Does it themselves', 'Calls an expert', 'Leaves it broken']],
  ['What is the Leader\'s biggest fear?', ['Heights', 'Public speaking', 'Cockroaches']],
  ['How does the Leader sleep?', ['Like a log', 'Light and restless', 'With the TV on']],
  ['What would the Leader do with a free afternoon?', ['Nap', 'Cook for friends', 'Run errands']],
  ['Which line would the Leader most likely say?', ['"It is not my fault"', '"I told you so"', '"Let me handle it"']],
  ['How does the Leader react to spoilers?', ['Furious', 'Does not care', 'Spoils things for others']],
  ['What does the Leader do on a Sunday afternoon?', ['Rests after a big lunch', 'Visits family', 'Catches up on work']],
  ['What is the Leader\'s phone like?', ['Spotless and organised', 'Full of unread messages', 'Always at 1% battery']],
  ['What would the Leader haggle over most?', ['Fruits at the market', 'A taxi fare', 'The price of a new phone']],
];

// The rules the game relies on, checked when the data is exported.
const MIN_OPTIONS = 2, MAX_OPTIONS = 3, TEXT_MAX = 200, MIN_QUESTIONS = 30;
const seen = new Set();
for (const [text, options] of QUESTIONS) {
  if (typeof text !== 'string' || !text || text.length > TEXT_MAX) throw new Error('bad exam question text: ' + text);
  if (seen.has(text)) throw new Error('duplicate exam question: ' + text);
  seen.add(text);
  if (!Array.isArray(options) || options.length < MIN_OPTIONS || options.length > MAX_OPTIONS) throw new Error('an exam question needs 2 or 3 options: ' + text);
  if (new Set(options).size !== options.length) throw new Error('duplicate options in: ' + text);
  for (const option of options) if (typeof option !== 'string' || !option || option.length > TEXT_MAX) throw new Error('bad option in: ' + text);
}
if (QUESTIONS.length < MIN_QUESTIONS) throw new Error('the bank needs at least ' + MIN_QUESTIONS + ' questions');

module.exports = { QUESTIONS: QUESTIONS.map(([text, options]) => ({ text, options })) };
