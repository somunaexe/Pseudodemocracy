// The complete card set. Single source of truth for every card.
// {GOOD} / {BAD} are replaced with the Result card names from game_data.js.
// Cards are numbered automatically in the order listed here.
const { V } = require('./game_data');
const C = V.corruption;

const fill = (s) => s.replace(/\{GOOD\}/g, V.goodCard).replace(/\{BAD\}/g, V.badCard).replace(/\{CANCEL\}/g, `\u2212${Math.abs(V.cancelledAt)}`);

const glossary = [
  ['Rival', 'A label placed on a player by a specific card. It carries no rules or restrictions of its own; it only matters when another card says \u201Cchoose a rival\u201D or similar, in which case it must target someone already carrying the label (if you have one). There is no token for it; the table just remembers.'],
  ['Loyalist', 'A player made your Loyalist by a card votes with you on anything at all, for however long that card states. The status simply expires when that duration ends, or earlier if a card says they defect. You can have more than one at a time.'],
  ['Vice', 'A second Leader created by a card. A Vice is a Leader in every way, but each term served as Vice scores \u00BD round.'],
  ['Corruption marker', `A marker placed on a player by a specific card. On your ${C.limit === 3 ? 'third' : C.limit + 'th'} marker: your roles are frozen, you can\u2019t pick ${V.goodCard} cards, and you lose ${C.pop} popularity. This lifts one of two ways \u2014 pay ${C.fine} PSD to the treasury and everything is restored (roles back, popularity drop reversed), or wait out ${C.wait} terms and the freeze lifts but your roles are gone for good and the popularity drop stays.`],
];

