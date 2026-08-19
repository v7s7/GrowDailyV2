/**
 * Which of the room's three daily push events a finish just caused.
 *
 * Split out of index.js purely so it can be tested: requiring index.js
 * calls admin.initializeApp(), which needs credentials, so the one piece
 * of real branching logic in this feature would otherwise only ever be
 * exercised in production. See index.js's message tables for why the unit
 * is an event rather than a finisher.
 */

/**
 * @param {Array<{id: string, data: function(): object}>} others Every
 * participant doc EXCEPT the caller, whose own finish is what got us here.
 * @param {string} todayKey The finisher's app day, "YYYY-MM-DD".
 * @return {{event: string, recipients: Array}|null} The event and exactly
 * who should hear about it, or null when nobody should.
 */
function roomEventFor(others, todayKey) {
  if (others.length === 0) return null;
  const unfinished = others.filter((d) => {
    const p = d.data() || {};
    return !(p.allDoneToday === true && p.allDoneDate === todayKey);
  });
  // Order matters where two events could apply at once. In a two-person
  // room the very first finish is ALSO the moment one person is left
  // standing, and "you're the last one" is the more useful of the two - so
  // firstToday is the fallback, checked last, not the default.
  if (unfinished.length === 0) return {event: "perfect", recipients: others};
  if (unfinished.length === 1) {
    return {event: "lastOne", recipients: unfinished};
  }
  return {event: "firstToday", recipients: unfinished};
}

module.exports = {roomEventFor};
