// The iPad's copy of the laptop's renderers (Sources/Render/WebRender.swift loads it in a hidden web view, offline): KaTeX at the
// laptop's version for maths SwiftMath can't read, and the tutor's chemistry diagrams drawn by the laptop's own code (the Molecules tool's
// Lewis structure, the VSEPR chart's shape, the Born–Haber cycle), frozen to PNG as nexus renderer/src/app/tutorboard.js does.
// Built by tools/render/build.mjs from a nexus checkout; the chem part below follows tutorboard.js's chemSvg / freezeSvg / svgToPng.
import katex from 'katex';
import { diagram, cellAt } from 'nexus/studyvsepr.js';
import { cycle, cycleSvg, COMPOUNDS } from 'nexus/studyenthalpy.js';
import { createMolTool } from 'nexus/app/studymol.js';
import { MOL_CSS } from 'nexus/app/studymolpage.js';
import { h } from 'nexus/ui.js';

// ---- maths: KaTeX into #out, its box measured for the app's snapshot
window.nexusMath = async (tex, display, size, color) => {
  const out = document.getElementById('out');
  out.style.fontSize = size + 'px'; out.style.color = color || '#000';
  try { out.innerHTML = katex.renderToString(String(tex), { displayMode: !!display, throwOnError: true, strict: 'ignore' }); } catch (e) { out.innerHTML = ''; return { ok: false, error: String(e && e.message || e) }; }
  await document.fonts.ready; // the fonts this formula uses load now; measure once they're in
  const r = out.getBoundingClientRect();
  return { ok: true, x: r.left, y: r.top, w: Math.ceil(r.width), h: Math.ceil(r.height) };
};
window.nexusFontsReady = () => document.fonts.ready.then(() => true);

// ---- chemistry diagrams
const SUB = { 0: '₀', 1: '₁', 2: '₂', 3: '₃', 4: '₄', 5: '₅', 6: '₆', 7: '₇', 8: '₈', 9: '₉' };
let MOL = null;
const molTool = () => MOL || (MOL = createMolTool(h('div'), {}));
function chemSvg(s) {
  if (s.kind === 'lewis') { const svg = molTool().lewisFor(s.molecule); return svg ? { svg, vars: molVars() } : null; }
  if (s.kind === 'vsepr') {
    const cell = s.bp != null ? cellAt(s.bp, s.lp) : molTool().vseprCellOf(s.molecule);
    return cell ? { svg: diagram(cell, { size: 220, mode: 'mg' }) } : null;
  }
  if (s.kind === 'cycle') {
    const f = String(s.compound || '').replace(/\d/g, (d) => SUB[d]);
    const c = COMPOUNDS.find((x) => x.f.toLowerCase() === f.toLowerCase());
    return c ? { svg: cycleSvg(cycle(c.f)) } : null;
  }
  return null;
}
let LIGHT = null, MOLV = null;
function lightVars() {
  if (LIGHT) return LIGHT; LIGHT = [];
  for (const sh of document.styleSheets) { let rules; try { rules = sh.cssRules; } catch { continue; } for (const r of rules) if (r.selectorText === ':root' && r.style) for (const p of r.style) if (p.startsWith('--')) LIGHT.push([p, r.style.getPropertyValue(p)]); }
  return LIGHT;
}
function molVars() {
  if (MOLV) return MOLV;
  const m = /:host\{([^}]*)\}/.exec(MOL_CSS); MOLV = [];
  if (m) for (const d of m[1].split(';')) { const k = d.indexOf(':'); const p = d.slice(0, k).trim(); if (p.startsWith('--')) MOLV.push([p, d.slice(k + 1).trim()]); }
  return MOLV;
}
const PAINT = ['fill', 'fill-opacity', 'stroke', 'stroke-width', 'stroke-opacity', 'stroke-dasharray', 'stroke-linecap', 'stroke-linejoin', 'opacity', 'font-family', 'font-size', 'font-weight', 'font-style', 'font-variant-numeric', 'text-anchor', 'dominant-baseline', 'paint-order'];
function freezeSvg(svgText, vars = []) {
  const host = h('div', { 'aria-hidden': 'true', style: 'position:fixed;left:-12000px;top:0;pointer-events:none' });
  for (const [p, v] of [...lightVars(), ...vars]) host.style.setProperty(p, v);
  host.innerHTML = svgText; document.body.append(host);
  try {
    const svg = host.querySelector('svg'); if (!svg) return null;
    const vb = svg.viewBox && svg.viewBox.baseVal, W = (vb && vb.width) || +svg.getAttribute('width') || 300, H = (vb && vb.height) || +svg.getAttribute('height') || 300;
    const clone = svg.cloneNode(true), src = [svg, ...svg.querySelectorAll('*')], dst = [clone, ...clone.querySelectorAll('*')];
    src.forEach((e, i) => {
      const cs = getComputedStyle(e), d = dst[i];
      for (const a of [...d.attributes]) if (/var\(/.test(a.value)) d.removeAttribute(a.name);
      for (const p of PAINT) { const v = cs.getPropertyValue(p); if (v) d.style.setProperty(p, v); }
    });
    clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg'); clone.setAttribute('width', W); clone.setAttribute('height', H); clone.removeAttribute('class');
    return { svg: new XMLSerializer().serializeToString(clone), w: W, h: H };
  } finally { host.remove(); }
}
async function svgToPng(svg, w, hh, scale = 3) {
  const img = new Image(); img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg); await img.decode();
  const cv = document.createElement('canvas'); cv.width = Math.round(w * scale); cv.height = Math.round(hh * scale);
  cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
  return cv.toDataURL('image/png').replace(/^data:image\/png;base64,/, '');
}
// the picture of a tutor chem step ({kind, molecule | compound | bp, lp}): { png (base64), w, h } in board units, or { error }
window.nexusChem = async (s) => {
  let c = null; try { c = chemSvg(s || {}); } catch (e) { return { error: String(e && e.message || e) }; }
  if (!c || !c.svg) return { error: 'Nexus has no ' + (s && s.kind) + ' diagram for ' + ((s && (s.molecule || s.compound)) || (s && s.bp + '/' + s.lp)) };
  const f = freezeSvg(c.svg, c.vars || []); if (!f) return { error: 'no picture' };
  try { return { png: await svgToPng(f.svg, f.w, f.h), w: f.w, h: f.h }; } catch (e) { return { error: String(e && e.message || e) }; }
};
window.nexusRenderReady = true;