const settlement = [
    "The Market Women's Association endorses you. Collect 5 PSD from every woman at the table.",
    "The Old Boys' Network claims you as one of their own. Choose up to 3 men at the table. They have to either give you 50 PSD or a role-card peek, no questions asked. Refusing costs them 10 popularity.",
    "You survived a vote of no confidence. Keep this card — play it anytime to choose a rival; neither of you can coup the other for the current term when used.",
    "A diaspora relative believes in you. Collect 150 PSD from the treasury now, plus 50 PSD from the treasury every term your popularity stays above 0. The moment it drops to 0 or below, the money stops for good.",
    "You are now a doctor and cut the ribbon on a hospital that has no doctors yet. Collect 150 PSD. Any player with the Doctor role collects a third of it (50 PSD) instead of you keeping it. If there are more than 3 doctors at the table, each additional doctor beyond the third is paid 50 PSD directly from your own pocket.",
    "You appointed an unqualified friend/family member to a government position. Choose a player — they get 100 PSD, a random role card, and become your Loyalist for 3 terms, voting with you on anything at all.",
    "You crowdfunded a new flyover. Collect 200 PSD, split evenly among all other players (round up if it doesn't divide evenly). Each player may give their share, redirect it to the treasury, or lose 10 popularity instead.",
    "You've had enough — or been inspired — by how things are run. Play anytime to found an Activist union. You become its Unionizer.",
    "You're ready to stir up trouble, for the leader or against them. Play anytime to found an Agbero mob. You become its Capon.",
    "The people are ready to move — you decide how. Play anytime to found either union type.",
    "You commissioned a statue of yourself. Tacky, but tourists love it — except the Leader who secretly insulted everyone who praised it. Choose one: quietly blackmail the Leader for 100 PSD per term for the next 2 terms, or take the same amount from the treasury instead — taking it from the treasury outs the Leader, costing them 15 popularity that term.",
    "You've obtained the keys to the city. If your popularity is higher than the current Leader's, you take their role outright and they're demoted to Vice; the ousted Leader scores ½ for this term. Otherwise, you become Vice.",
    "You have a 25% Levy reduction for as long as you remain Leader. The moment you lose the seat, the reduction ends. Keep this card till you become leader or sell it.",
    "You spoke well at a 20-v-1. Choose a player as your designated heckler, they pick a {BAD} card for themselves.",
    "The youth wing backs you. Every player who's never been Leader gets +5 popularity if they publicly back you next election. Keep this card until the next election is over.",
    "A rival's scandal breaks and you didn't lift a finger. Choose a rival — they lose 15 popularity, you gain 5.",
    "You settled a scandal before the press caught it. Take a free {GOOD} card on your next performance.",
    "A bloc allied with you throws a fundraiser in your name. Collect 20 PSD per member of any union/mob currently backing you.",
    "Peace Accord — choose a rival. For the next 3 terms, if either of you is successfully couped, the other loses 10 popularity too.",
    "You found a loophole in your own tax filing. Collect 75 PSD from the treasury.",
    "An old investment matures. Collect 120 PSD.",
    "A viral video shows you helping a stranger. Gain 10 popularity.",
    "You gave a heartfelt speech nobody expected. Gain 15 popularity or 70 PSD.",
    "You have many talents. Choose any role of your choice now.",
    "You may skip your next exam entirely — you're automatically considered to have passed.",
    "You quietly sold some government equipment. Collect 90 PSD, gain a corruption marker, and lose 5 popularity.",
    "You cried at a funeral (genuinely or not). Gain 5 popularity, no one can prove otherwise.",
    "You cut your own salary for optics. Lose 50 PSD or skip your next income if you have a role. Gain 20 popularity.",
    "You may look at the top card of the {GOOD} deck and the top card of the {BAD} deck before the next player's turn, and decide for each whether to leave it or bury it at the bottom.",
    "Choose a player — they must lend you 15 PSD interest-free for 3 terms.",
    "Choose a player to publicly praise you for being trustworthy — they gain 5 popularity, you gain the Lawyer role.",
    "A Secret Agent owes you a favor. They reveal the role card of a player of your choice to you.",
    "You privatized a public asset. Collect 150 PSD, lose 10 popularity.",
    "You lived by Dr. Sebi. You're immune to being sickened for the next 2 terms.",
    "You survive a scandal unscathed. If you lose popularity next term, halve the difference. Lasts for only one term.",
    "A foreign government sends \"aid.\" Collect 100 PSD from the treasury.",
    "Choose a player with a role card — swap roles with them. They lose 5 popularity from being seen as your proxy.",
    "You throw a lavish independence day party. Gain 10 popularity, lose 50 PSD.",
    "You quietly raise your own Doctor/Lawyer fee (if you hold either role) by 20 PSD for the next term. If you don’t have any of these roles, choose to become a Doctor/Lawyer now.",
    "Choose up to 2 players — they must vote with you for the rest of the term or lose 5 popularity each.",
    "Your cousin abroad wires funds. Collect 80 PSD.",
    "You may reroll one Result card draw next term, once. The first card you picked goes to a player of your choice.",
    "You donate to charity live on camera. Lose 30 PSD, gain 15 popularity.",
    "Choose a Rival — they lose their next Result card draw entirely but still have to perform.",
    "Your popularity floor for the next term can't go below what it is right now.",
    "Petrol subsidy windfall. Collect 60 PSD per term for the next 2 terms.",
    "You're declared a national hero. Gain 20 popularity and immunity from being CANCELLED this term even if you'd otherwise cross {CANCEL}.",
    "You qualified for benefits. Skip the next tax collection.",
    "You declared a public holiday in your own honor. Everyone else loses a term's income; you don't.",
    "Your appointee turns out to be under investigation. ASK ANOTHER PLAYER OF YOUR CHOICE TO READ THE REST FOR YOU — you and the player both gain 20 popularity and 100 PSD compensation from the treasury. Your appointee beat the case.",
  ];

