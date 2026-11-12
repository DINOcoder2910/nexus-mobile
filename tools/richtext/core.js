// A typed block's two files on the iPad, with the laptop's own code (nexus docs/rich-text.md): text/<id>.jsonl (what Nexus keeps) and the
// .md copy (the words the board and the block editor hold). NexusCore's RichWords.swift runs this in JavaScriptCore, with no web page, so
// the iPad reads and writes the same .jsonl the laptop and the hub's Google Docs bridge do, keeping paragraph ids, who wrote what and the
// header (the Google link, tabs). Built by tools/richtext/build.mjs from a nexus checkout into Packages/NexusCore/Sources/NexusCore/Resources.
// Every function takes and gives strings (JSON for objects), so the Swift side needs nothing but JSValue.toString.
import { readWords, writeWords, docForMd, copyBody, splitCopy } from 'nexus/board/richblock.js';
import { readDoc } from 'nexus/board/richfile.js';
import { docToMd } from 'nexus/board/richmd.js';

const out = (v) => JSON.stringify(v);
const opt = (s) => (s == null || s === '' ? null : s);
// the doc a .jsonl and the words it was last read or written with stand for, or null (none yet, or it can't be read)
function prevOf(jsonl, md) {
  if (!opt(jsonl)) return null;
  try { const doc = readDoc(jsonl); return { doc, md: md == null ? docToMd(doc.header, doc.docs).replace(/\n$/, '') : md }; } catch { return null; }
}

globalThis.NexusRichCore = {
  // what is on disk (either may be null) -> { md, how, stale } as richblock.js readWords: md the block's words; how 'json' | 'outside' |
  // 'converted' | 'new'; stale: the .jsonl should be written again. by / at: whom to credit paragraphs a hand edit of the copy changed.
  read(jsonl, file, by, at) {
    try {
      const r = readWords(opt(jsonl), file == null ? null : file, { by: by || 'outside', at: at || null });
      return out({ ok: true, md: r.md, how: r.how, stale: r.stale });
    } catch (e) { return out({ ok: false, md: copyBody(file), error: String(e && e.message || e) }); }
  },
  // the .jsonl for the words `md`, the doc following them keeping ids (prevJsonl: the .jsonl as last read or written, prevMd: the words it
  // held then). by / at: who changed the paragraphs that changed, and when. -> { ok, jsonl }
  write(md, prevJsonl, prevMd, by, at) {
    try {
      const doc = docForMd(String(md == null ? '' : md), prevOf(prevJsonl, prevMd), { by: by || 'iPad', at: at || null });
      return out({ ok: true, jsonl: writeWords(doc, String(md == null ? '' : md)).jsonl });
    } catch (e) { return out({ ok: false, error: String(e && e.message || e) }); }
  },
  // a header change (the Google link) on the .jsonl, the words kept: key, value (JSON; null removes it) -> { ok, jsonl }
  setHeader(jsonl, key, valueJson) {
    try {
      const d = readDoc(jsonl), v = valueJson == null ? null : JSON.parse(valueJson);
      const header = { ...d.header }; if (v == null) delete header[key]; else header[key] = v;
      const md = docToMd(d.header, d.docs).replace(/\n$/, '');
      return out({ ok: true, jsonl: writeWords({ header, docs: d.docs }, md).jsonl });
    } catch (e) { return out({ ok: false, error: String(e && e.message || e) }); }
  },
  // a .jsonl's words, as the block holds them (no last line end) -> { ok, md, header }
  words(jsonl) {
    try { const d = readDoc(jsonl); return out({ ok: true, md: docToMd(d.header, d.docs).replace(/\n$/, ''), header: d.header }); } catch (e) { return out({ ok: false, error: String(e && e.message || e) }); }
  },
  // a copy's file -> { body, nexus } (its checksum line taken off; nexus: Nexus wrote it)
  copy(file) { return out(splitCopy(file)); },
};
