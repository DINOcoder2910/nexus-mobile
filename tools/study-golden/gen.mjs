// Writes Packages/NexusCore/Tests/NexusCoreTests/StudyGolden.swift: what the laptop's renderer/src/studyfsrs.js and studydeck.js give
// for a set of inputs (fixed ones and seeded random ones), so StudyTests can check the iPhone and iPad port gives the same.
// Run from this folder with a nexus checkout beside nexus-mobile (and its node_modules, for `yaml`):  node gen.mjs ../../../nexus
import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const F = await import(pathToFileURL(path.join(nexus, 'renderer/src/studyfsrs.js')));
const D = await import(pathToFileURL(path.join(nexus, 'renderer/src/studydeck.js')));
const out_path = new URL('../../Packages/NexusCore/Tests/NexusCoreTests/StudyGolden.swift', import.meta.url);

// a seeded random (mulberry32), so the cases are the same each run
let seed = 20261112;
const rnd = () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));
const pick = (l) => l[Math.floor(rnd() * l.length)];
const MIN = 60000, HOUR = 3600000, DAY = 86400000;
const card = (c) => [c.state, c.due, c.s, c.d, c.reps, c.lapses, c.last];

const out = { zones: {}, rng: [], check: [], formula: [], decks: [], mcq: [], flip: [], review: {} };

// ---- FSRS, in two time zones (the day starts at 04:00 local, as the laptop's default)
for (const tz of ['UTC', 'Asia/Kolkata', 'America/New_York']) {
  process.env.TZ = tz;
  const z = { runs: [], dayStart: [], words: [], preview: [] };
  const T0 = Date.UTC(2026, 10, 3, 9, 0);
  for (let r = 0; r < 80; r++) {
    let c = F.newCard(); let now = T0 + ri(0, 48) * HOUR + ri(0, 59) * MIN;
    const steps = [];
    const n = ri(1, 10);
    for (let i = 0; i < n; i++) {
      const g = pick([1, 2, 3, 3, 3, 4]);
      c = F.review(c, g, now);
      steps.push({ g, now, card: card(c) });
      // the next review: on time, early, late, the same day, a few minutes on
      const k = rnd();
      now = k < 0.35 ? Math.max(now + MIN, c.due) : k < 0.55 ? c.due + ri(1, 30) * DAY : k < 0.7 ? now + ri(1, 600) * MIN : k < 0.85 ? Math.max(now + MIN, c.due - ri(0, 3) * DAY) : now + ri(1, 120) * DAY + ri(0, 23) * HOUR;
    }
    z.runs.push(steps);
  }
  for (let i = 0; i < 40; i++) { const a = T0 + ri(-200, 400) * DAY + ri(0, 1439) * MIN, b = a + ri(0, 90) * DAY + ri(-1439, 1439) * MIN; z.dayStart.push([a, F.dayStartOf(a), b, F.daysBetween(a, b), ri(0, 40), 0]); const L = z.dayStart[z.dayStart.length - 1]; L[5] = F.dueOnDay(a, L[4]); }
  for (let i = 0; i < 30; i++) { const now = T0 + ri(0, 100) * DAY + ri(0, 1439) * MIN; const due = now + pick([ri(1, 59) * MIN, ri(1, 23) * HOUR, ri(1, 30) * DAY, ri(31, 3000) * DAY]); z.words.push([now, due, F.untilWords(due, now)]); }
  for (const steps of z.runs.slice(0, 20)) { const last = steps[steps.length - 1]; const c = { ...F.newCard(), state: last.card[0], due: last.card[1], s: last.card[2], d: last.card[3], reps: last.card[4], lapses: last.card[5], last: last.card[6] }; const now = c.due + ri(-2, 5) * HOUR; z.preview.push([last.card, now, F.preview(c, now).map((x) => [x.due, x.inText])]); }
  out.zones[tz] = z;
}
process.env.TZ = 'UTC';
out.inWords = [MIN, 10 * MIN, 30 * 1000, 3 * HOUR, 23 * HOUR + 40 * MIN, DAY, 16 * DAY, 45 * DAY, 90 * DAY, 400 * DAY, 3000 * DAY].map((ms) => [ms, F.inWords(ms)]);
out.dayWords = [1, 2, 30, 31, 45, 200, 364, 365, 800].map((d) => [d, F.dayWords(d)]);
out.intervals = [0.1, 0.4, 1, 2.5, 3.173, 15.69, 100, 1000, 99999].map((s) => [s, F.intervalDays(s)]);
out.retrievability = [[0, 3], [1, 3], [10, 10], [30, 2.5], [5, 0]].map(([d, s]) => [d, s, F.retrievability(d, s)]);