const scandal = [
    "The women playing the game are owed an apology. Lose 5 popularity every term for up to 4 terms, or until you publicly apologize to the table (roleplay it — they decide if it counts), whichever comes first.",
    "The men playing the game turn on you over a leaked comment. Lose 15 popularity immediately, plus an extra 5 for each male Loyalist you have.",
    "A rival now has your number. Choose a player — for the rest of your term they may check your Doctor bead, role draw, or coup-card status once, free, without warning.",
    "You owe the player 2 seats to your left 150 PSD, payable on demand. Until fully paid, they may block any of your Result cards, any time.",
    "You spoke horribly at a university debate. You're now a Civilian. If you were already one, the first player holding a role who speaks to you becomes a Civilian instead.",
    "You paid an official to make a legal problem disappear. Pay 100 PSD and gain a corruption marker.",
    "Your appointee turns out to be under investigation. Ask another player to read this card aloud for you — you and whoever reads it, both gain a corruption marker.",
    "Nobody shows up to your rally. Lose 10 popularity; any union/mob you're in loses one member, chosen by you.",
    "Your mob got caught on camera. Disband any union/mob you're in immediately — its remaining members become your Rivals.",
    "The person seated closest to you leaked your tax returns. They choose a \"transparency fee\" — between 10 and 50 PSD (minimum of 0 if you're a Civilian) — payable to the treasury.",
    "Your flyover collapsed. Pay 200 PSD in damages, split evenly among all other players (round up if it doesn't divide evenly). Each player may accept their share, redirect it to the treasury, or reject it — in which case you keep that portion.",
    "Your tax break gets ruled illegal. Pay double your next Levy payment; if you're Leader, your Levy-setting power is suspended that term.",
    "You lost the 20-v-1. You're now a Civilian, and the player sitting opposite you takes your former role.",
    "Your embezzlement was traced — you committed it with the last person you spoke to. Snitch and split the punishment (each return 100 PSD, lose 10 popularity, gain 1 corruption marker), or take it alone (return 200 PSD, lose 20 popularity, gain 1 corruption marker).",
    "Delayed Reckoning. Place this face-down. Next time the Levy is raised (by anyone), flip it: lose 5 popularity and repay the difference to the treasury.",
    "You were caught fraternizing with the opposition. Lose 20 popularity; your current Loyalist (if any) defects immediately.",
    "Your convoy hit a pothole you were supposed to fix. Pay 50 PSD in \"repairs.\" If you ask someone else to read this card aloud for you, they help you pay half the repairs instead.",
    "Your ghost workers were discovered on the payroll. Pay 150 PSD and gain a corruption marker.",
    "A satirist made you the punchline of the year. Lose 15 popularity. Within your next 2 terms, anyone may cite this once to cancel one of your {GOOD} cards before it resolves.",
    "You tried to extend term limits and got caught. Lose 25 popularity and can’t run for the leader role for 2 terms.",
    "You overpaid for office supplies (yours). Pay 40 PSD to the treasury.",
    "An old speech resurfaces. Lose 8 popularity.",
    "Your handshake photo ages badly. Lose 5 popularity.",
    "You're sickened by an unknown source. You're sick for 1 round.",
    "Your motorcade damages a market stall. Pay 70 PSD, lose 5 popularity.",
    "Your role card is frozen for 1 term (can't use its power).",
    "A contractor overcharges you for a project. Pay 80 PSD.",
    "Your official portrait is mocked online. Lose 7 popularity.",
    "You're fined for late paperwork. Pay 50 PSD, gain a corruption marker.",
    "You skip a mandatory public event. Lose 10 popularity.",
    "Choose a player — you must repay a debt to them of 50 PSD.",
    "Choose a player — they publicly criticize you; you lose 5 popularity; They gain 5 popularity.",
    "Choose a player — they may peek at your role card once.",
    "Your car breaks down on the way to a summit. Pay 30 PSD for repairs.",
    "A leaked memo embarrasses you. Lose 10 popularity.",
    "You lose your next {GOOD} card draw entirely.",
    "You bounce a check to a vendor. Pay 45 PSD, gain a corruption marker.",
    "Your response to a crisis lands flat. Lose 12 popularity.",
    "Choose a player — they collect 70 PSD from you as \"compensation\" and gain a corruption marker themselves for accepting it.",
    "You can't attempt a coup for 1 term.",
    "Bad investment. Lose 60 PSD.",
    "You're forced to publicly refund a donor. Pay 40 PSD, lose 5 popularity.",
    "A rival gets to check your coup-card status for free, once.",
    "Whoever is marking your exam answers next round can manipulate them to affect the score.",
    "You lose a bet made in confidence. Pay 35 PSD.",
    "Choose a player of your choice — you must pay them 30 PSD as a \"peace offering,\" and you lose 7 popularity for looking weak.",
    "You have been infected with COVID and are sick for 3 terms. The two closest players to your sides and the last player you spoke to become sick for three terms. The next player who make eye contact with you while you are sick, becomes sick for 3 terms.",
    "You embezzled funds. Collect 200 PSD from the treasury. The leader can stay quiet, split the money with you, or expose you, giving you a corruption marker.",
    "You missed your own policy announcement. Skip your next income collection.",
    "You draw an extra Performance card for your next turn.",
  ];

