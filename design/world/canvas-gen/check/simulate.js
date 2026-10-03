// Runs a board's logic like the runtime does (React-style shallow setState), taps through a script,
// fast-forwards timers, and checks each rendered step for thrown errors and unresolved values.
const fs = require('fs');
const path = require('path');
const timers = [];
let now = 0;
global.setTimeout = (fn, ms) => { timers.push({ at: now + (ms || 0), fn }); return timers.length; };
global.clearTimeout = (id) => { if (timers[id - 1]) timers[id - 1].fn = null; };
function advance(ms) {
  const end = now + ms;
  for (;;) {
    const next = timers.filter((t) => t.fn && t.at <= end).sort((a, b) => a.at - b.at)[0];
    if (!next) break;
    now = next.at; const f = next.fn; next.fn = null; f();
  }
  now = end;
}
class DCLogic { constructor(p) { this.props = p || {}; this.state = null; } setState(s) { this.state = Object.assign({}, this.state || {}, s); } }
global.DCLogic = DCLogic;
function load(file) {
  const src = fs.readFileSync(file, 'utf8');
  const js = src.split('data-dc-script')[1].split("'>").slice(1).join("'>").split('</script>')[0];
  const markup = src.split('<x-dc>')[1].split('</x-dc>')[0].replace(/<helmet>[\s\S]*?<\/helmet>/, '');
  return { C: eval('(' + js.trim().replace(/^class Component extends DCLogic/, 'class extends DCLogic') + ')'), markup };
}
const get = (v, p) => p.split('.').reduce((a, k) => (a == null ? a : a[k]), v);
function check(markup, vals, label) {
  // every hole must resolve to something other than undefined
  const holes = [...markup.matchAll(/\{\{\s*([\w.$]+)\s*\}\}/g)].map((m) => m[1]);
  const scoped = new Set(); [...markup.matchAll(/as="(\w+)"/g)].forEach((m) => scoped.add(m[1]));
  const bad = holes.filter((h) => !scoped.has(h.split('.')[0]) && !['true', 'false', '$index'].includes(h) && get(vals, h) === undefined);
  if (bad.length) console.log(`  ! ${label}: unresolved ${[...new Set(bad)].join(', ')}`);
}
function run(board, props, steps) {
  // PROJ=proposal/project runs the same taps on the proposal canvas's copies
  const file = path.join(process.env.PROJ ? path.resolve(process.env.PROJ) : path.join(__dirname, '..', 'project'), board + '.dc.html');
  if (!fs.existsSync(file)) return;
  const { C, markup } = load(file);
  const c = new C(props || {});
  let fails = 0;
  const render = (label) => { try { const v = c.renderVals(); check(markup, v, label); return v; } catch (e) { fails++; console.log(`  ✗ ${label}: ${e.message}`); return null; } };
  let v = render('start');
  console.log(`${board}`);
  for (const [label, act, wait] of steps) {
    try { act(v, c); } catch (e) { fails++; console.log(`  ✗ ${label}: ${e.message}`); }
    v = render(label);
    const s = c.state || {};
    const mid = JSON.stringify({ walking: s.walking, action: s.action, say: s.say, sel: s.sel, dir: s.dir, flip: s.flip, carry: s.carry, view: s.view, sit: s.sit, hold: s.hold, gift: s.gift, photo: s.photo, night: s.night, msg: s.msg, gold: s.gold });
    advance(wait || 0);
    v = render(label + ' (after)');
    const t = c.state || {};
    console.log(`  ${label}: ${mid}  ->  ${JSON.stringify({ walking: t.walking, action: t.action, say: t.say, done: t.done, took: t.took, gift: t.gift, photo: t.photo, night: t.night, sit: t.sit, walk: t.walk && t.walk.map(Math.round), hold: t.hold, sel: t.sel, spots: t.spots, gold: t.gold, msg: t.msg, view: t.view, level: t.level, golden: t.golden, ramadan: t.ramadan })}`);
  }
  console.log(fails ? `  ${fails} failures` : '  ok');
}
const ev = (x, y) => ({ nativeEvent: { offsetX: x, offsetY: y } });
run('Walk', {}, [
  ['tap ground far left', (v) => v.ground(ev(40, 140)), 3000],
  ['tap palm', (v) => v.tp.kpalm(), 3000],
  ['pick dates', (v) => v.act(), 4000],
  ['tap jasmine', (v) => v.tp.k2(), 3000],
  ['take cutting', (v) => v.act(), 4000],
  ['tap bench', (v) => v.tp.k5(), 3000],
  ['sit', (v) => v.act(), 4000],
  ['tap lantern arch', (v) => v.tp.k4(), 3000],
  ['lights', (v) => v.act(), 5000],
  ['gift', (v) => v.giveGift(), 5000],
  ['water', (v) => v.water(), 3000],
  ['like', (v) => v.like(), 0],
  ['tap house', (v) => v.tp.k1(), 3000],
  ['camera', (v) => v.photoOn(), 2000],
  ['close photo', (v) => v.photoOff(), 0],
]);
run('Play', {}, [
  ['level up moment', (v) => v.levelUp(), 6000],
  ['tap palm', (v) => v.tp.kpalm(), 5000],
  ['tap lemon', (v) => v.tp.k0(), 5000],
  ['tap gift from Khalid', (v) => v.tp.kg0(), 5000],
  ['tap ground', (v) => v.ground(ev(200, 60)), 3000],
  ['tap house', (v) => v.tp.k1(), 3000],
  ['night', (v) => v.toggleNight(), 0],
]);
run('Inside', {}, [
  ['sit: walks over, hops onto the cushions', (v) => v.sit(), 2700],
  ['stand: hops down, walks back', (v) => v.sit(), 2700],
  ['sit again', (v) => v.sit(), 2700],
  ['tap the cushions while he sits', (v) => v.sl.t7(), 0],
  ['swap them for a chest: he stands', (v) => v.pk.mandoos(), 0],
  ['open chest slot', (v) => v.sl.t8(), 0],
  ['put a shelf', (v) => v.pk.shelf(), 0],
  ['night', (v) => v.toggle(), 0],
]);
run('Edit', {}, [
  ['select coral house', (v) => v.cb.t7(), 0],
  ['make it gold', (v) => v.gild(), 0],
  ['flip', (v) => v.flip(), 0],
  ['move', (v) => v.move(), 0],
  ['to empty place 6', (v) => v.cb.t6(), 0],
  ['hold lemon from tray', (v) => v.hold.lemon(), 0],
  ['place at 11', (v) => v.cb.t11(), 0],
  ['design 3', (v) => v.tabs.t2(), 0],
]);
run('Builder', {}, [
  ['tap empty place 1', (v) => v.tap.t1(), 0],
  ['rare tab', (v) => v.tabRare(), 0],
  ['locked chest', (v) => v.pick.pearl_chest(), 0],
  ['lantern arch', (v) => v.pick.lantern_arch(), 3000],
  ['level 80', (v) => v.setLevel({ target: { value: '80' } }), 0],
  ['night', (v) => v.toggleNight(), 0],
]);
run('Neighbours', {}, [
  ['visit Khalid', (v) => v.go.v0(), 0],
  ['water', (v) => v.water(), 3000],
  ['open gift', (v) => v.openGift(), 0],
  ['give basket', (v) => v.give.harvest_basket(), 0],
  ['like', (v) => v.like(), 0],
  ['back', (v) => v.back(), 0],
]);
run('Show', {}, [['vote Khalid', (v) => v.vt.v0(), 0]]);
run('Rig', {}, [['walk', (v) => v.b.walk(), 0], ['happy', (v) => v.b.happy(), 0]]);

