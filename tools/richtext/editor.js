// The laptop's rich-text block editor on the iPad (nexus docs/rich-text.md "Editors": the same editor in a web view). A block's words are
// edited as its doc in a ProseMirror view with the laptop's own commands, keys and typing rules (board/richedit.js), Review mode and a
// locked draft (board/richreview.js), and the words as markdown going back to the app on every change (the copy's words, which the board,
// drafts, comments, sync and search keep using, as the laptop's item._md). Sources/Writing/RichEditor.swift hosts it and talks to it
// through window.rich (in) and webkit.messageHandlers.rich (out). Built by tools/richtext/build.mjs from a nexus checkout.
//
// Places in the words cross the bridge as offsets in that markdown (UTF-16, as NSString counts), mapped to and from the doc with the
// laptop's board/richanchor.js, so the app's comments, flashcards, tasks and Review buttons work on the same ranges as before.
import { EditorView, Decoration, DecorationSet } from 'prosemirror-view';
import { Plugin, PluginKey, TextSelection, AllSelection } from 'prosemirror-state';
import { undo, redo, undoDepth, redoDepth, closeHistory } from 'prosemirror-history';
import katex from 'katex';
import { schema } from 'nexus/board/richschema.js';
import * as R from 'nexus/board/richedit.js';
import { docToMd } from 'nexus/board/richmd.js';
import { docForMd } from 'nexus/board/richblock.js';
import { readDoc, FIRST_TAB, tabIds } from 'nexus/board/richfile.js';
import { blockTransform } from 'nexus/board/livetext.js';
import { richMap, toMd, toDoc, posAt } from 'nexus/board/richanchor.js';
import { reviewPlugin, lockPlugin, REVIEW } from 'nexus/board/richreview.js';
import { richCount } from 'nexus/board/richwords.js';
import { accentDead, ACCENT_KEYS } from 'nexus/board/blocks.js';

const post = (m) => { try { window.webkit.messageHandlers.rich.postMessage(m); } catch { if (window.richOut) window.richOut(m); } };
const mdOf = (doc) => docToMd(doc.header, doc.docs).replace(/\n$/, '');
const tabOf = (doc) => tabIds(doc.header)[0] || FIRST_TAB;
const host = () => document.getElementById('ed');

let view = null;
let held = null; // { doc: { header, docs }, md }: the block's doc and the markdown the app holds for it (the same words)
let tab = FIRST_TAB;
let opts = { chem: true, review: false, locked: false };
let marked = []; // comment ranges, as markdown offsets [from, to]
let mapCache = null; // richMap of `held`, made when a place has to cross the bridge

// ---------------------------------------------------------------------------------------------------- places: markdown <-> doc
function map() {
  if (!mapCache || mapCache.md !== held.md || mapCache.node !== view.state.doc) mapCache = { md: held.md, node: view.state.doc, m: richMap({ header: held.doc.header, docs: { ...held.doc.docs, [tab]: view.state.doc } }, tab, held.md) };
  return mapCache.m;
}
const docRange = (from, to) => { const r = toDoc(map(), from, to); return r ? { from: Math.max(0, Math.min(r.from, view.state.doc.content.size)), to: Math.max(0, Math.min(r.to, view.state.doc.content.size)) } : null; };
function selMd() {
  const { from, to } = view.state.selection;
  try { const r = toMd(map(), from, to); if (r) return { loc: r.from, len: Math.max(0, r.to - r.from) }; } catch {}
  return { loc: held.md.length, len: 0 };
}
function posFromMd(o, bias = 1) { try { return Math.max(0, Math.min(posAt(map(), o, bias), view.state.doc.content.size)); } catch { return view.state.doc.content.size; } }

