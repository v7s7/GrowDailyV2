/**
 * The control-room frame's behaviour, on every live page (lib/shell.js draws
 * the frame itself): the dark/light switch, the Cmd+K account finder, and
 * the live pill a page can update.
 *
 * A plain file, not a template literal, like the Wording page's scripts:
 * what the browser runs is exactly what is written here.
 */
(function () {
  'use strict';

  var THEME_KEY = 'gd-admin-theme';
  var root = document.documentElement;

  // ---- Theme ------------------------------------------------------------
  // The head script already applied a saved choice before paint; this only
  // flips it, remembers it, and tells charts to redraw in the new colours.
  function currentTheme() {
    return root.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
  }
  function setTheme(theme) {
    root.setAttribute('data-theme', theme);
    try { localStorage.setItem(THEME_KEY, theme); } catch (e) { /* private window */ }
    window.dispatchEvent(new CustomEvent('gd-theme', { detail: theme }));
  }
  var toggle = document.getElementById('themeToggle');
  if (toggle) {
    toggle.addEventListener('click', function () {
      setTheme(currentTheme() === 'dark' ? 'light' : 'dark');
    });
  }

  // ---- Live pill --------------------------------------------------------
  // Pages say how fresh their data is; the frame owns how that looks.
  function setLive(text, on) {
    var pill = document.getElementById('livePill');
    var label = document.getElementById('livePillText');
    if (!pill || !label) return;
    label.textContent = text;
    pill.classList.toggle('on', !!on);
  }

  // ---- Cmd+K: find an account from anywhere ------------------------------
  // The dashboard hands over the accounts it already scanned (provideAccounts);
  // any other page asks /api/users once, the first time the finder opens.
  var accounts = null;
  var loading = null;
  function provideAccounts(list) {
    accounts = (list || []).map(function (a) {
      return {
        uid: a.uid,
        name: a.displayName || '',
        email: a.email || '',
        hay: ((a.displayName || '') + ' ' + (a.email || '') + ' ' + a.uid).toLowerCase(),
      };
    });
  }
  function ensureAccounts() {
    if (accounts) return Promise.resolve(accounts);
    if (!loading) {
      loading = fetch('/api/users')
        .then(function (r) { return r.json(); })
        .then(function (d) { provideAccounts(d.users || []); return accounts; })
        .catch(function () { loading = null; return []; });
    }
    return loading;
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }

  var scrim = null;
  var input = null;
  var listBox = null;
  var results = [];
  var selected = 0;

  function openAccount(uid) {
    if (!uid) return;
    window.location.href = '/report/' + encodeURIComponent(uid);
  }

  function render() {
    listBox.textContent = '';
    if (!accounts) {
      listBox.appendChild(el('div', 'cmdk-empty', 'Loading accounts…'));
      return;
    }
    var q = input.value.trim().toLowerCase();
    var words = q.split(/\s+/).filter(Boolean);
    results = accounts.filter(function (a) {
      return words.every(function (w) { return a.hay.indexOf(w) >= 0; });
    }).slice(0, 40);
    if (selected >= results.length) selected = Math.max(0, results.length - 1);
    if (!results.length) {
      listBox.appendChild(el('div', 'cmdk-empty', q ? 'No account matches.' : 'No accounts.'));
      return;
    }
    results.forEach(function (a, i) {
      var row = el('div', 'cmdk-item' + (i === selected ? ' sel' : ''));
      row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', i === selected ? 'true' : 'false');
      var who = el('span', 'who');
      who.appendChild(el('span', 'nm', a.name || a.email || a.uid.slice(0, 10)));
      who.appendChild(el('span', 'ml', (a.name ? a.email + ' · ' : '') + a.uid));
      row.appendChild(who);
      row.appendChild(el('span', 'go', '↵'));
      row.addEventListener('mouseenter', function () { selected = i; paintSelection(); });
      row.addEventListener('click', function () { openAccount(a.uid); });
      listBox.appendChild(row);
    });
  }

  function paintSelection() {
    Array.prototype.forEach.call(listBox.querySelectorAll('.cmdk-item'), function (row, i) {
      row.classList.toggle('sel', i === selected);
      row.setAttribute('aria-selected', i === selected ? 'true' : 'false');
      if (i === selected) row.scrollIntoView({ block: 'nearest' });
    });
  }

  function openFinder() {
    if (scrim) return;
    scrim = el('div', 'cmdk-scrim');
    var box = el('div', 'cmdk');
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', 'Find an account');
    var head = el('div', 'cmdk-head');
    head.appendChild(el('span', null, '⌕'));
    input = document.createElement('input');
    input.type = 'search';
    input.placeholder = 'Name, email or uid…';
    input.setAttribute('aria-label', 'Find an account');
    input.setAttribute('autocomplete', 'off');
    input.setAttribute('spellcheck', 'false');
    input.setAttribute('dir', 'auto');
    head.appendChild(input);
    listBox = el('div', 'cmdk-list');
    listBox.setAttribute('role', 'listbox');
    var foot = el('div', 'cmdk-foot');
    foot.appendChild(el('span', null, '↑↓ to move'));
    foot.appendChild(el('span', null, '↵ to open the report'));
    foot.appendChild(el('span', null, 'esc to close'));
    box.appendChild(head);
    box.appendChild(listBox);
    box.appendChild(foot);
    scrim.appendChild(box);
    document.body.appendChild(scrim);
    selected = 0;
    render();
    input.focus();
    ensureAccounts().then(function () { if (scrim) render(); });

    input.addEventListener('input', function () { selected = 0; render(); });
    input.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown') { e.preventDefault(); selected = Math.min(selected + 1, results.length - 1); paintSelection(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); selected = Math.max(selected - 1, 0); paintSelection(); }
      else if (e.key === 'Enter') { e.preventDefault(); if (results[selected]) openAccount(results[selected].uid); }
      else if (e.key === 'Escape') { e.preventDefault(); closeFinder(); }
    });
    scrim.addEventListener('mousedown', function (e) { if (e.target === scrim) closeFinder(); });
  }

  function closeFinder() {
    if (!scrim) return;
    scrim.remove();
    scrim = null;
  }

  var finderButton = document.getElementById('cmdkOpen');
  if (finderButton) finderButton.addEventListener('click', openFinder);
  document.addEventListener('keydown', function (e) {
    if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) {
      e.preventDefault();
      if (scrim) closeFinder(); else openFinder();
    }
  });

  window.GDShell = {
    setLive: setLive,
    provideAccounts: provideAccounts,
    openFinder: openFinder,
    theme: currentTheme,
  };
})();
