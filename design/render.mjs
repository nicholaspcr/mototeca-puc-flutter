#!/usr/bin/env node
// Renders each .dc.html artboard to a standalone static HTML, then screenshots it
// with headless Chrome at phone size. Keeps the artboards as the single source of
// truth for both the published canvas and the PDF images.
//
//   node render.mjs [--out <dir>] [--scale 3]

import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const outDir = resolve(argVal('--out') ?? join(HERE, 'exports'));
const scale = argVal('--scale') ?? '3';
const viewportOnly = args.includes('--viewport');
const W = 393, H = 852;

function argVal(flag) {
  const i = args.indexOf(flag);
  return i === -1 ? undefined : args[i + 1];
}

// Screens in flow order, with optional setup that drives the artboard's own logic
// into the state worth capturing (instead of a blank initial state).
const SCREENS = [
  { file: 'Main.dc.html', name: '01-login' },
  { file: 'WorkshopRegister.dc.html', name: '02-cadastro-oficina' },
  { file: 'Dashboard.dc.html', name: '03-painel-oficina' },
  {
    file: 'NewRecord.dc.html', name: '04-novo-registro',
    setup: `c.setState({ nrPlateQuery: 'ABC1D23' }); c.nrSearch();
            c.setState({ nrOps: ['Troca de óleo e filtro'], nrCost: '245.00',
                         nrParts: [{ name: 'Óleo 10w30', qty: 1, cost: '62.00' }] });`,
  },
  { file: 'VehicleRegister.dc.html', name: '05-cadastro-veiculo' },
  { file: 'MyVehicles.dc.html', name: '06-minhas-motos' },
  {
    file: 'CustomerPortal.dc.html', name: '07-portal-proprietario',
    setup: `c.setState({ custPlateQuery: 'ABC1D23' }); c.custSearch();`,
  },
  { file: 'ServiceDetail.dc.html', name: '08-detalhe-servico' },
  { file: 'Reminders.dc.html', name: '09-lembretes' },
  { file: 'About.dc.html', name: '10-sobre' },
];

// Minimal stand-in for the design-canvas runtime: resolves {{ dotted.paths }},
// <sc-if>, <sc-for> and <x-import> against the artboard's own Component class.
const SHIM = String.raw`
class DCLogic {
  constructor() { this.props = {}; this.state = {}; }
  setState(patch, cb) { Object.assign(this.state, patch); if (cb) cb(); }
  forceUpdate() {}
  renderVals() { return {}; }
}
window.DCLogic = DCLogic;

const HOLE = /\{\{\s*([^}]+?)\s*\}\}/g;

function lookup(scope, path) {
  if (path === 'true') return true;
  if (path === 'false') return false;
  return path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), scope);
}

function styleFromObject(obj) {
  return Object.entries(obj)
    .filter(([, v]) => v != null && v !== '')
    .map(([k, v]) => {
      const prop = k.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase());
      const needsPx = typeof v === 'number' &&
        !/^(flex|flexGrow|flexShrink|opacity|zIndex|fontWeight|lineHeight|order)$/.test(k);
      return prop + ':' + (needsPx ? v + 'px' : v);
    })
    .join(';');
}

function renderAttrs(el, scope) {
  for (const attr of Array.from(el.attributes)) {
    const { name, value } = attr;
    const whole = value.match(/^\{\{\s*([^}]+?)\s*\}\}$/);
    if (whole) {
      const val = lookup(scope, whole[1].trim());
      if (typeof val === 'function') { el.removeAttribute(name); continue; }
      if (val && typeof val === 'object') { el.setAttribute(name, styleFromObject(val)); continue; }
      el.setAttribute(name, val == null ? '' : String(val));
      continue;
    }
    if (HOLE.test(value)) {
      HOLE.lastIndex = 0;
      el.setAttribute(name, value.replace(HOLE, (_, p) => {
        const v = lookup(scope, p.trim());
        return v == null ? '' : String(v);
      }));
    }
  }
  // Inputs render their value as an attribute so it survives the screenshot.
  if (el.tagName === 'INPUT' && el.hasAttribute('value')) el.value = el.getAttribute('value');
}

function renderNode(node, scope) {
  if (node.nodeType === Node.TEXT_NODE) {
    if (node.nodeValue.includes('{{')) {
      node.nodeValue = node.nodeValue.replace(HOLE, (_, p) => {
        const v = lookup(scope, p.trim());
        return v == null ? '' : String(v);
      });
    }
    return;
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return;

  const tag = node.tagName.toLowerCase();

  if (tag === 'sc-if') {
    const expr = (node.getAttribute('value') || '').replace(/[{}]/g, '').trim();
    const keep = !!lookup(scope, expr);
    const frag = document.createDocumentFragment();
    if (keep) {
      for (const child of Array.from(node.childNodes)) { renderNode(child, scope); frag.appendChild(child); }
    }
    node.replaceWith(frag);
    return;
  }

  if (tag === 'sc-for') {
    const listExpr = (node.getAttribute('list') || '').replace(/[{}]/g, '').trim();
    const as = node.getAttribute('as') || 'item';
    const list = lookup(scope, listExpr) || [];
    const template = Array.from(node.childNodes);
    const frag = document.createDocumentFragment();
    list.forEach((item, i) => {
      for (const child of template) {
        const clone = child.cloneNode(true);
        renderNode(clone, { ...scope, [as]: item, $index: i });
        frag.appendChild(clone);
      }
    });
    node.replaceWith(frag);
    return;
  }

  if (tag === 'x-import') {
    // Image slots are interactive uploaders in the canvas; print a neutral placeholder.
    const ph = document.createElement('div');
    ph.setAttribute('style',
      'height:100%;min-height:90px;border:1px dashed #E2E8F0;border-radius:8px;background:#F8FAFC;' +
      'display:flex;align-items:center;justify-content:center;color:#94A3B8;font-size:11px;');
    ph.textContent = node.getAttribute('placeholder') || 'Foto';
    node.replaceWith(ph);
    return;
  }

  renderAttrs(node, scope);
  for (const child of Array.from(node.childNodes)) renderNode(child, scope);
}

window.__dcRender = function (ComponentClass, setup) {
  let vals = {};
  if (ComponentClass) {
    const c = new ComponentClass();
    if (!c.state) c.state = {};
    if (setup) setup(c);
    vals = c.renderVals ? c.renderVals() : {};
  }
  const root = document.getElementById('__dc_root');
  for (const child of Array.from(root.childNodes)) renderNode(child, vals);
  document.documentElement.setAttribute('data-dc-rendered', '1');
  // Reported back through the title so the renderer can size a full-content capture.
  const frame = root.firstElementChild;
  document.title = 'H:' + Math.ceil(frame ? frame.scrollHeight : 0);
};
`;