// ---------------------------------------------------------------------------------------------------- the look
// look: { size, scale, family, color, muted, accent, rule, codeBack, fill, dark, padX, padY, fullscreen, page: { top, right, bottom, left },
// styles: { title|h1|h2|h3|body|quote|code: { size, weight, color, line, before, after, indent } }, hl: { name: css }, colors: { name: css } }
const FAMILY = { sans: '-apple-system, system-ui, sans-serif', serif: 'ui-serif, Georgia, serif', mono: 'ui-monospace, Menlo, monospace', rounded: 'ui-rounded, -apple-system, sans-serif' };
function setLook(L) {
  if (!L) return;
  const s = L.scale || 1, root = document.documentElement, css = [];
  root.classList.toggle('full', !!L.fullscreen);
  root.classList.toggle('dark', !!L.dark);
  root.style.setProperty('--ink', L.color || '#1b1b1b');
  root.style.setProperty('--muted', L.muted || '#6b6b6b');
  root.style.setProperty('--accent', L.accent || '#1f5fd1');
  root.style.setProperty('--rule', L.rule || 'rgba(0,0,0,.15)');
  root.style.setProperty('--code-back', L.codeBack || 'rgba(0,0,0,.05)');
  root.style.setProperty('--family', FAMILY[L.family] || FAMILY.sans);
  root.style.setProperty('--size', (L.size || 17) * s + 'px');
  root.style.setProperty('--list', (L.size || 17) * 1.4 * s + 'px');
  const pad = L.fullscreen ? L.page || { top: 56, right: 72, bottom: 280, left: 72 } : { top: (L.padY || 0) * s, right: (L.padX || 0) * s, bottom: (L.padY || 0) * s, left: (L.padX || 0) * s };
  root.style.setProperty('--pad', `${pad.top}px ${pad.right}px ${pad.bottom}px ${pad.left}px`);
  // the marks' places as the closed block draws them (MDLayoutManager): measured from the words' top, in ems of the line
  const m = L.marks || {}, em = (v) => (+v || 0).toFixed(4) + 'em';
  root.style.setProperty('--quote', (m.quote || Math.round((L.size || 17) * 1.125)) * s + 'px');
  root.style.setProperty('--dot-x', em(Math.max(0.16, (m.dash || 0.36) / 2) - 0.16));
  root.style.setProperty('--dot-y', em((m.ascent || 0.95) - (m.xHeight || 0.52) / 2 - 0.16));
  root.style.setProperty('--box-x', em(Math.max(0, ((m.brackets || 0.8) - 0.9) / 2)));
  root.style.setProperty('--box-y', em((m.ascent || 0.95) - (m.capHeight || 0.7) / 2 - 0.45));
  const st = L.styles || {};
  // every paragraph its style's space after (the copy is one line a paragraph; BlockStyler adds the same); `shift` lifts the words to
  // the top of their line as TextKit has them, and the last line ends with its words (TextKit gives it no line spacing)
  const rule = (sel, v) => { if (v) css.push(`${sel}{font-size:${v.size * s}px;font-weight:${v.weight};color:${v.color};line-height:${v.line};margin:${(v.before || 0) * s}px 0 ${(v.after || 0) * s}px ${(v.indent || 0) * s}px;position:relative;top:${-(v.shift || 0) * s}px}`); };
  rule('#ed .ProseMirror > p, #ed .rt-body', st.body);
  rule('#ed .rt-title', st.title); rule('#ed .rt-h1', st.h1); rule('#ed .rt-h2', st.h2); rule('#ed .rt-h3', st.h3);
  rule('#ed .rt-quote', st.quote); rule('#ed .rt-code', st.code);
  css.push('#ed .ProseMirror > :first-child{margin-top:0}#ed .ProseMirror > :last-child{margin-bottom:0}');
  for (const id of ['body', 'title', 'h1', 'h2', 'h3', 'quote']) if (st[id]) css.push(`#ed .ProseMirror > .rt-${id}:last-child{margin-bottom:${-2 * (st[id].shift || 0) * s}px}`);
  // a run of quote lines: one bar down the run (the space between them is padding, inside the bar); the bar stops at the last line's words
  if (st.quote) css.push(`#ed .rt-quote{--qcut:${2 * (st.quote.shift || 0) * s}px}#ed .rt-quote:has(+ .rt-quote){--qcut:0px;margin-bottom:0;padding-bottom:${(st.quote.after || 0) * s}px}`);
  for (const [k, v] of Object.entries(L.hl || {})) css.push(`#ed mark[data-c="${k}"]{background:${v}}`);
  for (const [k, v] of Object.entries(L.colors || {})) css.push(`#ed .rt-color[data-c="${k}"]{color:${v}}`);
  document.getElementById('look').textContent = css.join('\n');
  if (view) sizeSoon();
}

