// Writes Packages/NexusCore/Tests/NexusCoreTests/SheetsGolden.swift: what the laptop's renderer/src/studysheets.js, studyupload.js,
// studyread.js and the units and Practice classifying parts of studydeck.js give for a set of inputs, so SheetsTests can check the
// iPhone and iPad port (NexusCore StudySheets.swift, StudyUpload.swift, StudyUnits.swift) gives the same.
// Run from this folder with a nexus checkout beside nexus-mobile (and its node_modules, for `yaml`):  node gen-sheets.mjs ../../../nexus
import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const imp = (p) => import(pathToFileURL(path.join(nexus, 'renderer/src', p)));
const SH = await imp('studysheets.js');
const U = await imp('studyupload.js');
const RD = await imp('studyread.js');
const D = await imp('studydeck.js');
const out_path = new URL('../../Packages/NexusCore/Tests/NexusCoreTests/SheetsGolden.swift', import.meta.url);

const out = {};

// ---- names
const NAMES = [
  'Mole & Atomic Structure — MCQ, 15 mk, 23 min · 3 copies [pre-2025]', 'Periodicity — question bank, SL & HL, 47 pp · MS only [pre-2025]',
  'Energetics + Kinetics — HL test (Hess, spontaneity), no MS [pre-2025]', 'Kinetics — Paper 2 structured, 40 mk [2025]', 'Redox — HL test, 30 mk, no MS [2025]',
  'New-Syllabus Mock Exam — Kinetics & Acid–Base, 61 mk, 28 pp [2025]', 'Data-Based Set 1 — graph analysis & evaluation · MS only [pre-2025]',
  'Back Titration Calculations — practice problems, 2 pp [pre-2025]', 'Organic worked set — worked examples, 12 Q', 'Just a title', 'Bonding [2025]',
  'Équilibre — SL test, 20 mk', 'Hess — MCQ [2025]', 'Polymers — SL, HL, MCQ + structured, 50 mk, 90 min', 'Rates — quiz, 10 Q, 15 min [2025]',
  'Acids — formative assessment', 'Gas laws — revision paper, 3 pp, no MS', 'Moles — test, 20 mk [2025]', 'Mock — Paper 1 · 2 copies',
];
out.sheetName = NAMES.map((n) => [n, SH.parseSheetName(n)]);
out.kindOf = [['Redox', 'HL test'], ['Mock', ''], ['x', 'MCQ'], ['x', 'MCQ, structured'], ['x', 'structured'], ['Data-based', ''], ['x', '40 mk'], ['x', 'worked'], ['x', 'worksheet'], ['Quiz 3', ''], ['Notes', '']].map(([t, d]) => [t, d, SH.kindOf(t, d)]);
const ROLES = ['Atomic Str Worksheet MS.pdf', 'Atomic Str Worksheet.pdf', 'backtitration practice WS1 Ms.pdf', 'Kinetics and Acid base SL.pdf MS.pdf', 'X HL Paper-MCQs Markin scheme.pdf', 'X Ariahana Marked paper .pdf', 'polymers - markscheme.pdf', 'Answers.pdf', 'solutions (2).pdf', 'msg.pdf', 'Mass spec.pdf', 'Test_ms.docx', 'a/b/Quiz answer key.pdf'];
out.fileRole = ROLES.map((n) => [n, SH.fileRole(n)]);
out.unitOfFolder = ['05 Reactivity 1 — Energetics', '03 Structure 3.1 — Periodicity', '09 Multi-Topic Papers', 'Past yrs test', '11 reactivity 3.2 — Redox', 'Structure 2'].map((n) => [n, SH.unitOfFolder(n)]);
out.codesIn = ['S1.1 to S1.5.2, R2.1', 'S1, R1.1, R2.1', 'R1.2, S2.1 and S3.1.9, S3.1.10', 'SO4 and R2D2', 'R3.1–R3.4', 'R1.1-R1.3 and S2', 'x S4.1 R0.1', 'S1.12 to S1.2', 'R2.2.', 'R2.3.1 (a)'].map((t) => [t, SH.codesIn(t)]);
out.codesFromTitle = ['Kinetics + Equilibrium + Acid–Base', 'Mole & Atomic Structure', 'Bonding', 'Born-Haber cycles', 'Organic naming', 'pH and buffers', 'Rates', 'Électrochimie redox', 'Lewis VSEPR', 'nothing here'].map((t) => [t, SH.codesFromTitle(t)]);
out.stemOf = ['polymers-hl-sl-test-46marks (1).pdf', 'polymers-hl-sl-test-46marks - markscheme.pdf', 'Cumulative test - past-test questions.pdf', 'Cumulative test - markscheme.pdf', 'Test MS.pdf', 'Test.pdf', 'Équilibre_answers.PDF', 'a.b.c.pdf', 'x Marked paper.pdf'].map((n) => [n, SH.stemOf(n)]);
out.splitTop = ['HL test (Hess, spontaneity), no MS', 'a, b, (c, d), e', '', ' x '].map((s) => [s, SH.splitTop(s)]);

