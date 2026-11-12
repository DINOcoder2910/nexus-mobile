// Builds Resources/Render/ (render.html with the script and styles inline, KaTeX's fonts beside it) from a nexus checkout, so the iPad
// draws maths and the tutor's chemistry diagrams with the laptop's own code. Run it again when the laptop's KaTeX or chemistry tools change:
//   cd tools/render && npm install --no-save katex@<the laptop's version> esbuild && node build.mjs <path to nexus>
// The stubs stand in for the laptop app modules the Molecules tool imports but the tutor's diagrams never use.
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const here = path.dirname(new URL(import.meta.url).pathname);
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const src = path.join(nexus, 'renderer', 'src');
const out = path.resolve(here, '..', '..', 'Resources', 'Render');
const req = createRequire(path.join(here, 'package.json'));
const katexDir = path.dirname(req.resolve('katex/package.json'));
let rev = process.env.NEXUS_REV || '';
if (!rev) try { rev = execSync('git rev-parse --short HEAD', { cwd: nexus, encoding: 'utf8' }).trim(); } catch { rev = path.basename(nexus); }
const version = JSON.parse(fs.readFileSync(path.join(katexDir, 'package.json'), 'utf8')).version;

const stub = (name) => path.join(here, 'stubs', name);
const nexusPlugin = {
  name: 'nexus',
  setup(b) {
    b.onResolve({ filter: /^nexus\// }, (a) => ({ path: path.join(src, a.path.slice(6)) }));
    b.onResolve({ filter: /^\.\/(state|store|studyvsepr)\.js$/ }, (a) => {
      if (path.resolve(a.resolveDir) !== path.join(src, 'app')) return null;
      const n = a.path.slice(2, -3);
      return { path: stub(n === 'studyvsepr' ? 'studyvsepr-app.js' : n + '.js') };
    });
    b.onResolve({ filter: /^yaml$/ }, () => ({ path: stub('yaml.js') }));
    b.onResolve({ filter: /^katex(\/.*)?$/ }, (a) => ({ path: req.resolve(a.path) }));
  },
};
const res = await build({ entryPoints: [path.join(here, 'entry.js')], bundle: true, format: 'iife', minify: true, write: false, plugins: [nexusPlugin], loader: { '.css': 'empty' }, target: 'safari17', legalComments: 'none' });
const js = res.outputFiles[0].text;

// KaTeX's stylesheet, its fonts as woff2 files beside the page
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, 'fonts'), { recursive: true });
for (const f of fs.readdirSync(path.join(katexDir, 'dist', 'fonts'))) if (f.endsWith('.woff2')) fs.copyFileSync(path.join(katexDir, 'dist', 'fonts', f), path.join(out, 'fonts', f));
const katexCss = fs.readFileSync(path.join(katexDir, 'dist', 'katex.min.css'), 'utf8')
  .replace(/src:url\((fonts\/[^)]+\.woff2)\) format\("woff2"\)[^;}]*/g, 'src:url($1) format("woff2")');
// the laptop's light colour tokens (:root) and the study tools' classes, which the chem diagrams are painted from
const styles = fs.readFileSync(path.join(nexus, 'renderer', 'styles.css'), 'utf8');
const roots = [...styles.matchAll(/(^|\n):root\s*\{[^}]*\}/g)].map((m) => m[0].trim()).join('\n');
const study = fs.readFileSync(path.join(nexus, 'renderer', 'study.css'), 'utf8');

const html = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<!-- Built by tools/render/build.mjs from nexus ${rev} (KaTeX ${version}). Do not edit by hand. -->
<style>${katexCss}</style>
<style>${roots}</style>
<style>${study}</style>
<style>html,body{margin:0;padding:0;background:transparent}#out{position:absolute;left:0;top:0;display:inline-block;padding:2px 4px;white-space:nowrap;font-family:KaTeX_Main,serif}#out .katex-display{margin:0}</style>
</head><body><div id="out"></div><script>${js}</script></body></html>
`;
fs.writeFileSync(path.join(out, 'render.html'), html);
console.log('wrote', path.relative(process.cwd(), out), (html.length / 1024).toFixed(0) + ' KB page,', fs.readdirSync(path.join(out, 'fonts')).length, 'fonts, KaTeX', version);