// ---------------------------------------------------------------------------------------------------- what the editor shows besides the words
// list numbers and checkboxes (the laptop's app/boardrich.js listDeco); a checkbox is ticked by a tap
const listDeco = new Plugin({
  props: {
    decorations(state) {
      const labels = R.listLabels(state.doc), out = [];
      state.doc.forEach((n, off, i) => {
        if (labels[i]) out.push(Decoration.node(off, off + n.nodeSize, { 'data-n': labels[i] }));
        if (n.type.name === 'paragraph' && n.attrs.list === 'check') out.push(Decoration.widget(off + 1, () => { const cb = document.createElement('span'); cb.className = 'rt-box' + (n.attrs.checked ? ' on' : ''); cb.dataset.pos = String(off); cb.contentEditable = 'false'; return cb; }, { side: -1, key: 'cb' + off + (n.attrs.checked ? 'x' : '') }));
      });
      return DecorationSet.create(state.doc, out);
    },
    handleDOMEvents: {
      mousedown(v, e) { const cb = e.target.closest && e.target.closest('.rt-box[data-pos]'); if (!cb) return false; e.preventDefault(); return true; },
      touchend(v, e) {
        const cb = e.target.closest && e.target.closest('.rt-box[data-pos]'); if (!cb) return false;
        e.preventDefault(); if (!opts.locked) R.toggleCheckAt(+cb.dataset.pos)(v.state, v.dispatch); return true;
      },
      click(v, e) {
        const cb = e.target.closest && e.target.closest('.rt-box[data-pos]'); if (!cb) return false;
        e.preventDefault(); if (!opts.locked) R.toggleCheckAt(+cb.dataset.pos)(v.state, v.dispatch); return true;
      },
    },
  },
});
// the words open comments sit on, lit as on the board
const MARKED = new PluginKey('marked');
const markedPlugin = new Plugin({
  key: MARKED,
  state: { init: () => 0, apply: (tr, v) => (tr.getMeta(MARKED) ? v + 1 : v) },
  props: {
    decorations(state) {
      if (!marked.length || !held) return null;
      const out = [];
      for (const [a, b] of marked) { const r = docRange(a, b); if (r && r.to > r.from) out.push(Decoration.inline(r.from, r.to, { class: 'rt-marked' })); }
      return DecorationSet.create(state.doc, out);
    },
  },
});
// maths typeset in place
const typeset = (el, display) => { try { el.innerHTML = katex.renderToString(el.dataset.tex || '', { displayMode: display, throwOnError: false, strict: 'ignore' }); } catch { el.textContent = el.dataset.tex || ''; } };
class MathView {
  constructor(node) { const d = node.type.name === 'math'; this.dom = document.createElement(d ? 'div' : 'span'); this.dom.className = d ? 'rt-math' : 'rt-mathin'; this.dom.dataset.tex = node.attrs.tex; typeset(this.dom, d); }
  stopEvent() { return false; }
  ignoreMutation() { return true; }
}

