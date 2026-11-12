// Writes Packages/NexusCore/Tests/NexusCoreTests/CriticGolden.swift: what the laptop's renderer/src/board/critic.js and drafts.js give
// for a set of inputs (fixed ones and seeded random ones), so CriticTests can check the iPad's port gives the same.
// Run from this folder with a nexus checkout beside nexus-mobile:  node gen.mjs ../../../nexus
import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const K = await import(pathToFileURL(path.join(nexus, 'renderer/src/board/critic.js')));
const W = await import(pathToFileURL(path.join(nexus, 'renderer/src/board/drafts.js')));
const out_path = new URL('../../Packages/NexusCore/Tests/NexusCoreTests/CriticGolden.swift', import.meta.url);
const helpers = fs.readFileSync(path.join(nexus, 'dev/unit-boardwrite.mjs'), 'utf8').split('\n').slice(12, 34).join('\n');
const { rnd, ri, pick, PLAIN, NASTY, text, edit } = new Function(helpers + '; return { rnd, ri, pick, PLAIN, NASTY, text, edit };')();
const out = { parse: [], diff: [], edit: [], resolve: [], offsets: [], merge: [] };
const P = (md) => out.parse.push({ md, marks: K.parseCritic(md).map((m) => [m.kind, m.from, m.to, m.old, m.new]) });
['a {++b++} c {--d--} {~~e~>f~~}', 'one\n{++two++}', '{++a and {--b and {~~c~~} and {~~d~>e', '{++a\nb++}', '{++a {--b--} c++}', '`{++x++}` and ``{--y--}``', '`a` {++x++} `b`', '```\n{++x++}\n```\n{--y--}'].forEach(P);
const D = (a, b) => out.diff.push({ a, b, d: K.diffToCritic(a, b) });
[['the cat sat on the mat', 'the dog sat on a mat'], ['a big red cat', 'a red fat cat'], ['a\nc', 'a\nb\nc'], ['a\nb\nc', 'a\nc'], ['a\nc', 'a\n\nc'], ['', 'x\ny'], ['x\ny', ''], ['', ''], ['# Cells\n- one\n- two', '# Plant Cells\n- one\n- three'], ['first part. second part.', 'first part.\nsecond part.'], ['use `abc` here', 'use `abXc` here'], ['```\ncode\n```\nok', '```\ncode2\n```\nok'], ['a ++} b', 'a {++x++} b'], ['x', 'x ~> y ~~} {~~'], ['{--a--}', '{--b--}'], ['p', '`{++`'], ['```\n{++x++}\n```', '```\n{++x++}\n```\nmore']].forEach(([a, b]) => D(a, b));
for (let n = 0; n < 160; n++) { const vocab = n % 2 ? NASTY : PLAIN, a = n % 37 === 0 ? '' : text(vocab, ri(40)), b = n % 41 === 0 ? '' : edit(a, vocab, 1 + ri(8)); D(a, b); P(out.diff[out.diff.length - 1].d); }
const E = (md, from, to, ins, fwd = false) => { const r = K.reviewEdit(md, from, to, ins, { forward: fwd }); out.edit.push({ md, from, to, ins, fwd, out: r.md, cursor: r.cursor }); return r; };
[['a {++bc++} d', 6, 6, 'X'], ['a {++bc++} d', 10, 10, 'X'], ['a{++b++}c', 7, 8, ''], ['the cat sat', 4, 7, 'dog'], ['ab{++cd++}ef', 1, 11, 'X'], ['a{++bcd++}e', 5, 6, 'X'], ['a{--bcd--}e', 5, 5, 'X'], ['a{--bcd--}e', 4, 5, ''], ['abc', 1, 2, '', true], ['a{--b--}c', 8, 9, '', true], ['a{--bc--}d', 4, 5, '', true], ['one\ntwo\nthree', 4, 8, ''], ['one\ntwo', 3, 7, ''], ['ab\ncd', 2, 3, ''], ['abc', 3, 3, '\n'], ['abc', 0, 0, '\n'], ['x\n{++abcd++}', 7, 7, '\n'], ['x {++abcd++} y', 7, 7, '\n'], ['one two', 3, 3, '\n'], ['a', 1, 1, 'b\nc'], ['{--a--}{++b++}\nkeep {~~x~>y~~}\nz', 32, 32, '!'], ['use `abc` now', 7, 7, 'X'], ['```\nab\n```\ntext', 5, 5, 'X'], ['a\n\nc', 2, 2, 'x']].forEach((c) => E(...c));
const rawAt = (md, k) => { const map = K.newOffsets(md); return k < map.length ? map[k] : md.length; };
for (let n = 0; n < 50; n++) {
  const vocab = n % 2 ? NASTY : PLAIN, start = text(vocab, 3 + ri(20));
  let md = start, view = K.textOf(start, 'new');
  for (let step = 0; step < 12; step++) {
    const nf = ri(view.length + 1), nt = Math.min(view.length, nf + (ri(3) ? ri(6) : 0)), ins = ri(3) ? pick([pick(vocab), ' ', '\n', 'x', pick(vocab) + ' ']) : '';
    if (nf === nt && !ins) continue;
    const r = E(md, rawAt(md, nf), rawAt(md, nt), ins, ri(2) === 0);
    view = view.slice(0, nf) + ins + view.slice(nt); md = r.md;
  }
  out.offsets.push({ md, map: K.newOffsets(md) });
}
for (let n = 0; n < 80; n++) {
  const vocab = n % 2 ? NASTY : PLAIN, a = text(vocab, ri(25)), b = edit(a, vocab, 1 + ri(6)), md = K.diffToCritic(a, b), c = K.counts(md).total;
  if (!c) continue;
  const i = ri(c), acc = ri(2) === 0;
  out.resolve.push({ md, i, acc, out: acc ? K.acceptAt(md, i) : K.rejectAt(md, i) });
}
[['a {++b++} c {--d--} e {~~f~>g~~}', 9], ['a {++b++} c {--d--} e {~~f~>g~~}', -1], ['a\n{--b--}\nc', 0], ['{++a++}{++b++}', 0], ['x\n{--a--}{++b++}', 0], ['{++```++}\n{++a++}', 0]].forEach(([md, i]) => { out.resolve.push({ md, i, acc: true, out: K.acceptAt(md, i) }); out.resolve.push({ md, i, acc: false, out: K.rejectAt(md, i) }); });
const M = (s, o, n) => { const r = W.bringOver(s, o, n); out.merge.push({ snap: s, old: o, new: n, text: r.text, merged: r.merged, clashes: r.clashes }); };
const snap = 'Intro line\nCells are small.\nThey divide.\nThe end.';
M(snap, 'A better intro\nCells are small.\nThey divide.\nThe end.', 'Intro line\nCells are small.\nThey divide.\nThe end.');
M(snap, 'Intro line\nCells are tiny.\nThey divide.\nThe end.', 'Intro line\nCells are very small.\nThey divide.\nEnd.');
M('a\nb', 'a\nb\nfrom old', 'a\nb\nfrom new');
M('one\ntwo\nthree', 'One\ntwo\nthree', 'One!\ntwo\nTHREE');
for (let n = 0; n < 60; n++) { const vocab = n % 3 ? PLAIN : NASTY, s = text(vocab, 5 + ri(30)); M(s, edit(s, vocab, 1 + ri(4)), edit(s, vocab, 1 + ri(4))); }
const json = JSON.stringify(out);
if (json.includes('"##') || json.includes('\\##')) throw new Error('delimiter');
fs.writeFileSync(out_path,
`// Generated from the laptop's renderer/src/board/critic.js and drafts.js (nexus branch claude/project-thread-f6tljx, c936723): what they
// give for these inputs. CriticTests checks the iPad's port gives the same. Regenerate: node tools/critic-golden/gen.mjs <nexus checkout>.
let criticGolden = ##"${json}"##
`);
console.log(json.length, out.parse.length, out.diff.length, out.edit.length, out.resolve.length, out.merge.length);