// ---- models
const ROOT = 'classes/chem/files/Sheets';
const FILES = [
  `${ROOT}/01 Structure 1 — Atoms/Mole & Atomic Structure — HL test, 40 mk, 60 min [pre-2025]/t MS.pdf`,
  `${ROOT}/01 Structure 1 — Atoms/Mole & Atomic Structure — HL test, 40 mk, 60 min [pre-2025]/t.pdf`,
  `${ROOT}/03 Structure 3.1 — Periodicity/Periodicity — question bank, 47 pp · MS only [pre-2025]/p MS.pdf`,
  `${ROOT}/09 Multi-Topic Papers/Kinetics + Equilibrium — SL MCQ, 30 mk, no MS [pre-2025]/k.pdf`,
  `${ROOT}/Past yrs test/S1.1 to S1.5.2, R2.1.pdf`,
  `${ROOT}/Notebook LM Found/polymers-hl-sl-test-46marks (1).pdf`,
  `${ROOT}/Notebook LM Found/polymers-hl-sl-test-46marks (1).docx`,
  `${ROOT}/Notebook LM Found/polymers-hl-sl-test-46marks - markscheme.pdf`,
  `${ROOT}/Cumulative test - past-test questions.pdf`, `${ROOT}/Cumulative test - markscheme.pdf`,
  `${ROOT}/.hidden/x.pdf`, 'classes/chem/files/booklet.pdf',
];
const NEST = ['R/Teacher/01 Structure 1 — Atoms/Moles — test, 20 mk [2025]/m.pdf', 'R/Teacher/05 Reactivity 1 — Energetics/Hess — MCQ [2025]/h.pdf', 'R/Past/old.pdf',
  'R/Teacher/05 Reactivity 1 — Energetics/Hess — MCQ [2025]/sub/h marked paper.pdf', 'R/Teacher/09 Multi-Topic Papers/Mock — Paper 2, 61 mk [2025]/mock.pdf',
  'R/Teacher/05 Reactivity 1 — Energetics/Energetics Test 1.pdf', 'R/Teacher/05 Reactivity 1 — Energetics/Energetics Test 1 MS.pdf', 'R/Teacher/05 Reactivity 1 — Energetics/zeta.pdf', 'R/Teacher/05 Reactivity 1 — Energetics/Alpha.pdf'];
const BIG = [...FILES, 'classes/chem/files/Sheets/02 Structure 2 — Bonding/Bonding — HL test, 35 mk, 50 min, 9 pp [2025]/Bonding.pdf', 'classes/chem/files/Sheets/02 Structure 2 — Bonding/Bonding — HL test, 35 mk, 50 min, 9 pp [2025]/Bonding MS.pdf',
  'classes/chem/files/Sheets/02 Structure 2 — Bonding/ionic lattice worksheet.pdf', 'classes/chem/files/Sheets/02 Structure 2 — Bonding/Ionic lattice worksheet answers.pdf',
  'classes/chem/files/Sheets/04 Reactivity 2 — Rates/Rates — quiz, 10 Q, 15 min [2025]/rates.pdf', 'classes/chem/files/Sheets/04 Reactivity 2 — Rates/rates-sl-test-20marks.pdf'];
