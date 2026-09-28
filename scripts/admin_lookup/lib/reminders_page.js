'use strict';

/**
 * The Reminders tab: lib/reminders.js's model, drawn.
 *
 * Three questions, in the order a support message asks them: when does each
 * reminder ring, is anything stopping it, and what are the settings behind
 * that. Every time is on the ACCOUNT's clock, never this machine's, and the
 * tab says which clock that is.
 *
 * Reuses the report's own table (table.ledger, from the Day tab) so a habit
 * reads the same way on both tabs; the few classes of its own are .rem-*.
 */

const { escapeHtml, CATEGORY_META } = require('./render');
const R = require('./reminders');

const WEEKDAY_SHORT = { 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun' };
const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "Today", "Tomorrow", "Yesterday", else "Mon 29 Sep", on their clock. */
function dayLabel(ms, model) {
  const l = R.localOf(ms, model.clock.offset);
  if (l.key === model.todayKey) return 'Today';
  if (l.key === R.addDays(model.todayKey, 1)) return 'Tomorrow';
  if (l.key === R.addDays(model.todayKey, -1)) return 'Yesterday';
  const [, m, d] = l.key.split('-').map(Number);
  return `${WEEKDAY_SHORT[l.weekday]} ${d} ${MONTH_SHORT[m - 1]}`;
}

/** "Today 04:02" on their clock. */
function whenText(ms, model) {
  return `${dayLabel(ms, model)} ${R.fmtClock(R.localOf(ms, model.clock.offset).minute)}`;
}

/** "UTC+3", "UTC-7", "UTC+5:30". */
function utcLabel(offset) {
  const sign = offset < 0 ? '-' : '+';
  const a = Math.abs(offset);
  const h = Math.floor(a / 60);
  const m = a % 60;
  return `UTC${sign}${h}${m ? `:${String(m).padStart(2, '0')}` : ''}`;
}

function daysText(weekdays) {
  return weekdays.length ? weekdays.map((d) => WEEKDAY_SHORT[d]).join(', ') : 'Every day';
}

function quietText(s) {
  return `${R.fmtClock(s.quietStartMin)} to ${R.fmtClock(s.quietEndMin)}`;
}

/** Whether quiet hours are really in force (a zero-width window never is). */
function quietOn(s) {
  return s.quietHoursEnabled && s.quietStartMin !== null && s.quietEndMin !== null
    && s.quietStartMin !== s.quietEndMin;
}

/** How a habit's reminder arrives, with the platform detail as a tooltip. */
function ringsAs(h) {
  if (h.isQuit) {
    return `<span class="rem-as" title="A notification asking whether they kept it, with التزام and ما التزمت buttons. A quit habit never rings as an alarm.">Check-in</span>`;
  }
  if (h.alarm) {
    return `<span class="rem-as alarm" title="Rings as an alarm on iOS 26 or newer with alarms allowed, even on silent. Older iPhones, or alarms not allowed: a Time Sensitive notification. Android: a notification with the alarm sound."><span class="rem-ico">⏰</span>Alarm</span>`;
  }
  return '<span class="rem-as">Notification</span>';
}

/**
 * One slot's "Next ring" line: the moment, or why there is none. A reason
 * beside a moment says why it is not the obvious one.
 */
function nextLine(slot, model) {
  switch (slot.state) {
    case 'rings': {
      const why = [];
      if (slot.doneToday) why.push('done today, so today\'s was taken down');
      if (slot.quietSome) why.push('skipped on days it lands in quiet hours');
      return `<b class="rem-when">${escapeHtml(whenText(slot.next, model))}</b>`
        + (why.length ? ` <span class="rem-why">${escapeHtml(why.join('; '))}</span>` : '');
    }
    case 'unknown':
      if (model.forFile) {
        return '<span class="rem-none" title="A prayer time says roughly where someone is, and saved reports leave the place out.">Left out of saved reports</span>';
      }
      return model.settings.mirrored
        ? '<span class="rem-none" title="Outside Bahrain the phone gets prayer times from the Aladhan service, so this tool does not work them out. It rings at their prayer plus the shift.">Not worked out here</span>'
        : '<span class="rem-none" title="Their phone never uploaded its settings, so whether it has a prayer place is unknown.">Unknown</span>';
    case 'quiet':
      return `<span class="rem-bad" title="Quiet hours ${escapeHtml(quietText(model.settings))}. The phone arms nothing inside them unless the reminder is an alarm or set to Allow anyway.">Never: in quiet hours</span>`;
    case 'no-place':
      return '<span class="rem-bad" title="A prayer reminder is timed from the prayer place in their settings, and there is none.">Never: no prayer place</span>';
    case 'off':
      return `<span class="rem-bad">Off: ${model.settings.masterEnabled ? 'habit reminders off' : 'notifications off'}</span>`;
    case 'not-due':
      return '<span class="rem-none" title="The phone arms reminders only for habits due in the next 7 days.">Not due this week</span>';
    default:
      return '<span class="rem-none">Nothing ahead</span>';
  }
}

function habitNameCell(h) {
  const cat = CATEGORY_META[h.category] || CATEGORY_META.custom;
  return `<th scope="row" class="lg-habit"><span class="lg-emo">${cat.emoji}</span>`
    + `<span class="lg-name">${escapeHtml(h.name)}</span></th>`;
}

function renderHabitTable(model) {
  if (!model.habits.length) {
    return '<p class="muted">No habit has a reminder.</p>';
  }
  const rows = model.habits.map((h) => {
    const lines = (fn) => h.slots.map((s) => `<div class="rem-line">${fn(s)}</div>`).join('');
    const bad = h.slots.every((s) => s.state !== 'rings' && s.state !== 'unknown');
    return `<tr class="lg-row${bad ? ' rem-dead' : ''}">
        ${habitNameCell(h)}
        <td>${lines((s) => escapeHtml(s.label))}</td>
        <td>${lines((s) => nextLine(s, model))}</td>
        <td>${ringsAs(h)}</td>
        <td>${escapeHtml(daysText(h.weekdays))}</td>
      </tr>`;
  }).join('');
  return `<div class="lg-wrap"><table class="ledger rem-table">
      <thead><tr>
        <th class="lg-habit">Habit</th>
        <th title="What they picked: a time or a prayer, and how far before or after it.">Reminder</th>
        <th title="The next moment it rings, on their clock, by the phone's own rules: its days, quiet hours, and already done today.">Next ring</th>
        <th>Rings as</th>
        <th>Days</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table></div>`;
}

const WITHOUT_WHY = {
  none: 'no reminder set',
  routine: 'anchored to a routine with no clock time',
  text: 'anchored to their own words, which have no clock time',
  damaged: 'its stored time is unreadable, so the app shows none',
};

function renderWithout(model) {
  if (!model.without.length) return '';
  const items = model.without.map((h) => {
    let why = WITHOUT_WHY[h.cue.kind] || WITHOUT_WHY.none;
    if (h.cue.kind === 'routine') {
      why = `anchored to ${R.ROUTINE_NAMES[h.cue.routineKey] || 'a routine'}, which has no clock time`;
    }
    return `<li><span class="bidi">${escapeHtml(h.name)}</span>: ${escapeHtml(why)}</li>`;
  }).join('');
  return `<div class="offsched"><b>No reminder</b><ul>${items}</ul></div>`;
}

function renderTasks(model) {
  if (!model.tasks.length) {
    return '<p class="muted">No open task has a reminder ahead or in the last '
      + `${R.TASK_PASSED_DAYS} days.</p>`;
  }
  const off = !model.settings.masterEnabled;
  const rows = model.tasks.map((t) => {
    const lines = [
      ...t.recent.map((ms) => `<div class="rem-line"><span class="rem-past">${escapeHtml(whenText(ms, model))}</span> <span class="rem-why">passed</span></div>`),
      ...t.ahead.slice(0, R.TASK_ARMED_CAP).map((ms) => `<div class="rem-line">${off
        ? `<span class="rem-bad">${escapeHtml(whenText(ms, model))}, off</span>`
        : `<b class="rem-when">${escapeHtml(whenText(ms, model))}</b>`}</div>`),
    ];
    if (t.overCap) {
      lines.push(`<div class="rem-line"><span class="rem-why">${t.overCap} more after these, armed once the first ones have rung</span></div>`);
    }
    return `<tr class="lg-row">
        <th scope="row" class="lg-habit"><span class="lg-name">${escapeHtml(t.title)}</span></th>
        <td>${lines.join('')}</td>
        <td>${t.alarm
          ? '<span class="rem-as alarm" title="Rings as an alarm on iOS 26 or newer with alarms allowed; otherwise a notification."><span class="rem-ico">⏰</span>Alarm</span>'
          : '<span class="rem-as">Notification</span>'}</td>
      </tr>`;
  }).join('');
  return `<div class="lg-wrap"><table class="ledger rem-table">
      <thead><tr>
        <th class="lg-habit">Task</th>
        <th title="Open tasks only: a finished task rings nothing. A reminder that passed while the app was closed gets one catch-up notification the next time it opens.">Reminders</th>
        <th>Rings as</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table></div>`;
}

function renderSettings(model) {
  const s = model.settings;
  const row = (label, html) => `<tr><th>${escapeHtml(label)}</th><td>${html}</td></tr>`;
  const onOff = (v, offText) => (v ? 'On' : `<span class="rem-bad">${escapeHtml(offText)}</span>`);

  // Room pushes and the admin's messages wait out the night whatever this
  // switch says (functions/push_policy.js rule 1); it only moves the window.
  const oldBuild = s.mirrored && s.quietFromOldBuild
    ? ' <span class="rem-why">as a build before quiet hours went off by default reads it</span>'
    : '';
  const quiet = quietOn(s)
    ? `${escapeHtml(quietText(s))}. ${s.quietHoursAppliesToPrayer
      ? 'Prayer reminders are silenced too; alarms and habits set to "Allow anyway" still ring.'
      : 'Prayer reminders, alarms and habits set to "Allow anyway" still ring.'} Tasks ignore quiet hours. Room pushes and your messages wait until it ends.${oldBuild}`
    : `Off: every reminder rings at its time. Room pushes and your messages still wait out the night, 22:00 to 07:00.${oldBuild}`;

  let evening;
  if (model.evening.state === 'none') {
    evening = 'None saved to the account <span class="rem-why">a time picked while signed out stays on the phone</span>';
  } else {
    const at = R.fmtClock(model.evening.at);
    evening = {
      rings: `${at} every evening, while something on today's list is still open`,
      quiet: `<span class="rem-bad">${at}, silenced: inside quiet hours</span>`,
      off: `<span class="rem-bad">${at}, off with notifications</span>`,
    }[model.evening.state];
  }

  const weekly = {
    none: 'Not chosen',
    off: '<span class="rem-bad">Chosen, but not sent: notifications are off or there are no habits</span>',
    rings: 'Saturdays at 10:00',
  }[model.weekly.state];

  let prayer;
  if (model.forFile) prayer = 'Left out of saved reports';
  else if (s.hasPlace === null) prayer = 'Unknown: their settings were never uploaded';
  else if (!s.hasPlace) prayer = '<span class="rem-bad">No prayer place set, so no prayer reminder can ring</span>';
  else if (model.placeSource === 'bahrain') {
    prayer = `Bahrain's official timetable, the one the app uses there${model.placeLast ? ` (it runs to ${escapeHtml(model.placeLast)})` : ''}`;
  } else {
    prayer = 'Outside Bahrain. The phone gets them from the Aladhan service, so they are not worked out here';
  }

  const clock = model.clock.known
    ? `${utcLabel(model.clock.offset)}, as their phone last reported`
    : `${utcLabel(model.clock.offset)}, this computer's: their phone never reported one`;

  const seen = model.lastSeen === null
    ? 'No trace'
    : `${escapeHtml(whenText(model.lastSeen, model))}${model.stale ? ' <span class="rem-bad">(a while ago, see above)</span>' : ''}`;

  return `<table class="fields rem-settings"><tbody>
      ${row('Notifications', onOff(s.masterEnabled, 'Off: nothing rings'))}
      ${row('Habit reminders', onOff(s.habitRemindersEnabled, 'Off: no habit reminder rings'))}
      ${row('Quiet hours', quiet)}
      ${row('Evening note', evening)}
      ${row('Saturday note', weekly)}
      ${row('Close together', s.bundleEnabled
        ? 'Reminders within 15 minutes of each other arrive as one notification'
        : 'Each reminder arrives on its own')}
      ${row('Prayer times', prayer)}
      ${row('Their clock', clock)}
      ${row('Last seen', `${seen} <span class="rem-why">the latest the phone wrote, or refreshed its push token</span>`)}
      ${row('Settings from', s.mirrored
        ? 'Their phone\'s last upload'
        : '<span class="rem-bad">The app\'s defaults: their phone never uploaded its settings</span>')}
    </tbody></table>`;
}

/** The banners worth reading before anything else, loudest first. */
function renderWarnings(model) {
  const s = model.settings;
  const out = [];
  if (!s.masterEnabled) {
    out.push('All notifications are switched off in the app, so nothing on this tab rings.');
  } else if (!s.habitRemindersEnabled && model.habits.length) {
    out.push('Habit reminders are switched off in the app, so no habit reminder rings. Tasks and the evening note still do.');
  }
  if (model.stale) {
    const days = Math.floor((model.nowMs - model.lastSeen) / 86400000);
    out.push(`Their phone was last seen ${days} days ago. It keeps only the next ${R.OCCURRENCES_PER_SLOT} of each `
      + `habit reminder armed${model.anyAlarm ? ' (alarms a month)' : ''} and tops them up when the app opens, `
      + 'so if it has not been opened since, the habit reminders below have probably run out.');
  }
  const warn = out.map((t) => `<div class="rem-warn">${escapeHtml(t)}</div>`).join('');
  const calm = s.mirrored ? '' : '<div class="rem-warn calm">Their phone never uploaded its notification settings, '
    + 'so the app\'s defaults stand in below. Its real settings may differ.</div>';
  return warn + calm;
}

function renderTally(model) {
  const eve = model.evening.state === 'none' ? 'none' : R.fmtClock(model.evening.at);
  return `<div class="tally">
      <div class="ty"><b>${model.counts.habits}</b><span>habit${model.counts.habits === 1 ? '' : 's'} with reminders</span></div>
      <div class="ty"><b>${model.counts.tasksAhead}</b><span>task${model.counts.tasksAhead === 1 ? '' : 's'} with one ahead</span></div>
      <div class="ty"><b>${escapeHtml(eve)}</b><span>evening note</span></div>
    </div>`;
}

/**
 * The tab: { id, label, count, alert, html }. `alert` turns the tab's count
 * amber, the way a disagreeing day does on the Day tab, when switches in the
 * app stop reminders from ringing.
 */
function renderRemindersSection(model) {
  const s = model.settings;
  const html = `<div class="rem">
      ${renderWarnings(model)}
      ${renderTally(model)}
      <h3>Habits<span class="h3-note">times on their clock, ${escapeHtml(utcLabel(model.clock.offset))}</span></h3>
      ${renderHabitTable(model)}
      ${renderWithout(model)}
      <h3>Tasks</h3>
      ${renderTasks(model)}
      <h3>Settings</h3>
      ${renderSettings(model)}
      <p class="lg-legend">Worked out from what their phone saved to the account, with the phone's own rules. `
        + 'The phone does not upload what it actually armed, and whether it allows notifications at all is only known on the phone.</p>'
    + '</div>';
  const count = model.counts.habits + model.counts.tasksAhead;
  const alert = !s.masterEnabled || (!s.habitRemindersEnabled && model.counts.habits > 0) || model.stale;
  return { id: 'reminders', label: 'Reminders', count, alert, html };
}

module.exports = {
  dayLabel,
  whenText,
  utcLabel,
  renderRemindersSection,
};