// the iPad's keys in a block (Sources/Writing/BlockEditor.swift's, the laptop's board keys): styles, Word's accent keys, and the ones the app
// handles (Esc, the Writing view, find, a link)
const STYLES = { '1': 'h1', '2': 'h2', '3': 'h3', '0': 'body' };
let dead = null;
const keys = new Plugin({
  props: {
    handleKeyDown(v, e) {
      const typeIn = (ch) => { e.preventDefault(); v.dispatch(v.state.tr.insertText(ch).scrollIntoView()); return true; };
      if (e.metaKey && e.altKey && e.shiftKey && (e.key === '?' || e.key === '/' || e.code === 'Slash')) { dead = null; return typeIn('¿'); }
      if (e.metaKey && e.altKey && e.shiftKey && (e.key === '!' || e.key === '1' || e.code === 'Digit1')) { dead = null; return typeIn('¡'); }
      const d = accentDead(e); if (d) { e.preventDefault(); dead = d; return true; }
      if (dead && !['Shift', 'Control', 'Alt', 'Meta'].includes(e.key)) { const ch = ACCENT_KEYS[dead][e.key]; dead = null; if (ch && !e.ctrlKey && !e.altKey && !e.metaKey) return typeIn(ch); }
      const mod = e.metaKey || e.ctrlKey;
      if (e.key === 'Escape') { e.preventDefault(); post({ t: 'key', name: 'done' }); return true; }
      if (mod && e.key === 'Enter') { e.preventDefault(); post({ t: 'key', name: 'writing' }); return true; }
      if (mod && !e.shiftKey && (e.key === 'f' || e.key === 'F')) { e.preventDefault(); post({ t: 'key', name: 'find' }); return true; }
      if (mod && !e.shiftKey && (e.key === 'k' || e.key === 'K')) { e.preventDefault(); post({ t: 'key', name: 'link' }); return true; }
      if (mod && e.shiftKey && (e.key === '!' || e.code === 'Digit1')) { e.preventDefault(); return R.setStyle('title')(v.state, v.dispatch); }
      if (mod && e.shiftKey && (e.key === '>' || e.key === '.' || e.code === 'Period')) { e.preventDefault(); return R.setStyle('quote')(v.state, v.dispatch); }
      if (mod && !e.shiftKey && !e.altKey && STYLES[e.key]) { e.preventDefault(); return R.setStyle(STYLES[e.key])(v.state, v.dispatch); }
      return false;
    },
    handleDOMEvents: {
      // the system's own Bold / Italic / Underline (the edit menu's Format, ⌘B when the app doesn't take it): the doc's marks, not the page's
      beforeinput(v, e) {
        const mark = { formatBold: 'b', formatItalic: 'i', formatUnderline: 'u', formatStrikeThrough: 's' }[e.inputType];
        if (!mark) return false;
        e.preventDefault(); R.toggleMark(mark)(v.state, v.dispatch); return true;
      },
    },
  },
});

// ---------------------------------------------------------------------------------------------------- telling the app
let stateT = 0, sizeT = 0;
function stateSoon() { if (!stateT) stateT = requestAnimationFrame(() => { stateT = 0; tellState(); }); }
function sizeSoon() { if (!sizeT) sizeT = requestAnimationFrame(() => { sizeT = 0; tellSize(); }); }
function tellState() {
  if (!view) return;
  const st = view.state, M = (n) => R.markActive(st, n);
  const node = st.doc, c = richCount(node);
  let caret = null;
  try { const r = view.coordsAtPos(st.selection.head); caret = { x: r.left + window.scrollX, y: r.top + window.scrollY, h: r.bottom - r.top }; } catch {}
  const hl = R.markAttrs(st, 'hl'), col = R.markAttrs(st, 'color'), link = R.markAttrs(st, 'link');
  post({
    t: 'state', style: R.styleAt(st), list: R.listAt(st),
    marks: { b: M('b'), i: M('i'), u: M('u'), s: M('s'), code: M('code'), sup: M('sup'), sub: M('sub') },
    hl: hl ? hl.c : null, color: col ? col.c : null, link: link ? link.href : null,
    canUndo: undoDepth(st) > 0, canRedo: redoDepth(st) > 0, sel: selMd(), empty: st.selection.empty, words: c.words, chars: c.chars, caret,
  });
}
function tellSize() {
  if (!view) return;
  const e = host();
  post({ t: 'size', w: Math.ceil(e.scrollWidth), h: Math.ceil(e.getBoundingClientRect().height) });
}

// ---------------------------------------------------------------------------------------------------- the editor
function dispatchTransaction(tr) {
  const remote = !!tr.getMeta('remote');
  view.updateState(view.state.apply(tr));
  if (tr.docChanged) {
    const doc = { header: held.doc.header, docs: { ...held.doc.docs, [tab]: view.state.doc } };
    if (remote) held = { doc, md: held.md }; // (the app set the words: it holds them as it sent them)
    else { held = { doc, md: mdOf(doc) }; post({ t: 'change', md: held.md }); }
    sizeSoon();
  }
  stateSoon();
}

