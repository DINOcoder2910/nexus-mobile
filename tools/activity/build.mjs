// Builds the iPhone's and iPad's copy of the laptop's task Activity wording (nexus renderer/src/activity.js and what it imports) into
// Packages/NexusCore/Sources/NexusCore/Resources/activitycore.js, run by TaskActivity.swift in JavaScriptCore. Run it again when the
// laptop's activity.js changes:
//   cd tools/activity && npm install --no-save esbuild && node build.mjs <path to nexus>      (nexus: npm ci there first, or at least yaml)
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const here = path.dirname(new URL(import.meta.url).pathname);
const nexus = path.resolve(process.argv[2] || '../../../nexus');
const src = path.join(nexus, 'renderer', 'src');
const out = path.join(here, '..', '..', 'Packages', 'NexusCore', 'Sources', 'NexusCore', 'Resources');
let rev = process.env.NEXUS_REV || '';
if (!rev) try { rev = execSync('git rev-parse --short HEAD', { cwd: nexus, encoding: 'utf8' }).trim(); } catch { rev = path.basename(nexus); }

const nexusPlugin = { name: 'nexus', setup(b) { b.onResolve({ filter: /^nexus\// }, (a) => ({ path: path.join(src, a.path.slice(6)) })); } };
const r = await build({ entryPoints: [path.join(here, 'core.js')], bundle: true, format: 'iife', minify: true, write: false, plugins: [nexusPlugin],
  nodePaths: [path.join(nexus, 'node_modules')], platform: 'browser', target: 'safari17', legalComments: 'none', charset: 'utf8' });
const js = r.outputFiles[0].text;
fs.writeFileSync(path.join(out, 'activitycore.js'), `// Built by tools/activity/build.mjs from nexus ${rev}. Do not edit by hand.\n` + js);
console.log('wrote activitycore.js', (js.length / 1024).toFixed(0) + ' KB from nexus', rev);
