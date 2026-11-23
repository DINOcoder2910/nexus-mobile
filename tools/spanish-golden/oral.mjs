// Writes Packages/NexusCore/Tests/NexusCoreTests/SpanishOralGolden.swift: what the laptop's renderer/src/spanishoral.js and
// spanishoralhear.js give for a set of oral files and inputs, so SpanishOralTests can check the iPhone and iPad's SpanishOral.swift
// reads them the same way. Run from this folder with a nexus checkout beside nexus-mobile (and its node_modules, for `yaml`):
//   node oral.mjs ../../../nexus
import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const O = await import(pathToFileURL(path.join(nexus, 'renderer/src/spanishoral.js')));
const H = await import(pathToFileURL(path.join(nexus, 'renderer/src/spanishoralhear.js')));
const outPath = new URL('../../Packages/NexusCore/Tests/NexusCoreTests/SpanishOralGolden.swift', import.meta.url);
const out = {};

out.toTheme = ['Ingenio humano', 'human ingenuity', 'tecnologia', 'Tecnología', 'IDENTIDADES', 'social', 'Compartir el planeta', 'planet', 'nonsense', '', 'experiencias', 'Festivales y celebraciones', 'el barrio'].map((t) => [t, O.toTheme(t)]);
out.themeName = ['ingenio', 'planeta', 'nope', ''].map((t) => [t, O.themeName(t)]);
out.labelFor = [{ label: 'Mi etiqueta', theme: 'ingenio', topic: 'Tecnología' }, { label: '', theme: 'experiencias', topic: 'Vacaciones' }, { label: '', theme: '', topic: 'Ocio' }, { label: '', theme: 'planeta', topic: '' }].map((i) => [i, O.labelFor(i)]);
out.oralId = ['2026-11-19T20:10:33', '2026-11-19T20:10', '2026-01-02T03:04:05.123Z'].map((t) => [t, O.oralId(t)]);
out.settings = ['teacher: "Señora K"\ntutor: "Ana"\n', 'teacher: ""\n', 'nonsense: [', '', 'preset: ib\ntutor: Pablo\n'].map((t) => { const s = O.parseSettings(t); return [t, { teacher: s.teacher, tutor: s.tutor }]; });
const orals = [
  O.serializeOral({ id: '2026-11-19 2010', kind: 'full', by: 'practice', started: '2026-11-19T20:10', image: 'fiesta.jpg', theme: 'Experiencias', otherTheme: 'human ingenuity', notes: '- fiesta\n- familia', segments: [{ part: 1, file: 'p1.webm', ms: 61000, q: '', heard: 'En la foto hay una fiesta.', said: 'En la foto hay una fiesta' }, { part: 2, file: 'p2.webm', ms: 120000, q: '¿Qué haces?', heard: 'Juego al fútbol.', said: '' }], marks: { A: 8, B1: 4, B2: 4, C: 5, total: 21 }, summary: 'Good picture, thin conversation.', model: 'opus' }),
  O.serializeOral({ id: '2026-11-20 1800', kind: 'session', by: 'tutor', title: '', recording: 'recording.m4a', started: '2026-11-20T18:00', given: { A: null, B1: null, B2: null, C: null, total: 18, max: 24, comments: 'Más pasado.', points: ['Use the preterite', 'Slow down'] }, turns: [{ start: 0, end: 4.5, who: 'examiner', text: '¿Qué hiciste ayer?' }, { start: 4.5, end: 9, who: 'me', text: 'Ayer fui al cine.' }, { start: 9, end: 12, who: 'feedback', text: 'Good.' }], listening: { talk: { mine: 0.5, me: 4.5 }, diffs: [{ said: 'fue', meant: 'fui', kind: 'ending' }] }, waiting: 'hear', from: 'iPhone' }),
  O.serializeOral({ id: '2026-11-21 0900', kind: 'full', by: 'teacher', title: 'Summative IO', started: '2026-11-21T09:00', given: { A: 9, B1: 5, B2: 4, C: 5, total: null, max: null, comments: '', points: [] } }),
  O.serializeOral({ id: '2026-11-22 1000', kind: 'conversation', by: 'practice', started: '2026-11-22T10:00', theme: 'planeta', marks: { A: 7, B1: null, B2: 4, C: 4, total: 15 } }),
  'id: "2026-11-23 0800"\nkind: weird\nby: someone\nstarted: 2026-11-23T08:00\ngiven:\n  A: "7"\n  B2: 5\nturns:\n  - text: hola\n    who: me\n  - who: me\nsegments:\n  - part: 1\n',
  'not: [valid',
];
out.orals = orals.map((t, i) => {
  const o = O.parseOral(t, `fallback-${i}`);
  if (!o) return [t, null];
  return [t, { id: o.id, kind: o.kind, by: o.by, title: o.title, recording: o.recording, started: o.started, image: o.image, theme: o.theme, otherTheme: o.otherTheme, notes: o.notes,
    given: o.given, marks: o.marks, summary: o.summary, segments: o.segments.map((s) => ({ part: s.part, file: s.file, ms: s.ms, q: s.q, heard: s.heard, said: s.said })), turns: o.turns,
    listening: !!o.listening, waiting: o.waiting ?? null, from: o.from ?? null, share: O.shareOf(o), max: O.maxOf(o.kind), when: O.history([o])[0].when }];
});
out.listenTest = H.LISTEN_TEST.map((l) => ({ id: l.id, read: l.read, how: l.how || '' }));
const json = JSON.stringify(out);
if (json.includes('"##') || json.includes('\\##')) throw new Error('delimiter');
fs.writeFileSync(outPath,
`// Generated from the laptop's renderer/src/spanishoral.js and spanishoralhear.js: what they give for these inputs. SpanishOralTests
// checks the iPhone and iPad's SpanishOral.swift gives the same. Regenerate: node tools/spanish-golden/oral.mjs <nexus checkout>.
let spanishOralGolden = ##"${json}"##
`);
console.log('wrote', json.length, 'characters;', out.orals.length, 'orals');
