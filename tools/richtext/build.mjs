// Builds the iPad's copy of the laptop's rich-text code (nexus docs/rich-text.md) from a nexus checkout with its node_modules installed:
//   - Packages/NexusCore/Sources/NexusCore/Resources/richcore.js: the converters (a block's .jsonl and its .md copy), run by RichWords.swift
//     in JavaScriptCore, with no web page (tools/richtext/core.js);
//   - Resources/RichText/rich.html: the block editor page (ProseMirror, the laptop's commands and typing rules, KaTeX), hosted by
//     Sources/Writing/RichEditor.swift in a web view (tools/richtext/editor.js, page.css), KaTeX's fonts beside it.
// Run it again when the laptop's rich-text code changes:
//   cd tools/richtext && npm install --no-save esbuild && node build.mjs <path to nexus>      (nexus: npm ci there first)
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const here = path.dirname(new URL(import.meta.url).pathname);
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const src = path.join(nexus, 'renderer', 'src');
const mobile = path.resolve(here, '..', '..');
const coreOut = path.join(mobile, 'Packages', 'NexusCore', 'Sources', 'NexusCore', 'Resources');
const pageOut = path.join(mobile, 'Resources', 'RichText');
const req = createRequire(path.join(nexus, 'package.json'));
const katexDir = path.dirname(req.resolve('katex/package.json'));
let rev = process.env.NEXUS_REV || '';
if (!rev) try { rev = execSync('git rev-parse --short HEAD', { cwd: nexus, encoding: 'utf8' }).trim(); } catch { rev = path.basename(nexus); }

// nexus/... is the laptop's renderer/src; every package (prosemirror-*, yaml, katex) comes from the laptop's node_modules, at its versions
const nexusPlugin = {
  name: 'nexus',
  setup(b) {
    b.onResolve({ filter: /^nexus\// }, (a) => ({ path: path.join(src, a.path.slice(6)) }));
  },
};
const bundle = async (entry, fmt) => (await build({ entryPoints: [path.join(here, entry)], bundle: true, format: fmt, minify: true, write: false, plugins: [nexusPlugin], nodePaths: [path.join(nexus, 'node_modules')], platform: 'browser', loader: { '.css': 'empty' }, target: 'safari17', legalComments: 'none', charset: 'utf8' })).outputFiles[0].text;

// ---- the converters, for JavaScriptCore
const core = await bundle('core.js', 'iife');
fs.mkdirSync(coreOut, { recursive: true });
fs.writeFileSync(path.join(coreOut, 'richcore.js'), `// Built by tools/richtext/build.mjs from nexus ${rev}. Do not edit by hand.\n` + core);

// ---- the editor page
const js = await bundle('editor.js', 'iife');
fs.rmSync(pageOut, { recursive: true, force: true });
fs.mkdirSync(path.join(pageOut, 'fonts'), { recursive: true });
for (const f of fs.readdirSync(path.join(katexDir, 'dist', 'fonts'))) if (f.endsWith('.woff2')) fs.copyFileSync(path.join(katexDir, 'dist', 'fonts', f), path.join(pageOut, 'fonts', f));
const katexCss = fs.readFileSync(path.join(katexDir, 'dist', 'katex.min.css'), 'utf8').replace(/src:url\((fonts\/[^)]+\.woff2)\) format\("woff2"\)[^;}]*/g, 'src:url($1) format("woff2")');
const pageCss = fs.readFileSync(path.join(here, 'page.css'), 'utf8');
const html = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<!-- Built by tools/richtext/build.mjs from nexus ${rev}. Do not edit by hand. -->
<style>${katexCss}</style>
<style>${pageCss}</style>
<style id="look"></style>
</head><body><div id="ed"></div><script>${js}</script></body></html>
`;
fs.writeFileSync(path.join(pageOut, 'rich.html'), html);
console.log('wrote richcore.js', (core.length / 1024).toFixed(0) + ' KB; rich.html', (html.length / 1024).toFixed(0) + ' KB; from nexus', rev);