const performance = [
    "You have a useless product you desperately need to sell. Choose another player and convince them to buy it from you in 45 seconds — you decide the product and price.",
    "Your neighbour (on your right) claims you damaged their property, demanding 100 PSD. You each explain your side; the leader decides who's telling the truth. Winner gets 100 PSD from the loser.",
    "You're a government official. A wealthy citizen offers 300 PSD to approve something benefiting their business. Act it out; the decision is yours.",
    "You've obtained confidential government info and release it publicly, explaining why. The leader has 60 seconds to respond; citizens vote on whether the response was convincing.",
    "You and the 4th player in this round are fighting for custody of your children. Each parent argues their case; the leader judges. Winner: 150 PSD. Loser: 50 PSD legal costs.",
    "You're up for re-election. Pick two players and pitch yourself to each in 30 seconds — they vote publicly for or against you.",
    "A journalist is investigating your last term. Answer three rapid-fire questions honestly, or lie convincingly — the table votes on whether they believed you.",
    "You need a loan. Convince another player to lend you 200 PSD — you pitch, they set the interest.",
    "Your Doctor gave you a convenient \"condition\" that excuses you from your next exam. Sell it to the table in 30 seconds.",
    "You're accused of election fraud. Defend yourself for 60 seconds — believed: +10 popularity; not: −15.",
    "A rival union wants your backing. Their Unionizer/Capon pitches you for 30 seconds — you decide.",
    "You're unveiling a new national policy. Sell it to the table like it's brilliant, even if you just invented it.",
    "Mediate a live dispute between two other players in 60 seconds. Succeed (table vote) and both pay you 25 PSD.",
    "A whistleblower is threatening to expose you. Negotiate a payoff, live, at the table.",
    "You're inaugurating a project that doesn't exist yet. Describe it convincingly enough nobody asks for receipts.",
    "Debate a rival: pick a topic, 30 seconds each side, table votes a winner.",
    "Convince the Lawyer to draft your will for free.",
    "A citizen confronts you over broken promises. Talk your way out in 30 seconds — table decides if it worked.",
    "Pitch your union/mob to an unaffiliated player. They accept or refuse based on your pitch alone.",
    "It's tax season and someone's dodging. Interrogate a player of your choice for 30 seconds — table decides guilt.",
    "You're launching a new slogan for your campaign. Pitch it to the table in 30 seconds, as if it's the best thing they've ever heard.",
    "You've been caught lying under oath — explain yourself to the table without admitting fault, in 45 seconds.",
    "Choose a player — accuse them of a crime you just made up, on the spot, and make it believable.",
    "You're giving a eulogy for a policy that failed. Make the table laugh or cry, your choice.",
    "You're unveiling your \"5-year plan.\" Describe it in vivid, over-the-top detail for 30 seconds.",
    "Choose a player — negotiate a trade deal with them live, out loud, until one of you gives in.",
    "You're being interviewed for a documentary about your legacy. Answer three questions the table asks you, honestly or not.",
    "Announce your resignation, then immediately announce you've changed your mind. Sell both moments.",
    "Choose two players — mediate an argument between them that you invent on the spot.",
    "You're addressing rumors of your declining health. Convince the table you're fine.",
    "Give an acceptance speech for an award you clearly don't deserve.",
    "Choose a player — challenge them to a public arm-wrestle of words: fastest to concede loses 20 PSD.",
    "You're launching a national holiday named after yourself. Justify it to the table.",
    "Explain, with a straight face, why the economy is actually doing great.",
    "Choose a player — apologize to them for something you didn't do, and make it sound sincere.",
    "You're being roasted by the press. Respond to three imagined headlines the table shouts at you.",
    "Deliver a farewell address as if you're leaving office forever (you're not).",
    "You have just been arrested for drugtrafficking and have to defend yourself in court.",
    "Convince the table that a recent scandal was actually a \"misunderstanding.\"",
    "Pitch a new tax to the table and get them to believe it's for their own good.",
    "Choose a player — try to recruit them into your union/mob with a single sentence.",
    "You're cutting the ribbon on something that doesn't exist yet. Sell the vision.",
    "Give a toast at your own inauguration.",
    "Choose a player — settle an old score with them, out loud, in front of everyone.",
    "You're being asked to resign. Refuse, dramatically, for 30 seconds.",
    "Explain your biggest failure as a triumph.",
    "Choose two players — get them to publicly disagree with each other for your benefit.",
    "You're announcing a new currency named after yourself. Convince the table it's a good idea.",
    "Deliver a campaign promise you have no intention of keeping — sell it anyway.",
    "Choose a player — convince them to publicly endorse you, on the spot.",
  ];

