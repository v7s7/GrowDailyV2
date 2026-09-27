'use strict';

// The prayer place, the way this tool may show it (lib/prayer_place.js): a
// flag, the place's own label, and how it was set. Never the coordinates,
// and nothing at all in a saved report.

const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const {
  prayerPlaceOf, profileForDisplay, flagEmoji, countryName, LABEL_MAX, LEFT_OUT,
} = require('../lib/prayer_place');
const { buildReportBody, renderFieldTable } = require('../lib/render');

const BH_FLAG = String.fromCodePoint(0x1F1E7, 0x1F1ED);
const RIFFA = { lat: 26.129999, lng: 50.555111, label: 'الرفاع، البحرين', auto: true };

function profileWith(location, code) {
  return {
    displayName: 'Test',
    notificationSettings: { masterEnabled: true, location, resolvedCountryCode: code },
  };
}

test('flagEmoji turns a two-letter code into its flag, and nothing else into anything', () => {
  assert.strictEqual(flagEmoji('BH'), BH_FLAG);
  assert.strictEqual(flagEmoji('bh'), BH_FLAG);
  assert.strictEqual(flagEmoji('EG'), String.fromCodePoint(0x1F1EA, 0x1F1EC));
  for (const bad of ['BHR', 'B', 'B1', '', '<b>', null, undefined, 12]) {
    assert.strictEqual(flagEmoji(bad), '', `${String(bad)} is not a country code`);
  }
});

test('countryName names the country in English, and nothing for a code with no country', () => {
  assert.strictEqual(countryName('BH'), 'Bahrain');
  assert.strictEqual(countryName('SA'), 'Saudi Arabia');
  assert.strictEqual(countryName('ZZ'), '');
  assert.strictEqual(countryName('XX'), '');
});

test('a place found by the phone: flag, label, country, and how it was set', () => {
  const place = prayerPlaceOf(profileWith(RIFFA, 'BH'));
  assert.deepStrictEqual(place, {
    label: 'الرفاع، البحرين',
    country: 'BH',
    flag: BH_FLAG,
    countryName: 'Bahrain',
    source: 'phone',
    sourceText: 'from their phone',
    title: 'Prayer place: الرفاع، البحرين (Bahrain), from their phone',
  });
});

test('a picked city and an older save each say so', () => {
  const city = prayerPlaceOf(profileWith({ ...RIFFA, label: 'Cairo, Egypt', auto: false }, 'EG'));
  assert.strictEqual(city.source, 'city');
  assert.strictEqual(city.sourceText, 'a city they picked');
  // No "(Egypt)" after a label that already says it.
  assert.strictEqual(city.title, 'Prayer place: Cairo, Egypt, a city they picked');

  const { auto, ...legacy } = RIFFA;
  const older = prayerPlaceOf(profileWith(legacy, 'BH'));
  assert.strictEqual(older.source, 'unknown');
  assert.match(older.sourceText, /before 25 Sept/);
});

test('no place unless the app itself would have one', () => {
  // NotificationLocation.fromMap: numeric lat and lng and a non-empty label.
  const cases = [
    null,
    {},
    { notificationSettings: 'on' },
    { notificationSettings: {} },
    profileWith(null, 'BH'),
    profileWith({ ...RIFFA, lat: undefined }, 'BH'),
    profileWith({ ...RIFFA, lng: '50.55' }, 'BH'),
    profileWith({ ...RIFFA, label: '' }, 'BH'),
    profileWith({ ...RIFFA, label: 7 }, 'BH'),
  ];
  for (const profile of cases) {
    assert.strictEqual(prayerPlaceOf(profile), null, JSON.stringify(profile));
  }
});

test('a code that is not two letters gives no flag, and the place still shows', () => {
  for (const code of ['BHR', '<b>', 'B1', 12, undefined, '']) {
    const place = prayerPlaceOf(profileWith(RIFFA, code));
    assert.strictEqual(place.flag, '', String(code));
    assert.strictEqual(place.country, '');
    assert.strictEqual(place.label, 'الرفاع، البحرين');
    assert.strictEqual(place.title, 'Prayer place: الرفاع، البحرين, from their phone');
  }
  assert.strictEqual(prayerPlaceOf(profileWith(RIFFA, ' bh ')).flag, BH_FLAG);
});

test('the place never carries the coordinates', () => {
  const place = prayerPlaceOf(profileWith(RIFFA, 'BH'));
  assert.ok(!('lat' in place) && !('lng' in place));
  const json = JSON.stringify(place);
  assert.ok(!json.includes('26.1') && !json.includes('50.5'), json);
});

test('a long label is clipped by code point, never inside an emoji', () => {
  const long = String.fromCodePoint(0x1F54C).repeat(LABEL_MAX + 20);
  const place = prayerPlaceOf(profileWith({ ...RIFFA, label: long }, 'BH'));
  const chars = Array.from(place.label);
  assert.strictEqual(chars.length, LABEL_MAX);
  assert.strictEqual(chars[chars.length - 1], '…');
  for (const ch of chars) {
    const cp = ch.codePointAt(0);
    assert.ok(cp < 0xD800 || cp > 0xDFFF, 'no half of a surrogate pair');
  }
  const blank = prayerPlaceOf(profileWith({ ...RIFFA, label: '   ' }, 'BH'));
  assert.strictEqual(blank.label, 'Bahrain', 'an all-space label falls back to the country');
});