const models = [[FILES, ROOT], [NEST, 'R'], [BIG, ROOT], [['R/03 Reactivity 3.1 — Acids/New-Syllabus Mock Exam — Kinetics & Acid–Base, 61 mk [2025]/m.pdf'], 'R'], [[], 'R']];
const M = models.map(([f, r]) => SH.buildSheets(f, r));
out.models = models.map(([files, root], i) => ({ files, root, sheets: M[i].sheets, groups: M[i].groups }));
out.forUnit = []; out.filter = []; out.sort = []; out.facts = [];
const FILTERS = [{}, { q: 'atomic mole' }, { q: 'mole & atomic' }, { q: 'ÁTOMIC' }, { kind: 'MCQ' }, { ms: 'none' }, { ms: 'only' }, { ms: 'with' }, { era: '2025' }, { era: 'unknown' }, { era: 'pre-2025' }, { level: 'HL' }, { level: 'SL' }, { unit: 'S3.1' }, { unit: 'S1' }, { unit: 'R2' }, { unit: 'S1', kind: 'Test', q: 'struct' }, { q: 'r2.1' }, { kind: 'Test', level: 'HL' }];
M.forEach((m, i) => {
  for (const [code, extra] of [['S1.4', []], ['S1', []], ['R2.3', []], ['R3.4', ['Cumulative test']], ['R1', []], ['S2.2', ['Notebook LM Found/polymers-hl-sl-test-46marks (1).pdf']], ['R2', []], ['S2', []]]) out.forUnit.push([i, code, extra, SH.sheetsForUnit(m.sheets, code, extra).map((s) => s.path)]);
  for (const f of FILTERS) out.filter.push([i, f, SH.filterSheets(m.sheets, f).map((s) => s.path)]);
  for (const by of ['unit', 'title', 'marks', 'pages']) out.sort.push([i, by, SH.sortSheets(m.sheets, by).map((s) => s.path)]);
  for (const s of m.sheets) out.facts.push([i, s.path, SH.factsLine(s), SH.msLabel(s.ms)]);
});
out.safeName = ['Chap 1-2 IBDP Chem  Set 2 MS', 'a : b', 'Paper (2019)', 'x...', ' trailing. ', 'a/b\\c', 'q?*"<>|', 'x'.repeat(200), 'tab\there', '..'].map((s) => [s, SH.safeName(s)]);
out.sheetFolderName = [{ title: 'Redox', details: 'HL test, 30 mk', ms: 'none', era: '2025' }, { title: 'Redox: a/b', details: 'question bank', ms: 'only', era: 'pre-2025', copies: 2 },
  { title: 'X', details: ['a', 'b'], ms: 'with', era: null }, { title: 'X', details: 'HL, no MS', ms: 'none' }, { title: 'X', details: '· MS only', ms: 'only' }, { title: 'X', details: '', ms: 'none', era: 'unknown' }, { title: 'Y', details: 'test,', ms: 'with' }].map((p) => [p, SH.sheetFolderName(p)]);
out.fileNameFor = [['Redox test.PDF', 'ms'], ['Redox test MS.pdf', 'ms'], ['Redox?.pdf', 'paper'], ['Kinetics MS.pdf', 'paper'], ['Kinetics - markscheme.pdf', 'paper'], ['x.pdf', 'marked'], ['answers.pdf', 'paper'], ['noext', 'ms'], ['a/b/c.docx', 'paper'], ['Test_solutions.pdf', 'paper']].map(([n, r]) => [n, r, SH.fileNameFor(n, r)]);
out.safePath = ['a/../b:c/./d', '/x//y/', 'a\\b', '', 'Teacher/05 Reactivity 1 — Energetics'].map((s) => [s, SH.safePath(s)]);
out.relIn = [[ROOT, ROOT + '/x/y.pdf'], [ROOT + '/', ROOT + '/x'], ['R', 'Q/x'], ['', 'a/b']].map(([r, p]) => [r, p, SH.relIn(r, p)]);
out.newUnitFolderName = [[0, 'Reactivity 3.2 — Redox', ROOT], [1, 'Reactivity 3.2 — Redox', 'R'], [4, 'Multi-Topic Papers', 'R'], [2, 'New: unit?', ROOT]].map(([i, l, r]) => [i, l, r, SH.newUnitFolderName(M[i].groups, l, r)]);

