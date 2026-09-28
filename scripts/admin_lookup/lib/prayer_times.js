'use strict';

/**
 * Prayer times for the Reminders tab, so a reminder set "15 minutes before
 * Fajr" can be shown as the clock time it actually rings at.
 *
 * Only where this tool can give the phone's OWN answer: inside the app's
 * Bahrain box, on a date Bahrain's official timetable covers. That is the
 * file the app bundles (assets/prayer/bahrain_official.json), read from the
 * repo here the way lib/habit_catalog.js reads the catalog, so the two can
 * never hold different figures. PrayerTimesService uses it ahead of every
 * other source for exactly those coordinates and dates (_bahrainOfficial).
 *
 * Anywhere else the phone asks the Aladhan API first and calculates only
 * when that fails, so any figure worked out here could differ from what the
 * phone armed. This returns null there and the tab says the time is not
 * worked out, rather than showing a clock time that might be wrong.
 *
 * The coordinates go in and never come out: the answer is prayer times,
 * never the point they were worked out for (see lib/prayer_place.js).
 */

const fs = require('fs');
const path = require('path');

const BAHRAIN_TABLE = path.join(__dirname, '..', '..', '..',
  'assets', 'prayer', 'bahrain_official.json');

/** The five prayers a habit can be anchored to (HabitCue.prayerKey). */
const PRAYER_KEYS = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

/** The table's column order, sunrise included (BahrainPrayerTable._order). */
const TABLE_ORDER = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

/**
 * The table's times are Bahrain wall clock (its own "timezone" field says
 * Asia/Bahrain), which has no daylight saving: always UTC+3.
 */
const BAHRAIN_UTC_OFFSET_MIN = 180;

/**
 * PrayerTimesService._regions' Bahrain box, the same generous rectangle
 * (Manama, Muharraq, Sitra, Hawar). isInBahrain there, verbatim.
 */
function isInBahrain(lat, lng) {
  return typeof lat === 'number' && typeof lng === 'number'
    && lat >= 25.5 && lat <= 26.5 && lng >= 50.3 && lng <= 50.9;
}

let _table = null; // { mtimeMs, days, first, last }

/**
 * The parsed table, re-read only when the file changes. A missing or
 * malformed file gives an empty table, so prayer reminders show "not worked
 * out" rather than the report failing.
 */
function bahrainTable() {
  let mtimeMs = null;
  try {
    mtimeMs = fs.statSync(BAHRAIN_TABLE).mtimeMs;
  } catch (_) {
    mtimeMs = null;
  }
  if (_table && _table.mtimeMs === mtimeMs) return _table;
  let days = {};
  let first = null;
  let last = null;
  if (mtimeMs !== null) {
    try {
      const decoded = JSON.parse(fs.readFileSync(BAHRAIN_TABLE, 'utf8'));
      if (decoded && decoded.days && typeof decoded.days === 'object') days = decoded.days;
      first = typeof decoded.first === 'string' ? decoded.first : null;
      last = typeof decoded.last === 'string' ? decoded.last : null;
    } catch (_) {
      days = {};
    }
  }
  if (Object.keys(days).length === 0) {
    console.warn(`prayer_times: no Bahrain timetable read from ${BAHRAIN_TABLE}; prayer reminder times will not be shown.`);
  }
  _table = { mtimeMs, days, first, last };
  return _table;
}

/**
 * One day's times from the Bahrain table as epoch milliseconds, keyed
 * fajr / sunrise / dhuhr / asr / maghrib / isha, or null when the table has
 * no such day (BahrainPrayerTable.lookup: a malformed row is null too).
 *
 * [dateKey] is 'YYYY-MM-DD', the PHONE's local date: calculateDays walks the
 * device's own calendar days and looks each one up by its date.
 */
function bahrainDay(dateKey) {
  const row = bahrainTable().days[dateKey];
  if (typeof row !== 'string') return null;
  const parts = row.split(' ');
  if (parts.length !== TABLE_ORDER.length) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!m) return null;
  const out = {};
  for (let i = 0; i < TABLE_ORDER.length; i++) {
    const hm = /^(\d{1,2}):(\d{2})$/.exec(parts[i]);
    if (!hm) return null;
    out[TABLE_ORDER[i]] = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
      Number(hm[1]), Number(hm[2])) - BAHRAIN_UTC_OFFSET_MIN * 60000;
  }
  return out;
}

/**
 * A day-lookup for one prayer place: (dateKey) => times or null, plus what
 * it can answer, for the tab to say.
 *
 *   source 'bahrain'  the official table; null only past its last date.
 *   source 'none'     outside Bahrain: every lookup is null.
 *
 * [location] is notificationSettings.location as stored ({lat, lng, ...}),
 * or anything else for "no place".
 */
function prayerTimesFor(location) {
  const lat = location && typeof location === 'object' ? location.lat : undefined;
  const lng = location && typeof location === 'object' ? location.lng : undefined;
  if (isInBahrain(lat, lng)) {
    const t = bahrainTable();
    return { source: 'bahrain', last: t.last, dayTimes: (key) => bahrainDay(key) };
  }
  return { source: 'none', last: null, dayTimes: () => null };
}

module.exports = {
  BAHRAIN_TABLE,
  BAHRAIN_UTC_OFFSET_MIN,
  PRAYER_KEYS,
  isInBahrain,
  bahrainTable,
  bahrainDay,
  prayerTimesFor,
};