window.rich = {
  // open: { md (the block's words as the app holds them), jsonl (its .jsonl as last read or written, for ids), look, chem, review, locked,
  // lang, caret: 'start' | 'end' | 'all' | { loc, len } (markdown offsets) | { x, y } (a point in the page), marked: [[from, to]], focus }
  open(o) {
    if (view) { view.destroy(); view = null; }
    let prev = null;
    if (o.jsonl) try { const d = readDoc(o.jsonl); prev = { doc: d, md: mdOf(d) }; } catch {}
    const md = String(o.md == null ? '' : o.md);
    const doc = docForMd(md, prev);
    held = { doc, md }; tab = tabOf(doc); mapCache = null;
    opts = { chem: o.chem !== false, review: !!o.review, locked: !!o.locked };
    marked = o.marked || [];
    setLook(o.look);
    const node = doc.docs[tab] || schema.nodes.doc.create(null, [schema.nodes.paragraph.create()]);
    const state = R.richState(node, { chem: () => opts.chem, plugins: [keys, listDeco, markedPlugin, reviewPlugin(() => opts.review), lockPlugin(() => opts.locked)] });
    const ed = host(); ed.textContent = '';
    view = new EditorView(ed, {
      state, dispatchTransaction,
      nodeViews: { math: (n) => new MathView(n), mathin: (n) => new MathView(n) },
      attributes: { spellcheck: 'true', autocapitalize: 'sentences', autocorrect: 'on' },
    });
    if (o.lang) view.dom.lang = o.lang;
    const st = view.state;
    let sel = TextSelection.atEnd(st.doc);
    if (o.caret === 'start') sel = TextSelection.atStart(st.doc);
    else if (o.caret === 'all') sel = new AllSelection(st.doc);
    else if (o.caret && o.caret.loc != null) { const a = posFromMd(o.caret.loc), b = posFromMd(o.caret.loc + (o.caret.len || 0), -1); sel = TextSelection.between(st.doc.resolve(Math.min(a, b)), st.doc.resolve(Math.max(a, b))); }
    else if (o.caret && o.caret.x != null) { const p = view.posAtCoords({ left: o.caret.x, top: o.caret.y }); if (p) sel = TextSelection.near(st.doc.resolve(p.pos)); }
    view.dispatch(st.tr.setSelection(sel).setMeta('addToHistory', false));
    if (o.focus !== false) view.focus();
    tellSize(); tellState();
    return true;
  },
  close() { if (view) { view.dom.blur(); view.destroy(); view = null; } held = null; return true; },
  focus() { if (view) view.focus(); return true; },
  blur() { if (view) view.dom.blur(); return true; },
  setLook(L) { setLook(L); return true; },
  setOpts(o) { Object.assign(opts, o || {}); if (o && o.lang != null && view) view.dom.lang = o.lang || ''; if (view) view.dispatch(view.state.tr.setMeta(MARKED, true)); return true; },
  setMarked(list) { marked = list || []; if (view) view.dispatch(view.state.tr.setMeta(MARKED, true)); return true; },
  // the app's own edit of the words (a Review button, Spanish's Correct, a task chip...): `md` with the selection at { loc, len }, one undo step
  setMd(md, loc, len) {
    if (!view) return false;
    md = String(md);
    const next = docForMd(md, held);
    const t = blockTransform(view.state.doc, next.docs[tab] || next.docs[tabOf(next)]);
    const tr = view.state.tr; for (const s of t.steps) tr.step(s);
    tr.setMeta(REVIEW, true); // (already as Review mode writes it; and it goes through a locked draft's filter like Review's own)
    held = { doc: { header: next.header, docs: { ...held.doc.docs, [tab]: tr.doc } }, md };
    mapCache = null;
    if (loc != null) { const a = posFromMdIn(tr.doc, next, md, loc), b = posFromMdIn(tr.doc, next, md, loc + (len || 0), -1); try { tr.setSelection(TextSelection.between(tr.doc.resolve(Math.min(a, b)), tr.doc.resolve(Math.max(a, b)))); } catch {} }
    view.dispatch(closeHistory(tr.scrollIntoView()));
    return true;
  },
  // the other device's words merged in (the app merged them): the doc made to say `md`, ids kept, the caret staying where they didn't
  // change anything; not an undo step
  remote(md) {
    if (!view) return false;
    md = String(md);
    const next = docForMd(md, held);
    const t = blockTransform(view.state.doc, next.docs[tab] || next.docs[tabOf(next)]);
    held = { doc: { header: next.header, docs: { ...held.doc.docs, [tab]: view.state.doc } }, md };
    mapCache = null;
    if (!t.steps.length) { stateSoon(); return true; }
    const tr = view.state.tr; for (const s of t.steps) tr.step(s);
    view.dispatch(tr.setMeta('addToHistory', false).setMeta('remote', true));
    return true;
  },
  select(loc, len) {
    if (!view) return false;
    const a = posFromMd(loc), b = posFromMd(loc + (len || 0), -1);
    view.dispatch(view.state.tr.setSelection(TextSelection.between(view.state.doc.resolve(Math.min(a, b)), view.state.doc.resolve(Math.max(a, b)))).scrollIntoView());
    view.focus();
    return true;
  },
  // the bar's and the keys' actions -> whether it did something
  cmd(name, arg) {
    if (!view) return false;
    const run = (c) => { const ok = c(view.state, view.dispatch); view.focus(); return !!ok; };
    switch (name) {
      case 'bold': return run(R.toggleMark('b'));
      case 'italic': return run(R.toggleMark('i'));
      case 'underline': return run(R.toggleMark('u'));
      case 'strike': return run(R.toggleMark('s'));
      case 'code': return run(R.toggleMark('code'));
      case 'sup': return run(R.toggleMark('sup'));
      case 'sub': return run(R.toggleMark('sub'));
      case 'highlight': return run(R.highlight(arg || 'yellow'));
      case 'color': return run(R.textColor(arg || null));
      case 'bullets': return run(R.toggleList('bullet'));
      case 'numbers': return run(R.toggleList('number'));
      case 'checklist': return run(R.toggleList('check'));
      case 'style': return run(R.setStyle(arg));
      case 'title': case 'h1': case 'h2': case 'h3': case 'body': case 'quote': return run(R.setStyle(name));
      case 'codeblock': return run(R.setStyle('code'));
      case 'indent': return run(R.indent(1));
      case 'outdent': return run(R.indent(-1));
      case 'align': return run(R.setAlign(arg || 'left'));
      case 'link': return run(R.setLink(arg || null));
      case 'dead': dead = ACCENT_KEYS[arg] ? arg : null; view.focus(); return true; // a native accent key (the app's key list took it first)
      case 'undo': return run(undo);
      case 'redo': return run(redo);
      case 'divider': { view.dispatch(view.state.tr.replaceSelectionWith(schema.nodes.divider.create()).scrollIntoView()); view.focus(); return true; }
      case 'insert': { if (!arg) return false; view.dispatch(view.state.tr.insertText(String(arg)).scrollIntoView()); view.focus(); return true; }
      // a link typed in: arg { text, href } at the caret (the bar's Link with nothing selected)
      case 'insertLink': {
        if (!arg || !arg.href) return false;
        const t = String(arg.text || arg.href), { from } = view.state.selection;
        const tr = view.state.tr.insertText(t); tr.addMark(from, from + t.length, schema.marks.link.create({ href: String(arg.href) })).removeStoredMark(schema.marks.link);
        view.dispatch(tr.scrollIntoView()); view.focus(); return true;
      }
      case 'selectAll': { view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc))); view.focus(); return true; }
      default: return false;
    }
  },
  // the selection's words as plain text
  selected() { if (!view) return ''; const { from, to } = view.state.selection; return view.state.doc.textBetween(from, to, '\n', ' '); },
  // rectangles of markdown ranges in the page (for the Writing view's comment cards and going to a comment): [{ x, y, w, h } | null]
  rects(list) {
    if (!view) return [];
    return (list || []).map(([a, b]) => {
      const r = docRange(a, b); if (!r) return null;
      try { const s = view.coordsAtPos(r.from), e = view.coordsAtPos(Math.max(r.from, r.to), -1); return { x: s.left + window.scrollX, y: s.top + window.scrollY, w: Math.max(1, e.right - s.left), h: Math.max(e.bottom, s.bottom) - s.top }; } catch { return null; }
    });
  },
  state() { tellState(); return true; },
};
// a markdown offset as a place in a doc that isn't the editor's yet (setMd's)
function posFromMdIn(node, doc, md, o, bias = 1) {
  try { return Math.max(0, Math.min(posAt(richMap({ header: doc.header, docs: { ...doc.docs, [tab]: node } }, tab, md), o, bias), node.content.size)); } catch { return node.content.size; }
}

new ResizeObserver(() => sizeSoon()).observe(document.getElementById('ed'));
document.addEventListener('selectionchange', () => stateSoon());
post({ t: 'loaded' });