// ---- the seeded random the laptop shuffles with
for (const s of ['', 'a', 's1|sulfate|forward', 'practice|x', 'flip|1762160400000|año', '😀 emoji', 'Ünïcödé']) { const r = D.rngOf(s); out.rng.push([s, [r(), r(), r(), r(), r()]]); }

// ---- typed answers (the laptop's unit table, then random spellings of formulas)
const CHECK = [
  ...['SO4 2-', 'SO4^2-', 'SO42-', 'SO4-2', 'SO4 -2', 'SO4^(2-)', 'SO4(2-)', 'so4 2-', 'SO₄²⁻', ' SO4  2 - ', 'SO4 2+', 'SO4', 'SO3 2-', '', 'SO₄⁻²', 'SO4²⁻', 'SO4 −2', 'SO4 – 2'].map((t) => [t, 'SO₄²⁻', []]),
  ...['OH-', 'OH 1-', 'OH^-', 'OH-1', 'oh-', 'O-', 'OH⁻', 'OH', 'OH+'].map((t) => [t, 'OH⁻', []]),
  ['NH4+', 'NH₄⁺', []], ['H3O+', 'H₃O⁺', []], ['O22-', 'O₂²⁻', []], ['Cr2O72-', 'Cr₂O₇²⁻', []], ['PO43-', 'PO₄³⁻', []], ['CH3COO-', 'CH₃COO⁻', []], ['Fe3+', 'Fe³⁺', []], ['Fe 3+', 'Fe³⁺', []], ['Fe+3', 'Fe³⁺', []], ['fe3+', 'Fe³⁺', []],
  ['Strong  acid.', 'strong acid', []], ['strong', 'strong acid', ['strong']], ['weak acid', 'strong acid', []], ['Sulphate', 'sulfate', []], ['hydronium', 'oxonium (hydronium)', ['oxonium', 'hydronium']],
  ['Co', 'CO', []], ['HCl', 'HCl', []], ['hcl', 'HCl', []], ['OH', 'OH⁻', []], ['NO3', 'NO₃⁻', []], ['SO42', 'SO₄²⁻', []], ['ClO', 'ClO⁻', ['ClO -']], ['clo', 'ClO⁻', ['ClO -']], ['ClO-', 'ClO⁻', ['ClO -']], ['NH4', 'NH₄⁺', []], ['NH4-', 'NH₄⁺', []],
  ['hydrogen carbonate', 'hydrogencarbonate', []], ['Dihydrogen phosphate', 'dihydrogenphosphate', []], ['hydrogen-carbonate ion', 'hydrogencarbonate', []], ['hydroxide ion', 'hydroxide', []], ['hydroxide', 'hydrogencarbonate', []], ['aluminium', 'aluminum', []], ['Hydrogen carbonate ion.', 'hydrogencarbonate', []],
  ['el perro', 'el perro', []], ['El Perro!', 'el perro', []], ['año', 'ano', []], ['no', 'no', []], ['  ', 'x', []], ['x', '', ['x']], ['(NH4)2SO4', '(NH₄)₂SO₄', []], ['[Fe(CN)6]3-', '[Fe(CN)₆]³⁻', []], ['Ca2+', 'Ca²⁺', []], ['Ca+2', 'Ca²⁺', []], ['Ca 2 +', 'Ca²⁺', []],
];
const FORMULAS = ['SO₄²⁻', 'OH⁻', 'NH₄⁺', 'Cr₂O₇²⁻', 'Fe³⁺', 'Cl⁻', 'MnO₄⁻', 'CO₃²⁻', 'HCO₃⁻', 'H₂PO₄⁻', 'O²⁻', 'Al³⁺', 'NO₂⁻', 'HCl', 'CH₄', 'CO'];
const plainOf = (f) => f.replace(/[₀-₉]/g, (c) => String('₀₁₂₃₄₅₆₇₈₉'.indexOf(c))).replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹]/g, (c) => String('⁰¹²³⁴⁵⁶⁷⁸⁹'.indexOf(c))).replace('⁺', '+').replace('⁻', '-');
for (let i = 0; i < 150; i++) {
  const f = pick(FORMULAS); let t = plainOf(f);
  const m = /^(.*?[A-Za-z)])(\d*)([+-])$/.exec(t);
  if (m && rnd() < 0.7) { const d = m[2], s = m[3]; t = m[1] + pick([' ' + d + s, '^' + d + s, d + s, s + d, ' ' + s + d, '(' + d + s + ')', '^(' + d + s + ')', ' ' + d + ' ' + s]); }
  if (rnd() < 0.15) t = t.toLowerCase();
  if (rnd() < 0.1) t = t.slice(0, -1);
  if (rnd() < 0.1) t = '  ' + t + ' ';
  CHECK.push([t, pick([f, f, f, pick(FORMULAS)]), []]);
}
for (const [t, a, acc] of CHECK) out.check.push([t, a, acc, D.checkAnswer(t, a, acc)]);
out.formula = ['OH⁻', 'ClO -', 'HCl', 'SO4^2-', 'Co', 'Sulphate', 'strong acid', 'hydroxide', 'H₂O', 'NaCl', 'Fe³⁺', 'ion', 'Mg', 'Iron', 'NH4 +', 'x', '', 'CH3COOH', 'el perro'].map((s) => [s, D.looksFormula(s)]);