// EFFECTS the game applies by itself when a Settlement or Scandal card is drawn. A card is found by the
// start of its text (the export fails if that matches no card or more than one). Only effects on the
// drawer alone are listed: psd is money to (+) or from (-) the treasury, popularity moves the base,
// sick makes the drawer sick for that many rounds and immune makes them immune to being sickened for that many,
// no_coup bars the drawer from attempting a coup for that many rounds.
// Cards not listed here are read out to the table and carried out by the table, as before.
// The export also checks that every amount appears as a number in the card's own text.
const effects = {
  settlement: [
    ['You found a loophole in your own tax', { psd: 75 }],
    ['An old investment matures', { psd: 120 }],
    ['A viral video shows you helping', { popularity: 10 }],
    ['You cried at a funeral', { popularity: 5 }],
    ['You privatized a public asset', { psd: 150, popularity: -10 }],
    ['You quietly sold some government equipment', { psd: 90, popularity: -5, marker: 1 }],
    ['A foreign government sends', { psd: 100 }],
    ['You throw a lavish independence day party', { psd: -50, popularity: 10 }],
    ['Your cousin abroad wires funds', { psd: 80 }],
    ['You donate to charity live on camera', { psd: -30, popularity: 15 }],
    ['You lived by Dr. Sebi', { immune: 2 }],
    // collect_each: every other player of that gender pays the drawer that much (what they can't pay becomes debt).
    ['The Market Women', { collect_each: { gender: 'female', amount: 5 } }],
    // Cards the drawer KEEPS to play later ("play anytime"): keep: true. A union card founds a union when played;
    // the player becomes its Unionizer (an Agbero mob's Capon). The third lets them choose which when they play it.
    // Rival cards: who 'rival' offers the drawer's rivals, or anyone if they have none; the one chosen becomes their rival.
    // truce: the two can't coup each other until the round ends; accord: for that many rounds, if either is couped the
    // other loses that much popularity; skip_draw: the chosen player's next Settlement or Scandal draw is lost.
    // loyalist: the chosen player becomes the drawer's Loyalist for that many rounds (who 'loyalist' offers the players that
    // can be); target_role 'random' gives them a random role card they can hold.
    ['You appointed an unqualified friend', { choose: { kind: 'player', who: 'loyalist' }, target: { psd: 100 }, target_role: 'random', loyalist: { rounds: 3 } }],
    // keys: the keys to the city. The drawer takes the Leader's role if they are more popular (the Leader becomes Vice), else becomes Vice.
    ["You've obtained the keys to the city", { keys: true }],
    // favor: a Secret Agent shows the drawer the role cards of the chosen player (whether each has a coup sticker).
    ['A Secret Agent owes you a favor', { choose: { kind: 'player', who: 'has_role' }, favor: true }],
    ['You survived a vote of no confidence', { keep: true, truce: true, choose: { kind: 'player', who: 'rival' } }],
    ["A rival's scandal breaks", { popularity: 5, choose: { kind: 'player', who: 'rival' }, target: { popularity: -15 } }],
    ['Peace Accord', { choose: { kind: 'player', who: 'rival' }, accord: { rounds: 3, loss: 10 } }],
    ['Choose a Rival', { choose: { kind: 'player', who: 'rival' }, skip_draw: true }],
    ["You've had enough", { keep: true, found_union: 'activist' }],
    ["You're ready to stir up trouble", { keep: true, found_union: 'agbero' }],
    ['The people are ready to move', { keep: true, choose: { kind: 'option', options: [{ label: 'Found an Activist union', found_union: 'activist' }, { label: 'Found an Agbero mob', found_union: 'agbero' }] } }],
    // Cards that ask the drawer to choose. `choose` is { kind: 'option' | 'role' | 'player', ... }:
    //   option  one of `options`, each its own effects (with a label shown to the player)
    //   role    any role the drawer can be given;   player  any other player in the game
    //   player with who: 'has_role'  only players holding a role card
    // After the choice: gain_role gives the DRAWER a role ('$choice' = the role they chose),
    // swap_with: '$choice' swaps all roles with the chosen player, target: {...} applies
    // psd/popularity to the chosen player.
    ['You gave a heartfelt speech nobody expected', { choose: { kind: 'option', options: [{ label: 'Gain 15 popularity', popularity: 15 }, { label: 'Gain 70 PSD', psd: 70 }] } }],
    ['You have many talents', { choose: { kind: 'role' }, gain_role: '$choice' }],
    ['Choose a player to publicly praise you', { choose: { kind: 'player' }, target: { popularity: 5 }, gain_role: 'Lawyer' }],
    ['Choose a player with a role card', { choose: { kind: 'player', who: 'has_role' }, swap_with: '$choice', target: { popularity: -5 } }],
  ],
  scandal: [
    ['You overpaid for office supplies', { psd: -40 }],
    // marker: 1 gives the drawer a corruption marker (see Corruption). In a player choice, target.marker gives one to the chosen
    // player too, and pay_chosen is money the drawer pays the chosen player. A choice with chooser: 'leader' is made by the
    // Leader about the drawer: share 'half' takes half of the card's psd off the drawer for the Leader.
    // disband: the drawer's union or mob disperses and its other members become the drawer's rivals.
    // peek: the chosen player gets a free check of the drawer (kinds: coup = coup-card status, bead = the Doctor's bead), once,
    // for the rest of the round if round_only. peek_rival: one of the drawer's rivals (either way round), at random, gets it.
    ['A rival now has your number', { choose: { kind: 'player' }, peek: { kinds: ['bead', 'coup'], round_only: true } }],
    ['A rival gets to check your coup-card status', { peek_rival: { kinds: ['coup'] } }],
    ['Your mob got caught on camera', { disband: true }],
    // An option with `then` asks a second question after it is chosen (here: whom to snitch on); `each` is what happens to the
    // drawer AND the player then chosen.
    ['Your embezzlement was traced', { choose: { kind: 'option', options: [
      { label: 'Snitch and split it', then: { kind: 'player' }, each: { psd: -100, popularity: -10, marker: 1 } },
      { label: 'Take it alone', psd: -200, popularity: -20, marker: 1 },
    ] } }],
    // popularity_per_loyalist: the drawer loses that much more for each Loyalist of that gender; defect: one of the drawer's
    // Loyalists (chosen at random) leaves them.
    ['The men playing the game', { popularity: -15, popularity_per_loyalist: { gender: 'male', popularity: -5 } }],
    ['You were caught fraternizing', { popularity: -20, defect: true }],
    ['You paid an official', { psd: -100, marker: 1 }],
    ['Your appointee turns out', { marker: 1, choose: { kind: 'player' }, target: { marker: 1 } }],
    ['Your ghost workers', { psd: -150, marker: 1 }],
    ["You're fined for late paperwork", { psd: -50, marker: 1 }],
    ['You bounce a check', { psd: -45, marker: 1 }],
    ['Choose a player \u2014 they collect 70', { choose: { kind: 'player' }, pay_chosen: 70, target: { marker: 1 } }],
    ['You embezzled funds', { psd: 200, choose: { kind: 'option', chooser: 'leader', options: [{ label: 'Stay quiet' }, { label: 'Split the money', share: 'half' }, { label: 'Expose them', marker: 1 }] } }],
    ['An old speech resurfaces', { popularity: -8 }],
    ['Your handshake photo ages badly', { popularity: -5 }],
    ['Your motorcade damages a market stall', { psd: -70, popularity: -5 }],
    ['A contractor overcharges you', { psd: -80 }],
    ['Your official portrait is mocked online', { popularity: -7 }],
    ['You skip a mandatory public event', { popularity: -10 }],
    ['Your car breaks down on the way to a summit', { psd: -30 }],
    ['A leaked memo embarrasses you', { popularity: -10 }],
    ['Your response to a crisis lands flat', { popularity: -12 }],
    ['Bad investment', { psd: -60 }],
    ["You're forced to publicly refund a donor", { psd: -40, popularity: -5 }],
    ['You lose a bet made in confidence', { psd: -35 }],
    ["You're sickened by an unknown source", { sick: 1 }],
    ["You can't attempt a coup", { no_coup: 1 }],
  ],
  // Performance cards that change how the turn is played:
  //   pitch   a rival union's Unionizer pitches the performer, who may join it (the performer decides)
  //   debate  the performer challenges a rival to a debate that the table judges
  performance: [
    ['A rival union wants your backing', { pitch: true }],
    ['Debate a rival', { debate: true }],
  ],
};

module.exports = {
  glossary,
  settlement: settlement.map(fill),
  scandal: scandal.map(fill),
  performance: performance.map(fill),
  effects,
};
