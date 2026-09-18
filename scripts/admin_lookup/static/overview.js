/**
 * The Overview, the control room's first view: six tiles, four charts and
 * four panels, drawn from DATA.overview (lib/overview.js, computed on the
 * server from the same scan as the Activity and Accounts views) plus the
 * scan's own events for the live feed.
 *
 * Charts are Apache ECharts (vendored, /vendor/echarts.min.js), set up to the
 * data-viz rules this tool follows:
 *   - bars at most 24px wide, 4px rounded tops, square at the baseline, and a
 *     2px gap in the panel colour between stacked parts;
 *   - hairline solid gridlines, axis text in the muted ink, never the series
 *     colour;
 *   - a tooltip on every chart, value first and the name after it, keyed by a
 *     short stroke of the series colour;
 *   - a legend whenever there is more than one series, labels only where they
 *     say something (today, the peak, the end of the line);
 *   - a Table view on every chart, which is also the relief the light
 *     theme's three sub-3:1 series colours require.
 * Colours are read from the CSS roles at draw time, so the theme switch
 * redraws everything in the other theme's validated steps.
 *
 * Builds DOM with textContent throughout: account names and event titles
 * come from users and are never parsed as HTML.
 */
(function () {
  'use strict';

  var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var ICONS = {};
  try {
    ICONS = JSON.parse(document.getElementById('gdIcons').textContent);
  } catch (e) {
    ICONS = {};
  }

  var last = null;          // the DATA drawn most recently, for redraws
  var charts = {};          // echarts instances by id
  var tableMode = {};       // chart id -> true when showing its table
  // Panel bodies waiting to be drawn. A chart measures its box when it is
  // created, and a panel still being built is not in the page yet, so it
  // would measure 0 by 0 and draw nothing: every draw waits until the whole
  // grid is attached.
  var pendingDraws = [];

  // ---- Small DOM helpers -----------------------------------------------
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = String(text);
    return n;
  }
  function iconNode(name) {
    var span = el('span', 'ic');
    span.setAttribute('aria-hidden', 'true');
    // Our own SVG, from lucide-static on the server, never user data.
    span.innerHTML = ICONS[name] || '';
    return span.firstChild || span;
  }
  function fmt(n) {
    return Number(n || 0).toLocaleString('en-US');
  }
  function dayLabel(key, today) {
    if (key === today) return 'Today';
    var p = key.split('-');
    return MONTHS[Number(p[1]) - 1] + ' ' + Number(p[2]);
  }
  function longDay(key) {
    var p = key.split('-');
    return Number(p[2]) + ' ' + MONTHS[Number(p[1]) - 1] + ' ' + p[0];
  }
  function ago(ms) {
    var s = Math.max(0, Math.round((Date.now() - ms) / 1000));
    if (s < 60) return 'just now';
    var m = Math.round(s / 60);
    if (m < 60) return m + 'm ago';
    var h = Math.round(m / 60);
    if (h < 24) return h + 'h ago';
    return Math.round(h / 24) + 'd ago';
  }
  function avatar(uid, name) {
    var h = 0;
    var id = String(uid || '');
    for (var i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) % 360;
    var a = el('span', 'avatar', String(name || id || '?').trim().charAt(0) || '?');
    a.style.background = 'hsl(' + h + ' 42% 42%)';
    a.setAttribute('aria-hidden', 'true');
    return a;
  }
  function openDrawer(uid) {
    if (window.GDDashboard && window.GDDashboard.openDrawer) window.GDDashboard.openDrawer(uid);
  }
  function showView(id) {
    if (window.GDDashboard && window.GDDashboard.showView) window.GDDashboard.showView(id);
  }

  function roles() {
    var cs = getComputedStyle(document.documentElement);
    var v = function (n) { return cs.getPropertyValue(n).trim(); };
    return {
      series: [v('--series-1'), v('--series-2'), v('--series-3'), v('--series-4'), v('--series-5')],
      ord: [v('--ord-1'), v('--ord-2'), v('--ord-3')],
      grid: v('--chart-grid'),
      axis: v('--chart-axis'),
      deemph: v('--chart-deemph'),
      text: v('--text'),
      textSec: v('--text-sec'),
      textTert: v('--text-tert'),
      surface: v('--surface'),
      surface2: v('--surface-2'),
      border: v('--border'),
      font: getComputedStyle(document.body).fontFamily,
    };
  }

  // ---- Tiles ------------------------------------------------------------
  function sparkline(values, c) {
    var w = 84, hgt = 26, pad = 3;
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('width', w);
    svg.setAttribute('height', hgt);
    svg.setAttribute('class', 'kpi-spark');
    svg.setAttribute('aria-hidden', 'true');
    if (!values || values.length < 2) return svg;
    var max = Math.max.apply(null, values.concat([1]));
    var pts = values.map(function (v, i) {
      var x = pad + (i * (w - pad * 2)) / (values.length - 1);
      var y = hgt - pad - (v / max) * (hgt - pad * 2);
      return [x, y];
    });
    var line = document.createElementNS(ns, 'polyline');
    line.setAttribute('points', pts.map(function (p) { return p[0].toFixed(1) + ',' + p[1].toFixed(1); }).join(' '));
    line.setAttribute('fill', 'none');
    line.setAttribute('stroke', c.deemph);
    line.setAttribute('stroke-width', '2');
    line.setAttribute('stroke-linejoin', 'round');
    line.setAttribute('stroke-linecap', 'round');
    svg.appendChild(line);
    var end = pts[pts.length - 1];
    var dot = document.createElementNS(ns, 'circle');
    dot.setAttribute('cx', end[0]);
    dot.setAttribute('cy', end[1]);
    dot.setAttribute('r', '3.5');
    dot.setAttribute('fill', c.series[0]);
    dot.setAttribute('stroke', c.surface);
    dot.setAttribute('stroke-width', '2');
    svg.appendChild(dot);
    return svg;
  }

  function delta(now, before, period) {
    var span = el('span', 'delta');
    var d = now - before;
    if (d === 0) {
      span.textContent = 'Same as ' + period;
      return span;
    }
    span.className = 'delta ' + (d > 0 ? 'up' : 'down');
    span.textContent = (d > 0 ? '+' : '−') + Math.abs(d) + ' vs ' + period;
    return span;
  }

  function tile(opts, c) {
    var t = el('div', 'kpi' + (opts.live ? ' live' : ''));
    var label = el('div', 'kpi-label');
    if (opts.icon) label.appendChild(iconNode(opts.icon));
    label.appendChild(el('span', null, opts.label));
    t.appendChild(label);
    var value = el('div', 'kpi-value');
    if (opts.live) {
      var dot = el('span', 'live-dot');
      if (!opts.value) dot.style.visibility = 'hidden';
      value.appendChild(dot);
    }
    value.appendChild(el('span', null, opts.valueText !== undefined ? opts.valueText : fmt(opts.value)));
    if (opts.of !== undefined) value.appendChild(el('span', 'of', 'of ' + fmt(opts.of)));
    t.appendChild(value);
    if (opts.meter !== undefined) {
      var meter = el('div', 'meter');
      var fill = el('i');
      fill.style.width = Math.round(Math.max(0, Math.min(1, opts.meter)) * 100) + '%';
      meter.appendChild(fill);
      t.appendChild(meter);
    }
    var foot = el('div', 'kpi-foot');
    var sub = el('div', 'kpi-sub');
    (opts.sub || []).forEach(function (part, i) {
      if (i) sub.appendChild(document.createTextNode(' · '));
      sub.appendChild(typeof part === 'string' ? document.createTextNode(part) : part);
    });
    foot.appendChild(sub);
    if (opts.spark) t.appendChild(sparkline(opts.spark, c));
    t.appendChild(foot);
    return t;
  }

  function renderTiles(data, c) {
    var box = document.getElementById('liveStrip');
    if (!box) return;
    var ov = data.overview;
    var k = ov.kpis;
    var never = (ov.panels.recency.filter(function (r) { return r.id === 'never'; })[0] || {}).count || 0;
    box.textContent = '';
    box.appendChild(tile({
      live: true, icon: 'radio', label: 'On the app now', value: k.onlineNow,
      sub: ['acted in the last ' + (data.onlineWindowMinutes || 15) + ' min'],
    }, c));
    box.appendChild(tile({
      icon: 'activity', label: 'Active today', value: k.activeToday,
      sub: [delta(k.activeToday, k.activeYesterday, 'yesterday')], spark: ov.series.activeByDay,
    }, c));
    box.appendChild(tile({
      icon: 'calendar-days', label: 'Active this week', value: k.activeWeek,
      sub: ['of ' + fmt(k.accountsTotal) + ' accounts'],
    }, c));
    box.appendChild(tile({
      icon: 'square-check-big', label: 'Squares done today', value: k.squaresDone, of: k.squaresScheduled,
      meter: k.squaresScheduled ? k.squaresDone / k.squaresScheduled : 0,
      sub: [fmt(k.peopleScheduledToday) + (k.peopleScheduledToday === 1 ? ' person' : ' people') + ' with habits due'],
    }, c));
    box.appendChild(tile({
      icon: 'user-plus', label: 'New this week', value: k.newWeek,
      sub: [delta(k.newWeek, k.newPrevWeek, 'last week')], spark: ov.series.signupsByDay,
    }, c));
    box.appendChild(tile({
      icon: 'users', label: 'Accounts', value: k.accountsTotal,
      sub: [fmt(never) + ' never did anything'],
    }, c));
  }

  // ---- Chart plumbing ---------------------------------------------------
  function chartFor(id, node) {
    var existing = charts[id];
    if (existing && existing.getDom() === node) return existing;
    if (existing) existing.dispose();
    charts[id] = window.echarts.init(node, null, { renderer: 'svg' });
    return charts[id];
  }

  function tooltipBase(c) {
    return {
      confine: true,
      backgroundColor: c.surface2,
      borderColor: c.border,
      borderWidth: 1,
      padding: [8, 10],
      textStyle: { color: c.text, fontSize: 12, fontFamily: c.font },
      extraCssText: 'border-radius:10px;box-shadow:0 14px 30px -14px rgba(0,0,0,.6);',
    };
  }

  function tipNode(head, rows, total) {
    var box = el('div', 'gd-tip');
    box.appendChild(el('div', 'gd-tip-head', head));
    rows.forEach(function (r) {
      var row = el('div', 'gd-tip-row');
      var key = el('span', 'gd-tip-key');
      key.style.background = r.color;
      row.appendChild(key);
      row.appendChild(el('span', 'gd-tip-val', fmt(r.value)));
      row.appendChild(el('span', 'gd-tip-name', r.name));
      box.appendChild(row);
    });
    if (total) box.appendChild(el('div', 'gd-tip-total', total));
    return box;
  }

  function categoryAxis(labels, c) {
    return {
      type: 'category',
      data: labels,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: c.axis, width: 1 } },
      axisLabel: { color: c.textTert, fontSize: 11, fontFamily: c.font, hideOverlap: true },
    };
  }

  function valueAxis(c) {
    return {
      type: 'value',
      minInterval: 1,
      splitNumber: 4,
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: { lineStyle: { color: c.grid, width: 1, type: 'solid' } },
      axisLabel: { color: c.textTert, fontSize: 11, fontFamily: c.font },
    };
  }

  function barShadow(c) {
    return { type: 'shadow', shadowStyle: { color: c.surface2, opacity: 0.9 } };
  }

  // ---- Panels -----------------------------------------------------------
  /**
   * A panel with a title, a line under it, and optionally a Chart / Table
   * switch. [draw] fills the body; for a chart it gets the node to draw in,
   * [table] returns {head, rows} for the table view.
   */
  function panel(opts) {
    var p = el('section', 'panel span-' + opts.span + (opts.tall ? ' tall' : ''));
    p.setAttribute('aria-label', opts.title);
    var head = el('div', 'panel-head');
    var titles = el('div');
    titles.appendChild(el('div', 'panel-title', opts.title));
    if (opts.sub) titles.appendChild(el('div', 'panel-sub', opts.sub));
    head.appendChild(titles);
    var body = el('div');
    if (opts.table) {
      var tools = el('div', 'panel-tools');
      var seg = el('div', 'seg');
      seg.setAttribute('role', 'group');
      seg.setAttribute('aria-label', 'Show as');
      var asChart = el('button', tableMode[opts.id] ? '' : 'on', 'Chart');
      var asTable = el('button', tableMode[opts.id] ? 'on' : '', 'Table');
      asChart.type = asTable.type = 'button';
      asChart.addEventListener('click', function () { tableMode[opts.id] = false; redraw(); });
      asTable.addEventListener('click', function () { tableMode[opts.id] = true; redraw(); });
      seg.appendChild(asChart);
      seg.appendChild(asTable);
      tools.appendChild(seg);
      head.appendChild(tools);
    }
    p.appendChild(head);
    p.appendChild(body);
    if (opts.table && tableMode[opts.id]) {
      if (charts[opts.id]) { charts[opts.id].dispose(); delete charts[opts.id]; }
      var t = opts.table();
      var wrap = el('div', 'chart-table');
      var table = el('table');
      var thead = el('thead');
      var hr = el('tr');
      t.head.forEach(function (h) { hr.appendChild(el('th', null, h)); });
      thead.appendChild(hr);
      table.appendChild(thead);
      var tbody = el('tbody');
      t.rows.forEach(function (r) {
        var tr = el('tr');
        r.forEach(function (cell, i) { tr.appendChild(el('td', null, i === 0 ? cell : fmt(cell))); });
        tbody.appendChild(tr);
      });
      table.appendChild(tbody);
      wrap.appendChild(table);
      body.appendChild(wrap);
    } else {
      pendingDraws.push(function () { opts.draw(body); });
    }
    if (opts.note) p.appendChild(el('div', 'chart-note', opts.note));
    if (opts.foot) p.appendChild(opts.foot);
    return p;
  }

  function footLink(text, label, onClick) {
    var foot = el('div', 'panel-foot');
    foot.appendChild(el('span', null, text));
    if (label) {
      var b = el('button', 'link', label);
      b.type = 'button';
      b.addEventListener('click', onClick);
      foot.appendChild(b);
    }
    return foot;
  }

  // What people did, stacked by kind, one bar per day.
  function activityPanel(data, c) {
    var ov = data.overview;
    var cats = ov.series.byCategory;
    var labels = ov.days.map(function (d) { return dayLabel(d, ov.today); });
    return panel({
      id: 'activity', span: 8,
      title: 'What people did',
      sub: 'Actions per day, last ' + ov.trendDays + ' days, Bahrain time',
      table: function () {
        return {
          head: ['Day'].concat(cats.map(function (x) { return x.label; })).concat(['Total']),
          rows: ov.days.map(function (d, i) {
            var total = 0;
            var row = [longDay(d)];
            cats.forEach(function (x) { row.push(x.counts[i]); total += x.counts[i]; });
            row.push(total);
            return row;
          }),
        };
      },
      draw: function (body) {
        var node = el('div', 'chart');
        body.appendChild(node);
        var chart = chartFor('activity', node);
        var shown = cats.map(function () { return true; });
        var build = function () {
          // The top visible part of each day's bar gets the rounded end; the
          // rest stay square so the stack reads as one bar.
          var tops = ov.days.map(function (_, di) {
            for (var si = cats.length - 1; si >= 0; si--) {
              if (shown[si] && cats[si].counts[di] > 0) return si;
            }
            return -1;
          });
          return cats.map(function (cat, si) {
            return {
              name: cat.label,
              type: 'bar',
              stack: 'day',
              barMaxWidth: 24,
              emphasis: { disabled: true },
              itemStyle: { color: c.series[si], borderColor: c.surface, borderWidth: 1 },
              data: cat.counts.map(function (v, di) {
                return { value: v, itemStyle: { borderRadius: tops[di] === si ? [4, 4, 0, 0] : 0 } };
              }),
            };
          });
        };
        chart.setOption({
          animationDuration: 260,
          textStyle: { fontFamily: c.font },
          legend: {
            top: 0, left: 0, icon: 'roundRect', itemWidth: 10, itemHeight: 10, itemGap: 16,
            textStyle: { color: c.textSec, fontSize: 11.5, fontFamily: c.font },
            inactiveColor: c.axis,
          },
          grid: { left: 4, right: 8, top: 34, bottom: 2, containLabel: true },
          xAxis: categoryAxis(labels, c),
          yAxis: valueAxis(c),
          tooltip: Object.assign(tooltipBase(c), {
            trigger: 'axis',
            axisPointer: barShadow(c),
            formatter: function (params) {
              var i = params[0].dataIndex;
              var rows = [];
              var total = 0;
              cats.forEach(function (cat, si) {
                if (!shown[si]) return;
                rows.push({ color: c.series[si], value: cat.counts[i], name: cat.label });
                total += cat.counts[i];
              });
              rows.reverse();
              return tipNode(longDay(ov.days[i]), rows, fmt(total) + ' in all');
            },
          }),
          series: build(),
        }, true);
        chart.off('legendselectchanged');
        chart.on('legendselectchanged', function (e) {
          cats.forEach(function (cat, si) { shown[si] = e.selected[cat.label] !== false; });
          chart.setOption({ series: build() });
        });
      },
    });
  }

  // One number per day: accounts that did something.
  function activePanel(data, c) {
    var ov = data.overview;
    var values = ov.series.activeByDay;
    var labels = ov.days.map(function (d) { return dayLabel(d, ov.today); });
    return panel({
      id: 'active', span: 4,
      title: 'Active accounts',
      sub: 'Accounts that did something, per day',
      table: function () {
        return { head: ['Day', 'Active'], rows: ov.days.map(function (d, i) { return [longDay(d), values[i]]; }) };
      },
      draw: function (body) {
        var node = el('div', 'chart short');
        body.appendChild(node);
        var chart = chartFor('active', node);
        var lastIndex = values.length - 1;
        chart.setOption({
          animationDuration: 260,
          textStyle: { fontFamily: c.font },
          grid: { left: 4, right: 8, top: 18, bottom: 2, containLabel: true },
          xAxis: Object.assign(categoryAxis(labels, c), {
            axisLabel: { color: c.textTert, fontSize: 11, fontFamily: c.font, interval: function (i) { return i === 0 || i === lastIndex || i === Math.floor(lastIndex / 2); } },
          }),
          yAxis: valueAxis(c),
          tooltip: Object.assign(tooltipBase(c), {
            trigger: 'axis',
            axisPointer: barShadow(c),
            formatter: function (params) {
              var i = params[0].dataIndex;
              return tipNode(longDay(ov.days[i]), [{ color: c.series[0], value: values[i], name: values[i] === 1 ? 'account' : 'accounts' }]);
            },
          }),
          series: [{
            name: 'Active accounts',
            type: 'bar',
            barMaxWidth: 24,
            emphasis: { disabled: true },
            itemStyle: { color: c.series[0], borderRadius: [4, 4, 0, 0] },
            label: {
              show: true, position: 'top', color: c.textSec, fontSize: 11, fontWeight: 600, fontFamily: c.font,
              formatter: function (p) { return p.dataIndex === lastIndex ? String(p.value) : ''; },
            },
            data: values,
          }],
        }, true);
      },
    });
  }

  // When in the day the actions happen.
  function hoursPanel(data, c) {
    var ov = data.overview;
    var values = ov.series.hours;
    var labels = values.map(function (_, h) { return (h < 10 ? '0' : '') + h; });
    var peak = values.indexOf(Math.max.apply(null, values));
    return panel({
      id: 'hours', span: 4,
      title: 'When people use the app',
      sub: 'By hour, Bahrain time, last ' + ov.trendDays + ' days',
      table: function () {
        return { head: ['Hour', 'Actions'], rows: values.map(function (v, h) { return [labels[h] + ':00', v]; }) };
      },
      draw: function (body) {
        var node = el('div', 'chart short');
        body.appendChild(node);
        var chart = chartFor('hours', node);
        chart.setOption({
          animationDuration: 260,
          textStyle: { fontFamily: c.font },
          grid: { left: 4, right: 8, top: 18, bottom: 2, containLabel: true },
          xAxis: Object.assign(categoryAxis(labels, c), {
            axisLabel: { color: c.textTert, fontSize: 11, fontFamily: c.font, interval: 5 },
          }),
          yAxis: valueAxis(c),
          tooltip: Object.assign(tooltipBase(c), {
            trigger: 'axis',
            axisPointer: barShadow(c),
            formatter: function (params) {
              var h = params[0].dataIndex;
              return tipNode(labels[h] + ':00 to ' + labels[h] + ':59', [{ color: c.series[0], value: values[h], name: 'actions' }]);
            },
          }),
          series: [{
            name: 'Actions',
            type: 'bar',
            barMaxWidth: 24,
            barCategoryGap: '28%',
            emphasis: { disabled: true },
            itemStyle: { color: c.series[0], borderRadius: [4, 4, 0, 0] },
            label: {
              show: true, position: 'top', color: c.textSec, fontSize: 11, fontWeight: 600, fontFamily: c.font,
              formatter: function (p) { return p.dataIndex === peak && p.value > 0 ? labels[peak] + ':00' : ''; },
            },
            data: values,
          }],
        }, true);
      },
    });
  }

  // Every account there has ever been, by sign-up date.
  function growthPanel(data, c) {
    var ov = data.overview;
    var g = ov.series.growth;
    var undated = ov.kpis.undatedAccounts;
    return panel({
      id: 'growth', span: 12,
      title: 'Accounts over time',
      sub: 'Total accounts at the end of each week, since the first sign-up',
      note: undated ? fmt(undated) + (undated === 1 ? ' account has' : ' accounts have')
        + ' no sign-up date left and ' + (undated === 1 ? 'is' : 'are') + ' not on the line.' : '',
      table: function () {
        return { head: ['Week to', 'Accounts'], rows: g.slice().reverse().map(function (p) { return [longDay(p.day), p.total]; }) };
      },
      draw: function (body) {
        var node = el('div', 'chart');
        body.appendChild(node);
        var chart = chartFor('growth', node);
        var lastIndex = g.length - 1;
        chart.setOption({
          animationDuration: 320,
          textStyle: { fontFamily: c.font },
          grid: { left: 4, right: 40, top: 18, bottom: 2, containLabel: true },
          xAxis: Object.assign(categoryAxis(g.map(function (p) { return p.day; }), c), {
            boundaryGap: false,
            axisLabel: {
              color: c.textTert, fontSize: 11, fontFamily: c.font, hideOverlap: true,
              formatter: function (d) {
                var p = d.split('-');
                return MONTHS[Number(p[1]) - 1] + (p[1] === '01' || d === g[0].day ? ' ' + p[0] : '');
              },
            },
          }),
          yAxis: valueAxis(c),
          tooltip: Object.assign(tooltipBase(c), {
            trigger: 'axis',
            axisPointer: { type: 'line', lineStyle: { color: c.axis, width: 1 } },
            formatter: function (params) {
              var i = params[0].dataIndex;
              return tipNode('Week to ' + longDay(g[i].day), [{ color: c.series[0], value: g[i].total, name: 'accounts' }]);
            },
          }),
          series: [{
            name: 'Accounts',
            type: 'line',
            data: g.map(function (p) { return p.total; }),
            showSymbol: true,
            symbol: 'circle',
            symbolSize: function (v, p) { return p.dataIndex === lastIndex ? 8 : 0; },
            lineStyle: { color: c.series[0], width: 2, cap: 'round', join: 'round' },
            itemStyle: { color: c.series[0], borderColor: c.surface, borderWidth: 2 },
            areaStyle: { color: c.series[0], opacity: 0.1 },
            emphasis: { disabled: true },
            endLabel: { show: true, color: c.textSec, fontSize: 11.5, fontWeight: 650, fontFamily: c.font, formatter: function (p) { return fmt(p.value); } },
          }],
        }, true);
      },
    });
  }

  function recencyPanel(data, c) {
    var r = data.overview.panels.recency;
    var total = r.reduce(function (s, x) { return s + x.count; }, 0) || 1;
    var colors = [c.ord[0], c.ord[1], c.ord[2], c.deemph];
    return panel({
      id: 'recency', span: 4,
      title: 'When accounts were last active',
      sub: 'Every account, by its last real action',
      draw: function (body) {
        var bar = el('div', 'stack-bar');
        bar.setAttribute('role', 'img');
        bar.setAttribute('aria-label', r.map(function (x) { return x.label + ': ' + x.count; }).join(', '));
        r.forEach(function (x, i) {
          if (!x.count) return;
          var part = el('i');
          part.style.width = (x.count / total) * 100 + '%';
          part.style.background = colors[i];
          part.title = x.label + ': ' + x.count;
          bar.appendChild(part);
        });
        body.appendChild(bar);
        var list = el('ul', 'legend-list');
        r.forEach(function (x, i) {
          var li = el('li');
          var sw = el('span', 'sw');
          sw.style.background = colors[i];
          li.appendChild(sw);
          li.appendChild(el('span', null, x.label));
          li.appendChild(el('span', 'ct', fmt(x.count)));
          li.appendChild(el('span', 'pc', Math.round((x.count / total) * 100) + '%'));
          list.appendChild(li);
        });
        body.appendChild(list);
      },
    });
  }

  function feedPanel(data) {
    var events = (data.events || [])
      .filter(function (e) { return e.type !== 'signin'; })
      .slice()
      .sort(function (a, b) { return b.at - a.at; })
      .slice(0, 10);
    return panel({
      id: 'feed', span: 4, tall: true,
      title: 'Latest actions',
      sub: 'The newest things people did, across everyone',
      draw: function (body) {
        var list = el('div', 'mini-list');
        if (!events.length) list.appendChild(el('div', 'mini-empty', 'Nothing yet.'));
        events.forEach(function (e) {
          var row = el('button', 'mini-row');
          row.type = 'button';
          row.appendChild(avatar(e.uid, e.who));
          var main = el('span', 'mini-main');
          main.appendChild(el('span', 'mini-name', e.who || (e.email || e.uid || '').slice(0, 14)));
          main.appendChild(el('span', 'mini-what', e.title + (e.sub ? ' · ' + e.sub : '')));
          row.appendChild(main);
          row.appendChild(el('span', 'mini-when', ago(e.at)));
          row.setAttribute('data-at', String(e.at));
          row.addEventListener('click', function () { openDrawer(e.uid); });
          list.appendChild(row);
        });
        body.appendChild(list);
      },
      foot: footLink(fmt((data.events || []).length) + ' events in this scan', 'Open Activity', function () { showView('activity'); }),
    });
  }

  function boardPanel(data) {
    var p = data.overview.panels;
    return panel({
      id: 'board', span: 8, tall: true,
      title: 'Today, person by person',
      sub: 'Everyone with habits due today, most finished first',
      draw: function (body) {
        var list = el('div', 'mini-list');
        if (!p.todayBoard.length) list.appendChild(el('div', 'mini-empty', 'Nobody has habits due yet today.'));
        p.todayBoard.forEach(function (x) {
          var row = el('button', 'mini-row');
          row.type = 'button';
          row.appendChild(avatar(x.uid, x.name));
          var main = el('span', 'mini-main');
          main.appendChild(el('span', 'mini-name', x.name));
          row.appendChild(main);
          var barBox = el('span', 'board-bar');
          var meter = el('span', 'meter' + (x.done >= x.scheduled ? ' full' : ''));
          var fill = el('i');
          // Nothing done is an empty track, not a sliver of bar.
          fill.style.width = Math.round((x.done / x.scheduled) * 100) + '%';
          if (x.done > 0) fill.style.minWidth = '4px';
          meter.appendChild(fill);
          barBox.appendChild(meter);
          barBox.appendChild(el('span', 'num', x.done + ' / ' + x.scheduled));
          row.appendChild(barBox);
          row.addEventListener('click', function () { openDrawer(x.uid); });
          list.appendChild(row);
        });
        body.appendChild(list);
      },
      foot: footLink(
        (p.todayBoardTotal > p.todayBoard.length ? 'Showing ' + p.todayBoard.length + ' of ' : '')
          + fmt(p.todayBoardTotal) + (p.todayBoardTotal === 1 ? ' person' : ' people') + ' with habits due today',
        'Open Accounts', function () { showView('accounts'); }),
    });
  }

  function streaksPanel(data) {
    var leaders = data.overview.panels.streakLeaders;
    return panel({
      id: 'streaks', span: 4,
      title: 'Longest streaks',
      sub: 'Days in a row, as each account stands now',
      draw: function (body) {
        var list = el('div', 'mini-list');
        if (!leaders.length) list.appendChild(el('div', 'mini-empty', 'No streaks running.'));
        leaders.forEach(function (x, i) {
          var row = el('button', 'mini-row');
          row.type = 'button';
          row.appendChild(el('span', 'rank', String(i + 1)));
          row.appendChild(avatar(x.uid, x.name));
          var main = el('span', 'mini-main');
          main.appendChild(el('span', 'mini-name', x.name));
          main.appendChild(el('span', 'mini-what', 'Level ' + x.level));
          row.appendChild(main);
          var s = el('span', 'streak');
          s.appendChild(iconNode('flame'));
          s.appendChild(el('span', null, x.streak + (x.streak === 1 ? ' day' : ' days')));
          row.appendChild(s);
          row.addEventListener('click', function () { openDrawer(x.uid); });
          list.appendChild(row);
        });
        body.appendChild(list);
      },
    });
  }

  // ---- Drawing ------------------------------------------------------------
  function draw(data) {
    if (!data || !data.overview) return;
    last = data;
    var c = roles();
    renderTiles(data, c);
    var grid = document.getElementById('ovGrid');
    if (!grid) return;
    grid.textContent = '';
    if (!window.echarts) {
      grid.appendChild(el('div', 'panel span-12', 'The chart library did not load (/vendor/echarts.min.js). Run npm install in scripts/admin_lookup.'));
      return;
    }
    // What happened, with the newest actions running down beside it and the
    // day's two shapes under it; today person by person, with the streaks
    // and where everyone stands stacked beside it; the whole history of
    // sign-ups across the bottom.
    grid.appendChild(activityPanel(data, c));
    grid.appendChild(feedPanel(data));
    grid.appendChild(activePanel(data, c));
    grid.appendChild(hoursPanel(data, c));
    grid.appendChild(boardPanel(data));
    grid.appendChild(streaksPanel(data));
    grid.appendChild(recencyPanel(data, c));
    grid.appendChild(growthPanel(data, c));
    var draws = pendingDraws;
    pendingDraws = [];
    draws.forEach(function (fn) { fn(); });
    // Panels whose chart is not on screen any more (switched to a table, or
    // gone) release their instance.
    Object.keys(charts).forEach(function (id) {
      if (!document.body.contains(charts[id].getDom())) {
        charts[id].dispose();
        delete charts[id];
      }
    });
    setRefreshing(false);
  }

  function redraw() {
    if (last) draw(last);
  }

  function setRefreshing(on) {
    ['liveStrip', 'ovGrid'].forEach(function (id) {
      var n = document.getElementById(id);
      if (n) n.classList.toggle('refreshing', !!on);
    });
  }

  var resizeTimer = null;
  window.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () {
      Object.keys(charts).forEach(function (id) { charts[id].resize(); });
    }, 120);
  });
  window.addEventListener('gd-theme', function () { redraw(); });

  /** Keeps "5m ago" true while the page sits open, without a redraw. */
  function tick() {
    Array.prototype.forEach.call(document.querySelectorAll('#ovGrid [data-at]'), function (row) {
      var when = row.querySelector('.mini-when');
      if (when) when.textContent = ago(Number(row.getAttribute('data-at')));
    });
  }

  window.GDOverview = {
    render: draw,
    tick: tick,
    redraw: redraw,
    resize: function () { Object.keys(charts).forEach(function (id) { charts[id].resize(); }); },
    setRefreshing: setRefreshing,
  };
})();