// ---- the simple version (2026-10-03) ----
run('Oasis', {}, [
  ['wait: Doum goes to sit on his own', () => {}, 4000],
  ['wait: still sitting', () => {}, 4000],
  ['wait: hops down, waters', () => {}, 6000],
  ['tap bench', (v) => v.tp.k4(), 3500],
  ['tap bench again while sitting', (v) => v.tp.k4(), 500],
  ['tap palm (hops down first)', (v) => v.tp.kpalm(), 5000],
  ['test: new level', (v) => v.levelUp(), 6000],
  ['tap vegetables', (v) => v.tp.k5(), 5000],
  ['test: friend took a cutting', (v) => v.showNews(), 0],
  ['test: Ramadan nights', (v) => v.ramadan(), 3000],
  ['test: back to day', (v) => v.ramadan(), 0],
  ['tap ground', (v) => v.ground(ev(120, 60)), 3000],
  ['reset', (v) => v.reset(), 0],
]);
run('Arrange', {}, [
  ['tap empty front right', (v) => v.tp.k5(), 0],
  ['groups', (v) => console.log('   have ' + v.have.map((c) => c.ar).join(', ') + ' | buy ' + v.buy.map((c) => c.ar + ' ' + c.label).join(', ') + ' | lock ' + v.lock.map((c) => c.ar + ' ' + c.label).join(', ')), 0],
  ['the lemon is tall: back only', (v) => { console.log('   away: ' + v.back.map((c) => c.ar).join(', ') + ' | hint: ' + v.rowHint); v.cards.find((c) => c.name === 'lemon').pick(); }, 0],
  ['put rose (have)', (v) => v.cards.find((c) => c.name === 'rose').pick(), 4000],
  ['tap well', (v) => v.tp.k3(), 0],
  ['locked fountain', (v) => v.cards.find((c) => c.name === 'fountain').pick(), 0],
  ['build lantern arch (700)', (v) => v.cards.find((c) => c.name === 'lantern_arch').pick(), 4000],
  ['tap the arch, empty it', (v) => v.tp.k3(), 0],
  ['empty', (v) => v.clear(), 0],
  ['tap it again: well and arch are yours', (v) => { v.tp.k3(); console.log('   have: ' + v.have.map((c) => c.ar).join(', ')); }, 0],
  ['done', (v) => v.close(), 0],
  ['tap the pomegranate', (v) => v.tp.k0(), 0],
  ['make it golden (2,000)', (v) => v.gild(), 1600],
  ['tap it again: no second golden', (v) => { v.tp.k0(); console.log('   can gild ' + v.canGild); }, 0],
  ['tap the house', (v) => v.tp.k1(), 0],
  ['golden: not enough gold', (v) => v.gild(), 0],
  ['coral house: not enough gold', (v) => v.cards.find((c) => c.name === 'coral_house').pick(), 0],
]);
run('Friends', {}, [
  ['turn on', (v) => v.turnOn(), 0],
  ['chips', (v) => console.log('   ' + JSON.stringify(v.rows)), 0],
  ['visit Yousef', (v) => v.go.v0(), 3000],
  ['tap sidr', (v) => v.tp.k1(), 3000],
  ['take a cutting', (v) => v.take(), 4500],
  ['card after', (v) => console.log('   ' + JSON.stringify(v.card)), 0],
  ['tap fountain', (v) => v.tp.k2(), 3000],
  ['card', (v) => console.log('   ' + JSON.stringify(v.card)), 0],
  ['back to list', (v) => v.toList(), 0],
  ['chips now', (v) => console.log('   ' + JSON.stringify(v.rows)), 0],
  ['visit Khalid', (v) => v.go.v1(), 3000],
  ['tap his bench', (v) => v.tp.k4(), 4000],
  ['tap his palm offshoot', (v) => v.tp.k1(), 4000],
  ['card', (v) => console.log('   ' + JSON.stringify(v.card)), 0],
  ['tap palm', (v) => v.tp.kpalm(), 3000],
  ['back, turn off', (v) => { v.toList(); }, 0],
  ['switch off', (v) => v.turnOff(), 0],
]);
