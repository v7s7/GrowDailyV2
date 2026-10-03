// Renders a .dc.html for given props into a static html page with local images.
const fs = require('fs');
const path = require('path');
const [file, prefix, casesJson, stateJson] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
const js = src.split('data-dc-script')[1].split("'>").slice(1).join("'>").split('</script>')[0];
let markup = src.split('<x-dc>')[1].split('</x-dc>')[0];
const style = (markup.match(/<style>([\s\S]*?)<\/style>/) || [, ''])[1];
markup = markup.replace(/<helmet>[\s\S]*?<\/helmet>/, '');
const blobMap = JSON.parse(fs.readFileSync(path.join(__dirname, 'blobmap.json'), 'utf8'));
class DCLogic { constructor(p) { this.props = p; this.state = null; } setState(s) { this.state = Object.assign({}, this.state || {}, s); } }
const Component = eval('(' + js.trim().replace(/^class Component extends DCLogic/, 'class extends DCLogic') + ')');
const get = (vals, p) => p.split('.').reduce((a, k) => (a == null ? a : a[k]), vals);
function fill(tpl, vals) {
  // sc-for (innermost first, non-nested assumption per pass)
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
for (const [name, props] of JSON.parse(casesJson)) {
  const c = new Component(props);
  if (stateJson) c.state = JSON.parse(stateJson);
  const vals = c.renderVals();
  let html = fill(markup, vals);
  html = html.replace(/\/_blob\/([0-9a-f]{32})/g, (m, id) => blobMap[id] ? 'file://' + blobMap[id] : m);
  fs.writeFileSync(`check/${prefix}${name}.html`, `<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:-apple-system,sans-serif}${style}</style></head><body>${html}</body></html>`);
}
