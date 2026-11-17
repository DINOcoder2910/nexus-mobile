// Writes Packages/NexusCore/Tests/NexusCoreTests/SpanishGolden.swift: what the laptop's renderer/src/spanishcore.js, spanishcheck.js,
// spanishmemory.js and spanishgrade.js (and lang-service.js's accent variants) give for a set of inputs (fixed ones and seeded random
// ones), so SpanishTests can check the iPhone and iPad port gives the same.
// Run from this folder with a nexus checkout beside nexus-mobile (and its node_modules, for `yaml`):  node gen.mjs ../../../nexus
// (Without node_modules in the checkout: copy the four renderer/src/spanish*.js files and lang-service.js into a folder that has `yaml`
// installed and pass that folder with --flat.)
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { pathToFileURL } from 'url';
const flat = process.argv.includes('--flat');
const nexus = path.resolve(process.argv.filter((a) => !a.startsWith('--'))[2] || '../../../nexus');
const src = (f) => pathToFileURL(path.join(nexus, flat ? '' : 'renderer/src', f));
const SC = await import(src('spanishcore.js'));
const CK = await import(src('spanishcheck.js'));
const MEM = await import(src('spanishmemory.js'));
const GR = await import(src('spanishgrade.js'));
const LS = createRequire(import.meta.url)(path.join(nexus, 'lang-service.js'));
const outPath = new URL('../../Packages/NexusCore/Tests/NexusCoreTests/SpanishGolden.swift', import.meta.url);

process.env.TZ = 'Asia/Kolkata';
let seed = 20261116;
const rnd = () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));
const pick = (l) => l[Math.floor(rnd() * l.length)];
const out = {};

// ---- skills and tags
out.toSkill = ['Ser/Estar', 'accent', 'preterite', 'negative imperative', 'imperative', 'por vs para', 'nonsense', 'agree.gender', 'Gender agreement', 'Plural', 'reflexive verbs',
  'Present perfect', 'Imperfect', 'Subjunctive', 'conditional', 'future', 'ir a + infinitive', 'stem change', 'present tense', 'tener que', 'possessive', 'object pronoun', 'comparison',
  'preposition', 'connector', 'usted', 'word order', 'false friend', 'Accent on verb', 'question word', 'tú/tu', '¿', 'spelling', 'ortografía', 'subject-verb agreement', 'article', 'gustar', 'past tense choice', '']
  .map((s) => [s, SC.toSkill(s)]);
out.cleanTag = ['Sustantivo', 'irr::o-ue', 'ser-estar', 'skill::preterite', 'tema::nope', 'Frase', '  Verbo ', 'organización', 'pos::verbo', 'whatever', '', 'tema::experiencias', 'skill::gustar']
  .map((s) => [s, SC.cleanTag(s)]);
out.accents = ['cafe', 'manana', 'Peru', 'comi', 'tambien', 'nino', 'pinguino', 'esta', 'mas', 'cancion', 'Arbol', 'dificil'].map((w) => [w, LS.accentVariants(w)]);
out.skillsYaml = SC.serializeSkills({ ...SC.COURSE_STATUS, 'verb.subjuntivo': 'taught' });
out.course = SC.course();
out.profileTemplate = SC.profileTemplate();
out.setupFiles = Object.entries(SC.setupFiles());

// ---- cards
out.cardId = [['la maleta', []], ['la maleta', ['maleta']], ['la maleta', ['maleta', 'maleta-2']], ['¿Qué tal?', []], ['', []], ['El niño pequeño de la casa grande que vive cerca del mar', []]]
  .map(([f, t]) => [f, t, SC.cardId(f, t)]);
out.draft = [{ word: 'maletas', lemma: 'maleta', form: 'feminine plural noun', meaning: 'suitcase' }, { word: 'fui', lemma: 'ir', form: 'verb, pretérito indefinido, yo', meaning: 'went' },
  { word: 'libros', lemma: '', form: 'masculine plural noun', meaning: 'books' }, { word: 'rápido', lemma: 'rápido', form: 'adjective', meaning: 'fast' }, { word: 'sin embargo', form: 'connector', meaning: 'however' },
  { word: 'bien', form: 'adverb', meaning: 'well' }, { word: 'la casa', lemma: 'casa', form: 'feminine singular noun', meaning: 'house' }]
  .map((w) => [w, SC.draftCard(w, 'es-viajes')]);
out.warnings = [[{ front: 'maleta', back: 'x', tags: ['pos::sustantivo'] }, [{ front: 'la maleta', back: 'y', deck: 'Vocab · Viajes' }]], [{ front: '', back: '' }, []],
  [{ front: 'a, b, c', back: 'x' }, []], [{ front: 'la casa', back: 'house', tags: ['pos::sustantivo'] }, [{ front: 'el perro', back: 'dog', deck: '' }]]]
  .map(([c, e]) => [c, e, SC.cardWarnings(c, e)]);