// ---- units, the study config, Practice classifying
out.config = ['', 'sheets: files/Chem Sheets', 'sheets: ../x', 'sheets: /a/b/\nlanguage: Spanish', 'sheets: 3', ': bad: yaml: [', 'language: es'].map((t) => [t, D.parseStudyConfig(t)]);
const UNITS = ['units:\n  - {code: S1.4, title: Moles, status: done, evidence: test 1, notes: " fine "}\n  - {code: S1.1, title: Particulate, status: partial}\n  - {code: R2.2, title: Rates, status: nope, sheets: [Cumulative test, 3]}\n  - {title: Loose one}\n  - {code: G11.1, title: Atributos}\n  - 5\n  - {code: "", title: ""}\n',
  '- {code: R1.1, title: Hess}\n- {code: X9.1, title: Other}\n', 'units: 3', 'units: [', '', 'nothing: here'];
out.units = UNITS.map((t) => { const r = D.parseUnits(t); return [t, r.ok, r.error || null, r.units, r.ok ? D.themesOf(r.units).map((g) => [g.code, g.title, g.units.map((u) => u.code)]) : null]; });
out.status = D.STATUS; out.themes = D.THEMES;
const PDECK = `id: acids
title: Acids and bases
cards:
  - {id: sa-rule, front: Strong acids, back: strong acid, options: [strong acid, weak acid, strong base, weak base], covers: [HCl, HNO3], note: Fully ionised}
  - {id: wa-rule, front: Weak acids, back: weak acid, options: [strong acid, weak acid, strong base, weak base]}
  - {id: sb-rule, front: Strong bases, back: strong base, options: [strong acid, weak acid, strong base, weak base]}
  - {id: other, front: x, back: y, options: [a, b]}
practice:
  - {id: hcl, name: hydrochloric acid, formula: HCl, answer: strong acid, rule: sa-rule, level: required}
  - {id: ch3cooh, name: ethanoic acid, formula: CH₃COOH, answer: weak acid, rule: wa-rule, level: common, note: A carboxylic acid}
  - {id: naoh, formula: NaOH, answer: strong base, rule: sb-rule}
  - {id: nh3, name: ammonia, answer: weak base, level: extra}
  - {id: hcl, name: dup, answer: strong acid}
  - {id: bad, answer: weak acid}
  - {id: noans, name: x}
  - {id: koh, name: potassium hydroxide, formula: KOH, answer: Strong base, rule: missing, level: weird}
`;
const PDECK2 = `cards:\n  - {id: a, front: A, back: one}\npractice:\n  - {id: p1, name: first, answer: red}\n  - {id: p2, name: second, answer: blue}\n  - {id: p3, name: third, answer: red}\n`;
out.practice = [];
for (const [y, id] of [[PDECK, 'acids'], [PDECK2, 'colours']]) {
  const r = D.parseDeck(y, id); const k = r.deck;
  const rounds = [];
  for (const level of ['all', 'common', 'required', 'nope']) for (const seed of ['1', '1762160400000', 'abc']) rounds.push([level, null, seed, D.practiceRound(k, { level, seed })]);
  rounds.push(['all', ['naoh', 'hcl'], '7', D.practiceRound(k, { ids: ['naoh', 'hcl'], seed: '7' })]);
  const checks = [];
  for (const p of k.practice) for (const t of ['', p.answer, p.answer.toUpperCase() + '.', 'sa', 'wa', 'sb', 'wb', 's.a', 'weak', 'strong', 'red', 'r', 'blue']) checks.push([p.id, t, D.practiceCheck(t, p), D.checkAnswer(t, p.answer)]);
  out.practice.push({ yaml: y, id, items: k.practice, options: D.practiceOptions(k), rounds, checks, rules: k.practice.map((p) => [p.id, (D.ruleOf(k, p) || {}).id || null]), levels: D.LEVELS });
}