// ---- decks
const DECKS = [
  ['ions', `id: ions\ntitle: Ions\nreversible: true\ncolumns:\n- {key: name, label: Ion}\n- {key: formula, label: Formula}\ngroups:\n- {id: s, title: Sulfur}\ncards:\n- id: sulfate\n  group: s\n  fields: {name: sulfate, formula: SO₄}\n  front: sulfate\n  back: SO₄²⁻\n  accept: [SO4 2-]\n- id: sulfite\n  group: s\n  front: sulfite\n  back: SO₃²⁻\n- id: oxonium\n  front: oxonium (hydronium)\n  back: H₃O⁺\n- id: sulfate\n  front: x\n  back: y\n- id: hydroxide\n  front: hydroxide\n  back: OH⁻\n- id: nitrate\n  front: nitrate\n  back: NO₃⁻\n- id: carbonate\n  group: c\n  front: carbonate\n  back: CO₃²⁻\n  accept_reverse: [carbonate ion]\n  note: "  trigonal planar  "\n- id: ammonium\n  group: c\n  front: ammonium\n  back: NH₄⁺\n  fields: {other: azanium}\n- {id: nofront, back: x}\n- {front: noid, back: y}\n`],
  ['ab', `id: ab\ntitle: AB\ncards:\n- {id: g1, front: group 1 hydroxides, back: strong base, covers: [LiOH, NaOH, KOH], options: [strong acid, weak acid, strong base, weak base]}\n- {id: hcl, front: HCl, back: strong acid, options: [strong acid, weak acid, strong base, weak base]}\n- {id: hf, front: HF, back: weak acid, options: [strong acid, weak acid, strong base, weak base]}\n- {id: carb, front: carboxylic acids, back: weak acid, covers: [ethanoic acid], options: [strong acid, weak acid, strong base, weak base]}\n- {id: conj, front: conjugate base of NH₄⁺, back: NH₃, options: [NH₃, NH₂⁻, NH₅⁺, NH₄], level: common}\n- {id: lone, front: lone option, back: yes, options: [maybe]}\n- {id: two, front: two options, back: B, options: [A, C], level: extra}\n`],
  ['es-casa', `id: es-casa\ntitle: La casa\nflip: true\nreversible: true\nlanguage: spanish\nkind: vocab\nunit: "1.2"\ncards:\n- {id: casa, front: la casa, back: the house, tags: [home, nouns], example: Mi casa es tu casa., added: 2026-11-01}\n- {id: no, front: "no", back: "no", tags: [basics]}\n- {id: si, front: sí, back: "yes", tags: [basics]}\n- {id: 3, front: 3, back: tres, tags: [numbers, basics]}\n- {id: true-card, front: true, back: verdadero}\n- {id: cocina, front: la cocina, back: the kitchen, tags: [home]}\n- {id: perro, front: el perro, back: the dog}\n`],
  ['empty-cols', `title: No columns\ncards:\n- {id: a, front: A, back: one}\n- {id: b, front: B, back: two, group: g}\ngroups:\n- {id: g, title: Gee}\n- {title: no id}\nsources:\n- IB data booklet\n- {title: Textbook, url: "https://example.com"}\n- {url: "https://x.y"}\n`],
  ['broken', 'cards: 3'], ['bad-yaml', 'cards: [\n'], ['nocards', 'title: x\n'],
];
for (const [id, y] of DECKS) {
  const r = D.parseDeck(y, id);
  out.decks.push({ id, yaml: y, ok: r.ok, problems: r.problems || [], deck: r.ok ? { ...r.deck, practice: undefined } : null, sections: r.ok ? D.deckSections(r.deck).map((s) => [s.id, s.title, s.cards.map((c) => c.id)]) : null,
    sides: r.ok ? r.deck.cards.map((c) => [c.id, D.sideOf(c, 'forward'), D.sideOf(c, 'reverse')]) : null, tags: r.ok ? D.tagsOf(r.deck).map((t) => [t.tag, t.n]) : null });
  if (!r.ok) continue;
  for (const c of r.deck.cards) for (const dir of r.deck.reversible ? ['forward', 'reverse'] : ['forward']) for (const s of ['s1', 'abc', '1762160400000' + ri(0, 9)]) {
    const m = D.mcqOptions(c, r.deck, dir, s); out.mcq.push([id, c.id, dir, s, m.options, m.correct]);
  }
  if (r.deck.flip) for (const c of r.deck.cards) for (const show of ['es', 'en', 'mix']) for (const s of ['1', '2', '1762160400000']) { const f = D.flipSide(c, show, s); out.flip.push([id, c.id, show, s, f.prompt, f.answer, f.flipped]); }
}