// ---- the checker
const T = 'Ayer comi en el cafe con mi amigos.';
const sm = CK.spellMarks([{ word: 'comi', start: 5, end: 9, accent: 'comí', suggestions: ['comí'] }, { word: 'cafe', start: 16, end: 20, accent: 'café', suggestions: ['café'] }, { word: 'xyz', start: 0, end: 3, accent: null, suggestions: ['y', 'z', 'w', 'q'] }]);
out.spellMarks = sm;
const ltIn = [{ offset: 25, length: 9, message: 'Concordancia', replacements: [{ value: 'mis amigos' }], rule: { id: 'ES_CONCORDANCIA_NUM', category: { id: 'GRAMMAR' } } },
  { offset: 0, length: 4, message: 'style', replacements: [], rule: { id: 'X', category: { id: 'STYLE' } } },
  { offset: 5, length: 4, message: 'acento', replacements: [{ value: 'comí' }], rule: { id: 'Y', category: { id: 'TYPOS' } } },
  { offset: 10, length: 2, message: 'Error gramatical: ser o estar', replacements: [{ value: 'a' }], rule: { id: 'SER_ESTAR', category: { id: 'GRAMMAR' } } },
  { offset: 33, length: 1, message: 'punto', replacements: [], rule: { id: 'PUNT', category: { id: 'PUNCTUATION' } } }];
out.lt = { text: T, matches: ltIn, marks: CK.ltMarks(T, ltIn) };
const aiAns = { corrected: 'Ayer comí en el café con mis amigos.', mistakes: [{ wrong: 'comi', right: 'comí', skill: 'accent', why: 'yo preterite' }, { wrong: 'mi amigos', right: 'mis amigos', skill: 'agree.number', why: 'plural' }, { wrong: 'not there', right: 'x', skill: 'spelling', why: '' }], good: [{ text: 'Ayer', skill: 'tense.past' }], structures: [{ name: 'pretérito indefinido', text: 'comi' }], words: [{ word: 'Ayer', meaning: 'yesterday' }] };
out.readCheck = { text: T, ans: aiAns, ai: CK.readCheck(T, aiAns) };
const algo = [...sm.slice(0, 2), ...CK.ltMarks(T, ltIn.slice(0, 2))];
out.merge = [];
const addMerge = (text, alg, ans) => { const ai = ans ? CK.readCheck(text, ans) : null; const m = CK.merge(text, alg, ai); out.merge.push({ text, algo: alg, ans, marks: m, runs: CK.runs(text, m).map((r) => [r.text, r.mark ? r.mark.wrong : null]), corrected: CK.corrected(text, m) }); };
addMerge(T, algo, null); addMerge(T, algo, aiAns);
addMerge('Soy cansado.', [{ s: 0, e: 3, wrong: 'Soy', right: 'Estoy', skill: 'ser-estar', kind: 'error', why: '', by: 'languagetool' }], { corrected: 'Soy cansado.', mistakes: [], good: [], structures: [], words: [] });
// random sentences with random marks
const WORDS = ['yo', 'tu', 'el', 'la', 'casa', 'comi', 'cafe', 'fui', 'mi', 'amigos', 'esta', 'bien', 'ayer', 'hoy', 'que', 'como', 'muy', 'grande', 'perro', 'gato'];
for (let k = 0; k < 40; k++) {
  const words = Array.from({ length: ri(3, 9) }, () => pick(WORDS)); const text = words.join(' ') + '.';
  const al = []; let at = 0;
  words.forEach((w) => { if (rnd() < 0.3) al.push({ s: at, e: at + w.length, wrong: w, right: w.toUpperCase(), skill: pick(['spelling', 'accent.stress', 'agree.gender']), kind: rnd() < 0.5 ? 'accent' : 'error', why: 'w', by: rnd() < 0.5 ? 'dictionary' : 'languagetool' }); at += w.length + 1; });
  const ans = rnd() < 0.3 ? null : { corrected: rnd() < 0.5 ? text.toUpperCase() : text, mistakes: words.filter(() => rnd() < 0.25).map((w) => ({ wrong: rnd() < 0.1 ? 'zz' : w, right: w + 'x', skill: pick(['ser-estar', 'accent', 'spelling']), why: 'y' })), good: words.filter(() => rnd() < 0.15).map((w) => ({ text: w, skill: 'gustar' })), structures: [], words: [] };
  addMerge(text, al, ans);
}
out.checkPrompt = [CK.checkPrompt({ text: T, found: algo, taught: SC.COURSE_STATUS }), CK.checkPrompt({ text: 'Hola.', question: '¿Qué tal?', taught: { 'verb.subjuntivo': 'taught' } })];
out.jsonFrom = ['Here:\n```json\n{"a":1}\n```', 'sure {"b": [1, 2]} ok', 'nothing'].map((t) => [t, CK.jsonFrom(t)]);

