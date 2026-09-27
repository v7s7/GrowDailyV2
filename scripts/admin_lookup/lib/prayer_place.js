'use strict';

/**
 * An account's prayer place, cut down to what a support question needs.
 *
 * The app keeps it on users/{uid}.notificationSettings: `location` is
 * {lat, lng, label, auto} (NotificationLocation in
 * lib/features/settings/models/notification_settings.dart), and
 * `resolvedCountryCode` is the ISO code BigDataCloud gave for the same point.
 * Only a signed-in account has one here. A guest's stays on the phone.
 *
 * The coordinates are the phone's own fix, at up to GPS precision, and they
 * only move after 10 km of travel (kPrayerPlaceMoveMeters), so for most
 * people they point at home. People were told the place is saved so their
 * reminders stay correct across their devices (public/privacy.html), and
 * "why are my prayer times wrong" needs the city, the country, and whether
 * the phone found it or they picked it. So that is all this tool shows: a
 * flag beside the name, the place's own label, and where it came from.
 * Never a map, never the exact point, and nothing to search or count people
 * by (Aziz, 2026-09-27).
 *
 * Every field is the account's own write, and the rules check none of it
 * (see test/escaping.test.js). So the code must be two letters before it
 * becomes a flag, the label is clipped here, and every page escapes both.
 */

// The app's label is "City, Country" (CountryLookupService.lookupPlace), or
// whatever name someone typed beside hand-entered coordinates, which has no
// limit at all. Long enough for any real place, short enough that a pasted
// paragraph cannot push the name line off the screen.
const LABEL_MAX = 80;

const REGION_NAMES = new Intl.DisplayNames(['en'], { type: 'region' });

// In the app's own terms (the Prayer location page's «من موقع تلفونك» and
// «مدينة اخترتها»), said about them rather than to them.
const SOURCE_TEXT = {
  phone: 'from their phone',
  city: 'a city they picked',
  unknown: 'saved before 25 Sept, source not recorded',
};

// What a saved report prints where the place would be.
const LEFT_OUT = 'left out of saved reports';

function clip(text, max) {
  // By code point, so a cut never lands inside an emoji's surrogate pair.
  const chars = Array.from(text);
  return chars.length > max ? `${chars.slice(0, max - 1).join('')}…` : text;
}

/** 'BH' to its flag emoji; '' for anything that is not two letters. */
function flagEmoji(code) {
  if (typeof code !== 'string' || !/^[A-Za-z]{2}$/.test(code)) return '';
  // A flag emoji is its two letters moved into the regional indicator block,
  // which starts at U+1F1E6 for A.
  const up = code.toUpperCase();
  return String.fromCodePoint(
    0x1F1E6 + up.charCodeAt(0) - 65,
    0x1F1E6 + up.charCodeAt(1) - 65,
  );
}

/** 'BH' to 'Bahrain', in English like the rest of this tool; '' if unknown. */
function countryName(code) {
  try {
    const name = REGION_NAMES.of(code);
    // A well-formed code with no country behind it comes back as itself,
    // or as "Unknown Region" for ZZ.
    return name && name !== code && name !== 'Unknown Region' ? name : '';
  } catch (_) {
    return '';
  }
}

/**
 * The prayer place the app would use for this profile, or null when it has
 * none. Same test as NotificationLocation.fromMap: numeric lat and lng and a
 * non-empty label, or the app treats the place as unset.
 *
 * Returns { label, country, flag, countryName, source, sourceText, title },
 * with `source` 'phone' (auto true), 'city' (auto false) or 'unknown' (saved
 * before 2026-09-25, when the app did not record which). There are no
 * coordinates in it, so nothing drawn from it can print them.
 */
function prayerPlaceOf(profile) {
  const ns = profile && profile.notificationSettings;
  if (!ns || typeof ns !== 'object') return null;
  const loc = ns.location;
  if (!loc || typeof loc !== 'object') return null;
  if (typeof loc.lat !== 'number' || typeof loc.lng !== 'number') return null;
  if (typeof loc.label !== 'string' || loc.label.length === 0) return null;

  const rawCode = typeof ns.resolvedCountryCode === 'string' ? ns.resolvedCountryCode.trim() : '';
  const country = /^[A-Za-z]{2}$/.test(rawCode) ? rawCode.toUpperCase() : '';
  const name = country ? countryName(country) : '';
  const label = clip(loc.label.trim(), LABEL_MAX) || name || 'a place with no name';
  const source = loc.auto === true ? 'phone' : loc.auto === false ? 'city' : 'unknown';
  // The English country name helps beside an Arabic label, and only repeats
  // itself beside "Cairo, Egypt".
  const named = name && !label.includes(name) ? ` (${name})` : '';
  return {
    label,
    country,
    flag: flagEmoji(country),
    countryName: name,
    source,
    sourceText: SOURCE_TEXT[source],
    title: `Prayer place: ${label}${named}, ${SOURCE_TEXT[source]}`,
  };
}

function roundedDegree(value) {
  return `${(Math.round(value * 10) / 10).toFixed(1)} (rounded here, about 11 km)`;
}

/**
 * The profile as the Raw tab may print it.
 *
 * Live, the place's lat and lng are rounded to one decimal, about 11 km:
 * enough to work out their prayer times again (they move under a minute per
 * 25 km), not enough to find a house. A saved report (lookup_user.js) leaves
 * the place out entirely, since a file on disk outlives the question it was
 * saved for. Returns a copy and leaves the profile itself alone.
 */
function profileForDisplay(profile, { forFile = false } = {}) {
  const ns = profile && profile.notificationSettings;
  if (!ns || typeof ns !== 'object' || Array.isArray(ns)) return profile;
  const shown = { ...ns };
  if (forFile) {
    for (const key of ['location', 'resolvedCountryCode']) {
      if (key in shown) shown[key] = LEFT_OUT;
    }
  } else if (shown.location && typeof shown.location === 'object' && !Array.isArray(shown.location)) {
    const loc = { ...shown.location };
    for (const key of ['lat', 'lng']) {
      if (typeof loc[key] === 'number' && Number.isFinite(loc[key])) loc[key] = roundedDegree(loc[key]);
    }
    shown.location = loc;
  }
  return { ...profile, notificationSettings: shown };
}

/**
 * The Firestore fields a select() needs for prayerPlaceOf. The dashboard and
 * the account finder read profiles through select(), where a field left off
 * the list simply arrives undefined.
 */
const PRAYER_PLACE_FIELDS = ['notificationSettings.location', 'notificationSettings.resolvedCountryCode'];

module.exports = {
  prayerPlaceOf,
  profileForDisplay,
  flagEmoji,
  countryName,
  PRAYER_PLACE_FIELDS,
  LABEL_MAX,
  LEFT_OUT,
  SOURCE_TEXT,
};