test('the Raw tab rounds the point to one decimal in the live report', () => {
  const profile = profileWith(RIFFA, 'BH');
  const before = JSON.parse(JSON.stringify(profile));
  const shown = profileForDisplay(profile);
  assert.strictEqual(shown.notificationSettings.location.lat, '26.1 (rounded here, about 11 km)');
  assert.strictEqual(shown.notificationSettings.location.lng, '50.6 (rounded here, about 11 km)');
  assert.strictEqual(shown.notificationSettings.location.label, RIFFA.label);
  assert.strictEqual(shown.notificationSettings.resolvedCountryCode, 'BH');
  assert.strictEqual(shown.notificationSettings.masterEnabled, true);
  assert.deepStrictEqual(profile, before, 'the profile itself is left alone');

  const html = renderFieldTable(shown);
  assert.ok(!html.includes('26.129999') && !html.includes('50.555111'), 'no stored digits');
  assert.ok(html.includes('26.1 (rounded here, about 11 km)'));
  assert.strictEqual(
    profileForDisplay(profileWith({ ...RIFFA, lat: -0.04 }, 'BH')).notificationSettings.location.lat,
    '0.0 (rounded here, about 11 km)',
  );
});

test('a saved report leaves the place out of the Raw tab', () => {
  const shown = profileForDisplay(profileWith(RIFFA, 'BH'), { forFile: true });
  assert.strictEqual(shown.notificationSettings.location, LEFT_OUT);
  assert.strictEqual(shown.notificationSettings.resolvedCountryCode, LEFT_OUT);
  assert.strictEqual(shown.notificationSettings.masterEnabled, true, 'the rest of the settings stay');
  const html = renderFieldTable(shown);
  assert.ok(!html.includes('26.1') && !html.includes('الرفاع') && !html.includes('>BH<'), html);
});

test('a profile with no settings comes back as it is', () => {
  const plain = { displayName: 'x' };
  assert.strictEqual(profileForDisplay(plain), plain);
  assert.strictEqual(profileForDisplay(null), null);
  const noPlace = { notificationSettings: { masterEnabled: false } };
  assert.deepStrictEqual(profileForDisplay(noPlace, { forFile: true }), noPlace);
});

test('the live report puts the flag beside the name and the place in the strip', () => {
  const profileData = profileWith(RIFFA, 'BH');
  const { header, stats } = buildReportBody({
    uid: 'u1', authRecord: null, profileData, sections: [], place: prayerPlaceOf(profileData),
  });
  assert.ok(header.includes(`<span class="idline-flag" title="Prayer place: الرفاع، البحرين (Bahrain), from their phone">${BH_FLAG}</span>`), header);
  assert.ok(stats.includes('<span>Prayer place</span>'), stats);
  assert.ok(stats.includes(`${BH_FLAG} <span class="bidi">الرفاع، البحرين</span>`), stats);
  assert.ok(stats.includes('<span class="stat-src">from their phone</span>'), stats);
});

test('a report with no place, a saved one included, shows neither', () => {
  const { header, stats } = buildReportBody({
    uid: 'u1', authRecord: null, profileData: profileWith(RIFFA, 'BH'), sections: [], place: null,
  });
  assert.ok(!header.includes('idline-flag'));
  assert.ok(!stats.includes('Prayer place'));
});

test('a hostile label is escaped in the report header and strip', () => {
  const profileData = profileWith({ ...RIFFA, label: '"><img src=x onerror=alert(1)>' }, 'BH');
  const { header, stats } = buildReportBody({
    uid: 'u1', authRecord: null, profileData, sections: [], place: prayerPlaceOf(profileData),
  });
  for (const html of [header, stats]) {
    assert.ok(!html.includes('<img'), html);
    assert.ok(html.includes('&quot;&gt;&lt;img src=x onerror=alert(1)&gt;'), html);
  }
});

test('the dashboard draws the flag and the drawer line escaped', () => {
  // flagHtml and placeHtml live in the browser script inside server.js's
  // page template. Run them as the browser would, with the page's own esc().
  const src = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
  const start = src.indexOf('  function esc(s) {');
  const end = src.indexOf('  // Every date and time on this page, in one language.');
  assert.ok(start > 0 && end > start, 'the helpers sit between esc() and the date helpers');
  const page = vm.runInNewContext(`${src.slice(start, end)}; ({ flagHtml, placeHtml });`);

  const place = prayerPlaceOf(profileWith({ ...RIFFA, label: '"><img src=x onerror=alert(1)>' }, 'BH'));
  const flag = page.flagHtml(place, 'u-flag');
  assert.ok(flag.startsWith('<span class="u-flag" title="Prayer place: &quot;&gt;&lt;img'), flag);
  assert.ok(flag.endsWith(`>${BH_FLAG}</span>`), flag);
  const line = page.placeHtml(place);
  assert.ok(!line.includes('<img') && line.includes('&lt;img'), line);
  assert.ok(line.includes('from their phone'), line);

  assert.strictEqual(page.flagHtml(null, 'u-flag'), '');
  assert.strictEqual(page.flagHtml(prayerPlaceOf(profileWith(RIFFA, 'BHR')), 'u-flag'), '');
  assert.ok(page.placeHtml(null).includes('none saved'));
});