// ---- the upload
out.folderSummary = [[0, null], [1, null], [2, null], [2, ['01 Structure 1 — Atoms', '09 Multi-Topic Papers']], [4, null], [3, []]].map(([i, f]) => [i, f, U.folderSummary(M[i], models[i][1], f)]);
const LONG = { unitFolder: 'T/05 Reactivity 1 — Energetics', title: 'A very long sheet title about enthalpy cycles and Hess law and Born Haber cycles', details: 'HL test, 40 mk, 60 min, structured questions with data', ms: 'with', era: '2025', fileName: 'An equally long original file name from the teacher about enthalpy cycles.pdf' };
out.targetPath = [
  ['classes/chemistry-hl/files/Chem Sheets', LONG, 160], ['classes/chemistry-hl/files/Chem Sheets', LONG, 120], ['classes/chemistry-hl/files/Chem Sheets', LONG, 60], ['classes/chemistry-hl/files/Chem Sheets', LONG, null],
  ['R', { ...LONG, title: 'Hess', details: 'MCQ', fileName: 'h.pdf' }, 160], ['R', { ...LONG, existingSheet: 'Hess — MCQ [2025]', fileName: 'h MS.pdf' }, 160],
  ['R', { ...LONG, existingSheet: 'An existing sheet with a long name that stays as it is', fileName: 'A file name that is long enough to be cut down.pdf' }, 120],
  ['R/', { unitFolder: '../x:y', title: 'T', details: '', ms: 'none', era: null, fileName: 'a.pdf' }, null],
  ['R', { unitFolder: '', title: 'Untitled sheet with words', details: 'many details, here, and there', ms: 'only', era: 'pre-2025', fileName: 'noext' }, 70],
].map(([r, p, max]) => [r, p, max, U.targetPath(r, p, max == null ? Infinity : max)]);
out.newUnitParent = M.map((m, i) => [i, U.newUnitParent(m, models[i][1])]);
out.sameNameFiles = [[0, 'polymers-hl-sl-test-46marks.pdf'], [0, 't.pdf'], [2, 'Bonding (2).pdf'], [0, '(1).pdf'], [1, 'h.pdf']].map(([i, n]) => [i, n, U.sameNameFiles(M[i], n)]);
const TA = 'Question 1 The oxidation state of manganese in MnO4- is +7. Question 2 Deduce the oxidation state of chromium in Cr2O7 2-. Question 3 State which species is reduced in the reaction between zinc and copper sulfate solution. Total 20 marks.';
const TB = TA.replace('Question 3', 'Question 3 (new)') + ' Extra page: balance the half equations for the reaction of iron with permanganate in acid.';
const TC = 'An unrelated text about rates of reaction and collision theory, with the Maxwell-Boltzmann distribution and activation energy.';
out.shingles = [[TA, TB], [TA, TC], [TA, TA], ['', TA], ['Ünïcödé — words, here: 1 2 3 4 5 6', 'unicode words here 1 2 3 4 5 6']].map(([a, b]) => [a, b, U.shingles(a).size, U.shingles(b).size, U.overlap(U.shingles(a), U.shingles(b)), [...U.shingles(a)].slice(0, 5)]);
out.near = [U.NEAR, U.MIN_SHINGLES, RD.DIGEST_MAX, RD.PAGE_THIN];
const PROPS = [null, { duplicates: [{ path: '01 Structure 1 — Atoms/Mole & Atomic Structure — HL test, 40 mk, 60 min [pre-2025]', why: 'same' }], unitFolder: '09 Multi-Topic Papers', role: 'paper' },
  { duplicates: [{ path: ROOT + '/Cumulative test - markscheme.pdf', why: '' }], unitFolder: 'Notebook LM Found', role: 'ms' }, { duplicates: [], unitFolder: '02 Structure 2 — Bonding' }];
