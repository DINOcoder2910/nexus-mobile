// Copies the laptop's study tool pages (nexus dist/tools/{molecules,vsepr,enthalpies}.html, which `node build.js` makes there) into
// Resources/Tools/, so the iPhone and iPad have the VSEPR chart, Enthalpies and Molecules before the laptop has sent its own copies to
// the data folder's .nexus-tools/ (which win when present: they follow the laptop). Run it again when the laptop's tools change:
//   (in nexus) node build.js   then   node tools/study-tools/copy.mjs <path to nexus>
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const here = path.dirname(new URL(import.meta.url).pathname);
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const from = path.join(nexus, 'dist', 'tools');
const out = path.resolve(here, '..', '..', 'Resources', 'Tools');
fs.mkdirSync(out, { recursive: true });
let rev = '';
try { rev = execSync('git rev-parse --short HEAD', { cwd: nexus, encoding: 'utf8' }).trim(); } catch { rev = '?'; }
for (const n of ['molecules', 'vsepr', 'enthalpies']) {
  const src = path.join(from, n + '.html');
  if (!fs.existsSync(src)) { console.error(`${src} is missing: run node build.js in ${nexus} first`); process.exit(1); }
  fs.copyFileSync(src, path.join(out, n + '.html'));
  console.log(`${n}.html  ${(fs.statSync(src).size / 1024).toFixed(0)} KB`);
}
fs.writeFileSync(path.join(out, 'VERSION'), `nexus ${rev}\n`);