function section(src, tag) {
  const m = src.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, 'i'));
  return m ? m[1] : '';
}

function buildStatic(src, setup, { full = false } = {}) {
  const helmet = section(src, 'helmet');
  let body = section(src, 'x-dc').replace(/<helmet[\s\S]*?<\/helmet>/i, '');
  const logic = (src.match(/<script[^>]*data-dc-script[^>]*>([\s\S]*?)<\/script>/i) || [, ''])[1];
  const setupFn = setup ? `function (c) { ${setup} }` : 'null';
  // Full captures let the frame grow past the viewport so nothing is cut off.
  const frameCss = full
    ? '#__dc_root>div{height:auto !important;min-height:852px;overflow:visible !important}'
    : '#__dc_root>div{overflow:hidden !important}';

  return `<!doctype html>
<html><head><meta charset="utf-8">
${helmet}
<style>html,body{margin:0;padding:0;overflow:hidden}${frameCss}</style>
</head>
<body>
<div id="__dc_root">${body}</div>
<script>${SHIM}<\/script>
<script>
${logic}
try {
  window.__dcRender(typeof Component !== 'undefined' ? Component : null, ${setupFn});
} catch (err) {
  document.title = 'RENDER_ERROR: ' + err.message;
  document.documentElement.setAttribute('data-dc-error', err.message);
}
<\/script>
</body></html>`;
}

mkdirSync(outDir, { recursive: true });
const tmp = join(outDir, '.html');
mkdirSync(tmp, { recursive: true });

function chrome(argv) {
  return execFileSync('google-chrome', [
    '--headless', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
    '--virtual-time-budget=3000', ...argv,
  ], { stdio: 'pipe', timeout: 90_000, maxBuffer: 64 * 1024 * 1024 }).toString();
}

let failures = 0;
for (const screen of SCREENS) {
  const src = readFileSync(join(HERE, screen.file), 'utf8');
  const probePath = join(tmp, screen.name + '.probe.html');
  const htmlPath = join(tmp, screen.name + '.html');
  const png = join(outDir, screen.name + '.png');

  try {
    // Pass 1: measure the artboard's real content height.
    writeFileSync(probePath, buildStatic(src, screen.setup, { full: true }));
    const dom = chrome([`--window-size=${W},${H}`, '--dump-dom', 'file://' + probePath]);
    const err = dom.match(/data-dc-error="([^"]*)"/);
    if (err) throw new Error('render error: ' + err[1]);
    const measured = Number((dom.match(/<title>H:(\d+)<\/title>/) || [, 0])[1]);
    // --viewport keeps every capture at phone height for a uniform catalogue.
    const height = viewportOnly ? H : Math.max(H, measured);

    // Pass 2: capture at full content height so nothing is truncated.
    writeFileSync(htmlPath, buildStatic(src, screen.setup, { full: height > H }));
    chrome([
      `--force-device-scale-factor=${scale}`,
      `--window-size=${W},${height}`,
      `--screenshot=${png}`,
      'file://' + htmlPath,
    ]);
    console.log(`ok   ${screen.name}.png  ${W}x${height}${height > H ? ' (rolável)' : ''}`);
  } catch (err) {
    failures++;
    console.error(`FAIL ${screen.name}: ${err.message.split('\n')[0]}`);
  }
}

rmSync(tmp, { recursive: true, force: true });
console.log(failures ? `${failures} screen(s) failed` : `${SCREENS.length} screens rendered to ${outDir}`);
process.exit(failures ? 1 : 0);
