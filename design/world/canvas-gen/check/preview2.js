// Like preview.js but renders nested <dc-import> components too.
const fs = require('fs');
const path = require('path');
const [file, out, propsJson, stateJson] = process.argv.slice(2);
// a preview is one still frame: timers (Doum's life on the oasis) never fire
global.setTimeout = () => 0;
const proj = path.dirname(file);
const blobMap = JSON.parse(fs.readFileSync(path.join(__dirname, 'blobmap.json'), 'utf8'));
class DCLogic { constructor(p) { this.props = p; this.state = null; } setState(s) { this.state = Object.assign({}, this.state || {}, s); } }
const styles = new Set();
const get = (vals, p) => p.split('.').reduce((a, k) => (a == null ? a : a[k]), vals);
function load(f) {
  const src = fs.readFileSync(f, 'utf8');
  const js = src.split('data-dc-script')[1].split("'>").slice(1).join("'>").split('</script>')[0];
  let markup = src.split('<x-dc>')[1].split('</x-dc>')[0];
  (markup.match(/<style>([\s\S]*?)<\/style>/g) || []).forEach((s) => styles.add(s.replace(/<\/?style>/g, '')));
  markup = markup.replace(/<helmet>[\s\S]*?<\/helmet>/, '');
  const Component = eval('(' + js.trim().replace(/^class Component extends DCLogic/, 'class extends DCLogic') + ')');
  return { markup, Component };
}
function fill(tpl, vals) {
  let prev;
  do {
    prev = tpl;
    tpl = tpl.replace(/<sc-for list="\{\{\s*([\w.]+)\s*\}\}" as="(\w+)"[^>]*>((?:(?!<sc-for)[\s\S])*?)<\/sc-for>/, (_, p, as, body) => {
      const list = get(vals, p) || [];
      return list.map((it) => fill(body, Object.assign({}, vals, { [as]: it }))).join('');
    });
  } while (tpl !== prev);
  do {
    prev = tpl;
    tpl = tpl.replace(/<sc-if value="\{\{\s*([\w.]+)\s*\}\}"[^>]*>((?:(?!<sc-if)[\s\S])*?)<\/sc-if>/, (_, p, body) => (get(vals, p) ? body : ''));
  } while (tpl !== prev);
  tpl = tpl.replace(/\s on\w+="\{\{[^}]*\}\}"/g, '');
  return tpl.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, p) => { const v = get(vals, p); return typeof v === 'function' ? '' : String(v); });
}
function render(f, props, state) {
  const { markup, Component } = load(f);
  const c = new Component(props);
  if (state) c.state = state;
  let html = fill(markup, c.renderVals());
  html = html.replace(/<dc-import name="(\w+)"([^>]*)>(<\/dc-import>)?/g, (_, name, attrs) => {
    const p = {};
    attrs.replace(/([\w-]+)="([^"]*)"/g, (m, k, v) => { p[k.replace(/-(\w)/g, (x, ch) => ch.toUpperCase())] = v; });
    return render(path.join(proj, name + '.dc.html'), p, null);
  });
  return html;
}
let html = render(file, JSON.parse(propsJson || '{}'), stateJson ? JSON.parse(stateJson) : null);
html = html.replace(/\/_blob\/([0-9a-f]{32})/g, (m, id) => (blobMap[id] ? 'file://' + blobMap[id] : m));
fs.writeFileSync(out, `<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:-apple-system,sans-serif}${[...styles].join('\n')}</style></head><body>${html}</body></html>`);