out.compareCandidates = [];
for (const [i, n] of [[0, 'polymers-hl-sl-test-46marks.pdf'], [2, 'Bonding.pdf'], [2, 'x MS.pdf']]) PROPS.forEach((p, k) => out.compareCandidates.push([i, n, k, U.compareCandidates(M[i], models[i][1], p, n), U.compareCandidates(M[i], models[i][1], p, n, 2)]));
out.props = PROPS;
const PAGES = [[], [''], ['abc'], ['x'.repeat(130)], ['Question 1 '.repeat(20), '', ''], ['a'.repeat(50), 'b'.repeat(50), 'c'.repeat(50), 'd'.repeat(50)], Array.from({ length: 8 }, (_, i) => (i % 3 ? '' : 'Some words here and more words to read. '.repeat(3)))];
out.thin = PAGES.map((p) => [p, RD.isThin(p), RD.thinPages(p), RD.thinPages(p, 2)]);
out.ocrFirst = [[[1, 2, 3, 4, 5, 8], 8, 3], [[2, 7], 7, 3], [[1], 1, 3], [[4, 5], 9, 2], [[], 4, 3]].map(([need, n, k]) => [need, n, k, RD.ocrFirst(need, n, k)]);
const PAPER = [
  'IB Chemistry HL\nPaper 2\nTime: 60 minutes\nTotal 40 marks\nSection A\n1. Define the term enthalpy change. [2]\n(a) State Hess law.\n' + 'Filler words that are not key lines at all. '.repeat(30),
  'Section B\n2) Calculate the enthalpy of combustion of methane [3 marks]\n  (b) Explain why bond enthalpies give an approximate answer (2 marks)\nmore text here',
  'Question 3. Born-Haber cycle for NaCl\n3 (a) label the steps\nS1.4 and R1.2 are tested here\nunit 4 recap\n' + 'x '.repeat(400),
  'nothing key on this page at all',
  'Markscheme\n1. ΔH = q / n ✓ [1]\nTotal 40 marks',
];
out.keyLines = PAPER.map((p) => [p, RD.keyLines(p), RD.keyLines(p, 2)]);
const LONGP = Array.from({ length: 66 }, (_, i) => `Section ${i}\n` + Array.from({ length: 30 }, (_, k) => `${k + 1}. A question line with words [${k} marks]`).join('\n'));
out.digest = [[PAPER, null], [PAPER.slice(0, 1), null], [PAPER.slice(0, 2), null], [LONGP, null], [PAPER, 900], [[], null]].map(([p, cap]) => [p, cap, cap == null ? RD.digest(p) : RD.digest(p, cap)]);
out.keywords = [PAPER, LONGP.slice(0, 3), ['Kinetics and equilibrium, R2.2 R2.2', 'Equilibrium constant Kc R2.3', 'acid-base titration'], []].map((p) => [p, RD.keywordCounts(p), RD.keywordHint(p)]);
out.focusFolders = [[2, PAPER], [2, ['Bonding, covalent and ionic lattices; S2.1 S2.2']], [1, ['Hess cycles R1.2']], [0, []], [2, ['R3.1 acids']]].map(([i, p]) => [i, p, RD.focusFolders(M[i], models[i][1], p)]);
const units = 'S1.4: Moles\nR3.2: Electron transfer reactions';
out.readPrompt = [
  { fileName: 'redox test.pdf', text: RD.digest(['Question 1  Oxidation states   of Mn in MnO4-']), hint: 'R3.2 ×1', summary: U.folderSummary(M[0], ROOT), units, pages: 1 },
  { fileName: 'scan.pdf', text: '', hint: '', summary: 'x/', units: '', how: 'images', pages: 4, images: [1, 2, 4] },
  { fileName: 'scan.pdf', text: 'abc', hint: 'S1 ×2', summary: 'x/', units, how: 'ocr', pages: 2, images: [2] },
  { fileName: 'k.pdf', text: 'start of it', hint: '', summary: 'y/', units: '', how: 'text', pages: 0, images: [], note: 'Kinetics HL test, 40 marks' },
].map((o) => [o, RD.readPrompt(o)]);
const ANS = [
  [{ summary: 'A redox test', title: 'Redox', units: [{ code: 'r3.2', section: '' }], primaryUnit: 'R3.2', kind: 'test', level: 'HL', marks: 30, minutes: 45, pages: 4, hasMarkscheme: false, role: 'paper', era: '2025', unitFolder: 'Past yrs test', existingSheet: null, details: '', fileName: 'redox test.pdf', duplicates: [], notes: 'One question is off syllabus.', unsure: false, reason: '' }, 'redox test.pdf', 0, ROOT],
  [{ role: 'markscheme', unit_folder: '01 Structure 1 — Atoms', existing_sheet: 'Mole & Atomic Structure — HL test, 40 mk, 60 min [pre-2025]', file_name: 't2.pdf' }, 't2.pdf', 0, ROOT],
  [{ unitFolder: '01 Structure 1 — Atoms', existingSheet: 'Nope' }, 'a.pdf', 0, ROOT],
  [{ title: 'Mock paper', units: [{ code: 'R2.3', section: 'Section A' }, { code: 'S1.4', section: 'Section B' }, { code: 'R2.3', section: 'Section B' }], unitFolder: '01 Structure 1 — Atoms', role: 'paper' }, 'm.pdf', 0, ROOT],
  [{ unit_folder: 'Teacher/05 Reactivity 1 — Energetics' }, 'h MS.pdf', 1, 'R'], [{ unit_folder: '05 Reactivity 1 — Energetics' }, 'h MS.pdf', 1, 'R'],
  [{ unit_folder: '06 Reactivity 3.2 — Redox' }, 'h MS.pdf', 1, 'R'], [{ unit_folder: 'Past' }, 'h MS.pdf', 1, 'R'],
  [{ unit_folder: '05 Reactivity 1 — Energetics', existing_sheet: 'Hess — MCQ [2025]', role: 'ms' }, 'h MS.pdf', 1, 'R'],
  [{ units: ['R1.1', 'bad', 'S9.1', 'R1.2'], kind: 'MCQ', level: 'hl', marks: '12', minutes: -3, pages: 20000, role: 'both', era: 'x', title: 'Hess: Test?', details: '', duplicates: [{ path: 'R/Teacher/x.pdf', why: 'w' }, { why: 'no path' }, null], fileName: '' }, 'Hess test MS.pdf', 1, 'R'],
  [{ units: [{ code: 'R1.1', section: 'A' }, { code: 'R1.2', section: 'A' }], kind: 'worksheet', level: 'SL & HL', marks: 20, minutes: 30, pages: 2, hasMarkscheme: true, title: '', fileName: 'w.pdf' }, 'Worksheet Energetics.pdf', 1, 'R'],
  [{ units: [{ code: 'R2.2' }, { code: 'S1.1' }], title: 'Mixed (R2.2)', unitFolder: 'nowhere' }, 'mix.pdf', 1, 'R'],
  [{ units: [{ code: 'R3.1' }], unitFolder: '', title: 'Acids' }, 'acids.pdf', 3, 'R'],
  [{ units: [{ code: 'R2.2' }, { code: 'R3.1' }], title: 'x' }, 'x.pdf', 4, 'R'],
  [{ unitFolder: 'Brand new unit', title: 't', kind: 'other' }, 'n.pdf', 1, 'R'],
  [null, 'x.pdf', 0, ROOT], [[1, 2], 'x.pdf', 0, ROOT], ['text', 'x.pdf', 0, ROOT],
];
out.readAnswer = ANS.map(([o, fileName, i, root]) => [o, fileName, i, root, RD.readAnswer(o, { fileName, model: M[i], root })]);
out.answerFromText = ['sorry', 'Here:\n```json\n{"title":"x"}\n```', 'Answer {"a": 1, "b": {"c": 2}} done', '```\n{"t": [1,2]}\n```', '{bad json}', '{"x": "a\\nb"}'].map((t) => [t, RD.answerFromText(t)]);
out.picturePages = [[1, [], 0], [2, [], 0], [5, [], 0], [5, [1, 2, 5], 3], [5, [1, 2, 5, 3, 4], 3], [9, [1, 2, 9, 3], 3], [3, [1, 2, 3], 3], [0, [], 0]].map(([n, s, e]) => [n, s, e, RD.picturePages(n, s, e)]);
out.nextImagePages = [[1, []], [5, []], [5, [1, 2, 5]], [9, [1, 2, 9, 3, 4, 5]]].map(([n, s]) => [n, s, RD.nextImagePages(n, s)]);
out.folderFor = [[['R1.1'], 1], [['R1.1', 'R1.2'], 1], [['R1.1', 'S1.4'], 1], [['R2.2'], 1], [['R2.2', 'R3.1'], 4], [[], 1], [['S1'], 2], [['S1.4', 'S2.1'], 2]].map(([c, i]) => [c, i, RD.folderFor(c, M[i], models[i][1])]);
const IDX = ['', 'sheets:\n  a/b:\n    notes: {t.pdf: "first note", t MS.pdf: second}\n    units: [R1.1, nope, S2]\n    filed: 2026-11-10\n  c:\n    notes: old text form\n  d: 3\n', 'sheets: [1]', '[', 'hello', 'sheets:\n', 'sheets:\n  x: {units: [R2.2]}\n'];
out.sheetIndex = IDX.map((t) => [t, RD.parseSheetIndexStrict(t), RD.parseSheetIndex(t)]);
const idx = RD.parseSheetIndex(IDX[1]);
out.sheetIndexText = [[idx, RD.serializeSheetIndex(idx)], [{}, RD.serializeSheetIndex({})], [{ 'Teacher/05 Reactivity 1 — Energetics/Hess — MCQ [2025]': { notes: { 'h.pdf': 'a: b # c', '': 'loose' }, units: ['R1.2'], filed: '2026-11-16' }, empty: { notes: {}, units: [], filed: '' } }, '']];
out.sheetIndexText[2][1] = RD.serializeSheetIndex(out.sheetIndexText[2][0]);
out.merge = [[null, { file: 't.pdf', notes: 'n', units: ['R1.1'], filed: '2026-11-16' }], [{ notes: { 't.pdf': 'a' }, units: ['R1.1'], filed: '2026-11-01' }, { file: 't MS.pdf', notes: 'b', units: ['R1.2', 'R1.1'], filed: '' }], [{ notes: 'old', units: [] }, { file: '', notes: '', units: [] }]].map(([p, e]) => [p, e, RD.mergeSheetEntry(p, e)]);
out.notesText = [{}, { 't.pdf': 'one' }, { 't.pdf': 'one', 't MS.pdf': 'two' }, { '': 'loose', 'x.pdf': 'y' }, 'plain'].map((n) => [n, RD.notesText(n)]);
out.schema = RD.SCHEMA; out.kinds = RD.KINDS; out.sheetKinds = SH.KINDS; out.sorts = SH.SORTS; out.eras = SH.ERAS;

const json = JSON.stringify(out);
if (json.includes('"##') || json.includes('\\##')) throw new Error('delimiter');
let rev = ''; try { rev = (await import('child_process')).execSync('git rev-parse --short HEAD', { cwd: nexus, encoding: 'utf8' }).trim(); } catch {}
fs.writeFileSync(out_path,
`// Generated from the laptop's renderer/src/studysheets.js, studyupload.js, studyread.js and studydeck.js (nexus ${rev}): what they give for
// these inputs. SheetsTests checks the iPhone and iPad port gives the same. Regenerate: node tools/study-golden/gen-sheets.mjs <nexus checkout>.
let sheetsGolden = ##"${json}"##
`);
console.log(json.length, out.models.map((m) => m.sheets.length), out.readAnswer.length);