// ---- the log and the numbers
const res = { marks: CK.merge(T, algo, CK.readCheck(T, aiAns)), corrected: aiAns.corrected, structures: [{ name: 'pretérito indefinido', text: 'comi' }], words: [{ word: 'Ayer', lemma: 'ayer', form: 'adverb', meaning: 'yesterday' }] };
const e1 = CK.logEntry({ at: '2026-11-09T10:00:00.000', text: T, question: '¿Qué hiciste?', result: res, chat: '2026-11-09 1405 Preterite' });
out.logEntry = e1;
out.logText = CK.serializeLog([e1, { at: '2026-11-09T10:05:00.000', source: 'chat', text: 'Hola: "sí" #1', fixed: 'Hola: "sí" #1', mistakes: [], good: [] }]);
const SK = SC.SKILLS.map((s) => s.id);
out.stats = [];
for (let k = 0; k < 25; k++) {
  const n = ri(1, 40); const entries = [];
  for (let i = 0; i < n; i++) {
    const day = ri(1, 28), h = ri(0, 23), m = ri(0, 59);
    const at = `2026-10-${String(day).padStart(2, '0')}T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00.000`;
    const pool = SK.slice(0, ri(2, 8));
    entries.push({ at, text: 'x', mistakes: pool.filter(() => rnd() < 0.35).map((s) => ({ skill: s })), good: pool.filter(() => rnd() < 0.3).concat(rnd() < 0.1 ? ['not-a-skill'] : []) });
  }
  const nowText = '2026-11-' + String(ri(1, 20)).padStart(2, '0') + 'T12:00:00'; const now = Date.parse(nowText);
  const st = CK.skillStats(entries, now);
  out.stats.push({ entries, nowText, stats: Object.entries(st), weakest: CK.weakest(st, 5).map((x) => x.id), streak: CK.streak(entries), solid: CK.solidShare(st, SC.COURSE_STATUS) });
}
out.moveToChat = CK.moveToChatText([e1, { text: 'Hola.', mistakes: [], fixed: 'Hola.' }]);
out.resultForTutor = [CK.resultForTutor(e1), CK.resultForTutor({ text: 'Hola', mistakes: [], good: [], partial: true })];

// ---- the tutor's reply, chats, memory
out.replies = ['Hola.\n\n```card\n{"front":"la maleta","back":"the suitcase","deck":"es-viajes"}\n```\n\n```check\n¿Qué hiciste ayer?\n```', 'Bien.\n```check\n¿Qué', 'Just text.', '```card\nnot json\n```\nAfter.']
  .map((t) => [t, MEM.parseReply(t)]);
const chat = { title: 'Preterite', started: '2026-11-09T14:05:00', model: 'opus', session: 's1', summary: 'Did the preterite: "fui" & more.', skills: ['verb.indefinido'], taught: ['verb.indefinido: endings'], messages: [{ role: 'user', text: 'Hola' }, { role: 'tutor', text: 'Hi.\n\n```check\nEscribe.\n```' }, { role: 'check', text: 'My answer: Fui.\nThe checker found no mistakes.' }] };
out.chatText = MEM.serializeChat(chat);
out.chatBack = MEM.parseChat(out.chatText, 'p');
out.chatPaths = [['Spanish', '2026-11-09T14:05:00', 'Tú: commands / again'], ['Work/Spanish', '2026-11-16T09:30:12.123', ''], ['S', '2026-11-16T09:30:00', 'A very long title that goes on and on and on past fifty characters for sure']]
  .map(([b, s, t]) => [b, s, t, MEM.chatPath(b, s, t)]);
const base = MEM.parseProfile(SC.profileTemplate());
out.profileBase = base;
const after = { ...base, working: '- Preterite endings.\n- ser and estar', strengths: '- Accents', learn: base.learn };
out.profileChanges = MEM.profileChanges(base, after);
out.profileText = MEM.serializeProfile({ ...after, mine: 'my own' });
out.caps = [['next', Array.from({ length: 80 }, (_, i) => '- line ' + i).join('\n')], ['mistakes', 'short'], ['strengths', 'x'.repeat(700)]].map(([k, t]) => [k, t, MEM.capBlock(k, t)]);
const memAns = { title: 'T', summary: 'S', skills: ['preterite', 'gustar', 'gustar'], taught: [{ skill: 'imperative', what: 'tú commands' }, { skill: 'x', what: '' }], profile: { strengths: 'a', working: 'b', mistakes: 'c', taught: 'd', next: 'e', learn: 'f' }, notes: [{ skill: 'Ser/estar', lines: ['x'] }, { skill: 'gustar', lines: [] }] };
out.readMemory = [memAns, MEM.readMemory(memAns)];
const n1 = MEM.addToNote('', 'ser-estar', 'taught', ['Mixed up soy and estoy.'], { day: '2026-11-09', link: '2026-11-09 1405 Preterite' });
out.notes = [n1, MEM.addToNote(n1, 'ser-estar', 'taught', ['Got it right.', 'Again.'], { day: '2026-11-10' }), MEM.addToNote('# Hand written\n\nno notes heading', 'gustar', 'reteach', ['x'], { day: '2026-11-11' })];

