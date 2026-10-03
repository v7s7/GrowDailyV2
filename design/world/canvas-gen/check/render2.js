const fs = require('fs');
const [file, prefix, casesJson] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
const js = src.split("data-dc-script")[1].split("'>").slice(1).join("'>").split('</script>')[0];
const markup = src.split('<x-dc>')[1].split('</x-dc>')[0];
class DCLogic { constructor(p){ this.props = p; } }
const Component = eval('(' + js.trim().replace(/^class Component extends DCLogic/, 'class extends DCLogic') + ')');
for (const [name, props] of JSON.parse(casesJson)) {
  const vals = new Component(props).renderVals();
  const get = (p) => p.split('.').reduce((a, k) => a == null ? a : a[k], vals);
  let svgs = markup.match(/<svg[\s\S]*?<\/svg>/g).map(s => s.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, p) => String(get(p))));
  svgs = svgs.map(s => s.replace(/<svg viewBox="0 0 360 400"[^>]*>/, '<g>').replace(/<\/svg>$/, '</g>'));
  const d = vals.d;
  const doum = d.show ? `<rect x="${d.left}" y="${d.top}" width="${d.w}" height="${d.h}" fill="none" stroke="#c00" stroke-width="1"/>` : '';
  fs.writeFileSync(`check/${prefix}${name}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 400" width="720" height="800"><rect width="360" height="400" fill="#F5F0E1"/>${svgs.join('')}${doum}</svg>`);
}