// ---- review.yaml: what the laptop writes, and what it reads back
const T0 = Date.UTC(2026, 10, 3, 9, 0);
let c2 = F.review(F.review(F.newCard(), 3, T0), 3, T0 + 10 * MIN);
const lapse = F.review(c2, 1, c2.due);
const decks = { ions: { forward: { sulfate: { ...c2, log: [[T0, 3, 'type'], [T0 + 10 * MIN, 3, 'type']] }, 'odd key': { ...lapse, log: [] }, yes: { ...F.newCard(), log: [] }, '12': { ...c2, log: [[T0, 4, '']] } }, reverse: { 'oxonium': { ...lapse, log: [[T0, 1, 'mcq']] } } }, 'es casa': { forward: { casa: { ...c2, s: 3, d: 5.5, log: [[T0, 3, 'flip']] } } }, empty: { forward: {} }, 'zz"q': { forward: { 'a:b': { ...c2, log: Array.from({ length: 45 }, (_, i) => [T0 + i * DAY, 3, 'flip']) } } } };
out.review.text = D.serializeReview(decks);
const back = D.parseReview(out.review.text);
out.review.parsed = back.decks;
const odd = `# hand-edited\ndecks:\n  ions:\n    forward:\n      a: {state: review, due: 2026-11-03T09:00:00.000Z, s: "2.5", d: 4, reps: 3, lapses: 0, last: 2026-11-01T09:00Z, log: [[2026-11-01T09:00Z, 3, type], [bad], [2026-11-02T10:00Z, 2]]}\n      b: {state: weird, due: , s: x}\n      c: 7\n    sideways:\n      d: {state: review}\n  broken: 3\n`;
const op = D.parseReview(odd);
out.review.odd = { text: odd, ok: op.ok, decks: op.decks };
out.review.empty = [['', D.parseReview('').ok], ['decks: [', D.parseReview('decks: [').ok], ['decks:\n', D.parseReview('decks:\n').ok]];

const json = JSON.stringify(out);
if (json.includes('"##') || json.includes('\\##')) throw new Error('delimiter');
fs.writeFileSync(out_path,
`// Generated from the laptop's renderer/src/studyfsrs.js and studydeck.js (nexus main, f5098ea): what they give for these inputs.
// StudyTests checks the iPhone and iPad port gives the same. Regenerate: node tools/study-golden/gen.mjs <nexus checkout>.
let studyGolden = ##"${json}"##
`);
console.log(json.length, Object.values(out.zones).map((z) => z.runs.length), out.check.length, out.mcq.length, out.flip.length);
