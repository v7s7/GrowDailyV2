/**
 * The Achievements page, in the browser — medals, characters and closet
 * items together, since they are all the same kind of thing to edit: a
 * short piece of catalog text with a built-in fallback.
 *
 * Served as a plain file by server.js (achievements_page.js says why it is
 * not inside a template, same reason as the Wording page). Reads everything
 * once from /api/achievements and /api/cosmetics, lets you edit a
 * name/description/title, and posts one field at a time; every save answers
 * with the fresh state of ITS OWN document (the two are separate documents
 * behind separate endpoints — see lib/achievements_admin.js and
 * lib/cosmetics_admin.js), so the page never shows anything the phones are
 * not seeing.
 */
(function () {
  'use strict';

  const state = { achievements: null, cosmetics: null, saving: new Set() };

  // ---- DOM (same tiny helpers as the Wording page) -------------------------

  function h(tag, props) {
    const el = document.createElement(tag);
    if (props) {
      for (const name of Object.keys(props)) {
        const value = props[name];
        if (value === null || value === undefined || value === false) continue;
        if (name === 'class') el.className = value;
        else if (name.slice(0, 2) === 'on') el.addEventListener(name.slice(2), value);
        else if (value === true) el.setAttribute(name, '');
        else el.setAttribute(name, String(value));
      }
    }
    for (let i = 2; i < arguments.length; i++) append(el, arguments[i]);
    return el;
  }

  function append(el, child) {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) {
      child.forEach((c) => append(el, c));
    } else {
      el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
    }
  }

  function $(id) {
    return document.getElementById(id);
  }

  function clear(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
    return el;
  }

  function button(label, onClick, cls, extra) {
    return h('button', Object.assign({ type: 'button', class: cls || 'btn', onclick: onClick }, extra || {}), label);
  }

  let toastTimer = null;
  function toast(message) {
    const el = $('toast');
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3200);
  }

  function banner(kind, html) {
    return h('div', { class: 'banner ' + kind }, h('div', { class: 'grow' }, html));
  }

  // ---- Server ---------------------------------------------------------------

  async function post(url, payload) {
    let res;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
    } catch (e) {
      return { ok: false, body: { error: 'Could not reach the admin tool. Is it still running?' } };
    }
    let body = {};
    try {
      body = await res.json();
    } catch (e) {
      body = { error: 'The admin tool answered ' + res.status + '.' };
    }
    return { ok: res.ok && body.ok !== false, body };
  }

  function errorText(body) {
    if (!body) return 'The save did not go through.';
    if (body.error) return body.error;
    if (Array.isArray(body.errors)) return body.errors.join(' ');
    return 'The save did not go through.';
  }

  // ---- Rendering --------------------------------------------------------

  const FIELD_LABEL = {
    name: 'Name (EN)', nameAr: 'Name (AR)',
    description: 'Description (EN)', descriptionAr: 'Description (AR)',
    title: 'Title (EN)', titleAr: 'Title (AR)',
    label: 'Label (EN)', labelAr: 'Label (AR)',
  };

  function fieldBox(endpoint, kind, row, field) {
    const isAr = field.endsWith('Ar');
    const current = row.overrides[field] !== undefined ? row.overrides[field] : row[field];
    const edited = row.overrides[field] !== undefined;
    const boxId = kind + ':' + row.id + ':' + field;
    const ta = h('textarea', {
      class: 't-' + (isAr ? 'ar' : 'en'),
      dir: isAr ? 'rtl' : 'ltr',
      rows: 1,
      'data-box': boxId,
      'aria-label': FIELD_LABEL[field],
    });
    ta.value = current;
    const msgs = h('div', { class: 'msgs', id: 'msgs-' + boxId.replace(/[^a-zA-Z0-9]/g, '_') });
    const col = h(
      'div',
      { class: 'field-col' },
      h(
        'div',
        { class: 'lang' },
        FIELD_LABEL[field],
        edited ? h('span', { class: 'badge edited' }, 'Edited') : null,
      ),
      ta,
      edited
        ? h(
            'div',
            { class: 'built-in' },
            'Built-in: ',
            h('span', { class: isAr ? 't-ar' : 't-en' }, row[field]),
            ' ',
            button('Revert', () => saveField(endpoint, kind, row.id, field, ''), 'link-btn'),
          )
        : null,
      msgs,
    );
    return { col, ta };
  }

  // The same four medal colors the app itself paints (GameColors.tierBronze/
  // Silver/Gold/Platinum) — a plain word repeated 24 times reads as one grey
  // list; the tint is what makes a ladder scannable at a glance the way the
  // real Achievements screen already is.
  const TIER_COLOR = { bronze: '#CD7F32', silver: '#B8C0C8', gold: '#E4B45F', platinum: '#6E8CA0' };

  function achievementRow(a) {
    const boxes = {};
    const fields = ['name', 'nameAr', 'description', 'descriptionAr'];
    const cols = fields.map((f) => {
      const { col, ta } = fieldBox('achievements', 'achievement', a, f);
      boxes[f] = ta;
      return col;
    });
    const savemsg = h('span', { class: 'savemsg' });
    const row = h(
      'div',
      { class: 'frow', id: 'ach-' + a.id },
      h(
        'div',
        { class: 'frow-head' },
        h('span', {
          class: 'tier-badge',
          style: 'border-color:' + TIER_COLOR[a.tier] + '55; color:' + TIER_COLOR[a.tier] + ';',
        }, a.tier),
        h('span', { class: 'key' }, a.id),
      ),
      h('div', { class: 'field' }, cols[0], cols[1]),
      h('div', { class: 'field' }, cols[2], cols[3]),
      h(
        'div',
        { class: 'row-foot' },
        button('Save', () => saveRow('achievements', 'achievement', a, fields, boxes, savemsg), 'btn btn-primary'),
        savemsg,
      ),
    );
    return row;
  }

  function familySection(f) {
    const boxes = {};
    const fields = ['title', 'titleAr'];
    const cols = fields.map((field) => {
      const { col, ta } = fieldBox('achievements', 'family', f, field);
      boxes[field] = ta;
      return col;
    });
    const savemsg = h('span', { class: 'savemsg' });
    const achievements = state.achievements.achievements.filter((a) => a.familyId === f.id);
    return h(
      'div',
      { class: 'family', id: 'family-' + f.id },
      h('div', { class: 'family-head' }, h('h2', null, f.title), h('span', { class: 'id' }, f.id)),
      h(
        'div',
        { class: 'frow' },
        h('div', { class: 'field' }, cols[0], cols[1]),
        h(
          'div',
          { class: 'row-foot' },
          button('Save family title', () => saveRow('achievements', 'family', f, fields, boxes, savemsg), 'btn btn-primary'),
          savemsg,
        ),
      ),
      h('div', { class: 'flist' }, achievements.map(achievementRow)),
    );
  }

  function prestigeRow(t) {
    const boxes = {};
    const fields = ['title', 'titleAr'];
    const cols = fields.map((f) => {
      const { col, ta } = fieldBox('cosmetics', 'prestige', t, f);
      boxes[f] = ta;
      return col;
    });
    const savemsg = h('span', { class: 'savemsg' });
    return h(
      'div',
      { class: 'frow', id: 'prestige-' + t.id },
      h(
        'div',
        { class: 'frow-head' },
        h('span', { class: 'tier-badge' }, 'Level ' + t.minLevel),
        h('span', { class: 'key' }, t.id),
      ),
      h('div', { class: 'field' }, cols[0], cols[1]),
      h(
        'div',
        { class: 'row-foot' },
        button('Save', () => saveRow('cosmetics', 'prestige', t, fields, boxes, savemsg), 'btn btn-primary'),
        savemsg,
      ),
    );
  }

  function prestigeSection() {
    return h(
      'div',
      { class: 'family', id: 'section-prestige' },
      h('div', { class: 'family-head' }, h('h2', null, 'Prestige Ranks')),
      h('div', { class: 'flist' }, state.cosmetics.prestige.map(prestigeRow)),
    );
  }

  function characterRow(c) {
    const boxes = {};
    const fields = ['name', 'nameAr'];
    const cols = fields.map((f) => {
      const { col, ta } = fieldBox('cosmetics', 'character', c, f);
      boxes[f] = ta;
      return col;
    });
    const savemsg = h('span', { class: 'savemsg' });
    return h(
      'div',
      { class: 'frow', id: 'char-' + c.id },
      h('div', { class: 'frow-head' }, h('span', { class: 'key' }, c.id)),
      h('div', { class: 'field' }, cols[0], cols[1]),
      h(
        'div',
        { class: 'row-foot' },
        button('Save', () => saveRow('cosmetics', 'character', c, fields, boxes, savemsg), 'btn btn-primary'),
        savemsg,
      ),
    );
  }

  function accessoryRow(a) {
    const boxes = {};
    const fields = ['name', 'nameAr', 'description', 'descriptionAr'];
    const cols = fields.map((f) => {
      const { col, ta } = fieldBox('cosmetics', 'accessory', a, f);
      boxes[f] = ta;
      return col;
    });
    const savemsg = h('span', { class: 'savemsg' });
    return h(
      'div',
      { class: 'frow', id: 'acc-' + a.id },
      h('div', { class: 'frow-head' }, h('span', { class: 'key' }, a.id)),
      h('div', { class: 'field' }, cols[0], cols[1]),
      h('div', { class: 'field' }, cols[2], cols[3]),
      h(
        'div',
        { class: 'row-foot' },
        button('Save', () => saveRow('cosmetics', 'accessory', a, fields, boxes, savemsg), 'btn btn-primary'),
        savemsg,
      ),
    );
  }

  function categoryRow(cat) {
    const boxes = {};
    const fields = ['label', 'labelAr'];
    const cols = fields.map((field) => {
      const { col, ta } = fieldBox('cosmetics', 'category', cat, field);
      boxes[field] = ta;
      return col;
    });
    const savemsg = h('span', { class: 'savemsg' });
    const accessories = state.cosmetics.accessories.filter((a) => a.category === cat.id);
    return h(
      'div',
      { class: 'family', id: 'category-' + cat.id },
      h('div', { class: 'family-head' }, h('h2', null, cat.label), h('span', { class: 'id' }, cat.id)),
      h(
        'div',
        { class: 'frow' },
        h('div', { class: 'field' }, cols[0], cols[1]),
        h(
          'div',
          { class: 'row-foot' },
          button('Save category label', () => saveRow('cosmetics', 'category', cat, fields, boxes, savemsg), 'btn btn-primary'),
          savemsg,
        ),
      ),
      h('div', { class: 'flist' }, accessories.map(accessoryRow)),
    );
  }

  function characterSection() {
    const male = state.cosmetics.characters.filter((c) => c.gender === 'male');
    const female = state.cosmetics.characters.filter((c) => c.gender === 'female');
    return h(
      'div',
      { class: 'family', id: 'section-characters' },
      h('div', { class: 'family-head' }, h('h2', null, 'Characters')),
      h('h3', { class: 'gender-head' }, 'Male'),
      h('div', { class: 'flist' }, male.map(characterRow)),
      h('h3', { class: 'gender-head' }, 'Female'),
      h('div', { class: 'flist' }, female.map(characterRow)),
    );
  }

  /** Jump links to each family/section, so a page with dozens of rows does
   *  not mean scrolling past everything else to reach the one you came to
   *  edit. */
  function jumpNav() {
    const links = [];
    for (const f of state.achievements.families) {
      links.push({ id: 'family-' + f.id, label: f.title });
    }
    links.push({ id: 'section-prestige', label: 'Prestige Ranks' });
    links.push({ id: 'section-characters', label: 'Characters' });
    for (const cat of state.cosmetics.categories) {
      links.push({ id: 'category-' + cat.id, label: cat.label });
    }
    return h(
      'div',
      { class: 'jump-nav' },
      links.map((link) =>
        h(
          'a',
          {
            href: '#' + link.id,
            onclick: (e) => {
              e.preventDefault();
              const el = document.getElementById(link.id);
              if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
            },
          },
          link.label,
        )),
    );
  }

  function render() {
    const view = $('viewList');
    clear(view);
    if (!state.achievements || !state.cosmetics) return;
    view.appendChild(jumpNav());
    view.appendChild(h('div', null, state.achievements.families.map(familySection)));
    view.appendChild(prestigeSection());
    view.appendChild(characterSection());
    view.appendChild(h('div', null, state.cosmetics.categories.map(categoryRow)));
  }

  // ---- Saving -------------------------------------------------------------

  const ENDPOINT = { achievements: '/api/achievements/field', cosmetics: '/api/cosmetics/field' };

  async function saveField(endpoint, kind, id, field, text) {
    const key = endpoint + ':' + kind + ':' + id + ':' + field;
    if (state.saving.has(key)) return false;
    state.saving.add(key);
    const { ok, body } = await post(ENDPOINT[endpoint], { kind, id, field, text });
    state.saving.delete(key);
    if (!ok) {
      toast(errorText(body));
      return false;
    }
    applyData(endpoint, body);
    if (body.changed) toast('Saved.');
    return true;
  }

  async function saveRow(endpoint, kind, row, fields, boxes, savemsg) {
    savemsg.textContent = 'Saving…';
    let anyError = false;
    for (const field of fields) {
      const current = row.overrides[field] !== undefined ? row.overrides[field] : row[field];
      const next = boxes[field].value;
      if (next === current) continue;
      const ok = await saveField(endpoint, kind, row.id, field, next);
      if (!ok) anyError = true;
    }
    savemsg.textContent = anyError ? 'Some fields did not save.' : 'Saved.';
    setTimeout(() => {
      savemsg.textContent = '';
    }, 2500);
  }

  function applyData(endpoint, data) {
    if (endpoint === 'achievements') {
      state.achievements = { families: data.families, achievements: data.achievements };
    } else {
      state.cosmetics = {
        characters: data.characters,
        accessories: data.accessories,
        categories: data.categories,
        prestige: data.prestige,
      };
    }
    render();
  }

  // ---- Boot -----------------------------------------------------------------

  async function load() {
    const [achRes, cosRes] = await Promise.all([fetch('/api/achievements'), fetch('/api/cosmetics')]);
    const [achBody, cosBody] = await Promise.all([achRes.json(), cosRes.json()]);
    if (!achBody.ok) {
      $('banners').appendChild(banner('danger', 'Could not load achievements: ' + errorText(achBody)));
      return;
    }
    if (!cosBody.ok) {
      $('banners').appendChild(banner('danger', 'Could not load characters & items: ' + errorText(cosBody)));
      return;
    }
    applyData('achievements', achBody);
    applyData('cosmetics', cosBody);
  }

  load();
})();