// ---- writing
const texts = ['Querida Ana:\n\nAyer fui a la playa con mi familia y comimos paella en un restaurante muy bonito cerca del mar.\n\nHoy voy a estudiar.\n\nUn abrazo,\nMurtaza',
  'Mis vacaciones\n\nLunes, 3 de mayo de 2026\n\nEl verano pasado viajé a España con mis padres. Visitamos Madrid y Barcelona, y comimos mucho. Me gustó mucho el museo del Prado porque hay cuadros muy famosos.\n\nEl año que viene quiero ir a México.\n\nSaludos,\nM.',
  'Hola, ¿qué tal? Estoy bien.', '', 'Estimado señor:\n\nLe escribo para pedir información sobre el curso de verano. ¿Cuánto cuesta? ¿Hay residencia para los estudiantes? Me interesa mucho aprender español en Salamanca.\n\nAtentamente,\nMurtaza Ali\n15/11/2026'];
out.wordCount = texts.map((t) => [t, GR.wordCount(t)]);
const pr = [{ id: 'p-1', text: 'Escribe un correo electrónico o un blog sobre tus vacaciones.', unit: 'G12.1', types: ['correo electrónico', 'blog'], source: 'Ms. Panhausen', task: '', added: '2026-11-09' }, { id: 'p-2', text: 'Un diario: "mi día"', unit: '', types: [], source: '', task: 'A', added: '' }];
out.promptsText = GR.serializePrompts(pr);
out.promptsBack = GR.parsePrompts(out.promptsText);
out.typesIn = ['Escribe un correo electrónico, un blog o un diario.', 'Un artículo para la revista o una reseña', 'nada'].map((t) => [t, GR.typesIn(t)]);
out.grades = [];
const c = (mark) => ({ mark, met: ['m'], missed: [], evidence: ['"q"'], next: ['n'] });
for (let k = 0; k < 40; k++) {
  const ans = { A: c(ri(-1, 8)), B: c(ri(0, 7)), C: c(ri(0, 4)), textType: 'blog', offTask: rnd() < 0.15, misread: rnd() < 0.2, wrongAudience: rnd() < 0.2, typeOffered: rnd() < 0.8, mistakes: rnd() < 0.5 ? [{ wrong: 'fui', right: 'fue', skill: 'preterite', why: 'él' }] : [], overall: 'ok' };
  const count = { paragraphs: ri(0, 4), counted: ri(40, 170) };
  out.grades.push({ ans, count, grade: GR.readGrade(ans, count) });
}
out.gradePrompt = GR.gradePrompt({ prompt: pr[0], text: 'y', count: GR.wordCount(texts[0]), samples: [{ A: 4, B: 5, C: 2, comment: 'good', text: 'Hola amigo.' }] });
const g = GR.readGrade(out.grades[0].ans, { paragraphs: 3 });
out.piece = GR.pieceFile({ prompt: pr[0], text: texts[0], count: GR.wordCount(texts[0]), grade: g, day: '2026-11-09' });
out.samples = ['---\nA: 4\nB: 5\nC: 2\ncomment: good\n---\n# x\nHola amigo.', '---\nA: 4\n---\nHola', '---\nA: 4\nB: 5\nC: 2\n---\n'].map((t) => [t, GR.parseSample(t)]);

const json = JSON.stringify(out);
if (json.includes('"##') || json.includes('\\##')) throw new Error('delimiter');
fs.writeFileSync(outPath,
`// Generated from the laptop's renderer/src/spanishcore.js, spanishcheck.js, spanishmemory.js, spanishgrade.js and lang-service.js
// (nexus main): what they give for these inputs. SpanishTests checks the iPhone and iPad port gives the same.
// Regenerate: node tools/spanish-golden/gen.mjs <nexus checkout>.
let spanishGolden = ##"${json}"##
`);
console.log('wrote', json.length, 'characters;', out.merge.length, 'merges,', out.stats.length, 'stat runs,', out.grades.length, 'grades');
