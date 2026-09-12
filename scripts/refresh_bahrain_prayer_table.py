#!/usr/bin/env python3
"""Refreshes assets/prayer/bahrain_official.json from Bahrain's official feed.

The app ships the government's own prayer timetable (BahrainPrayerTable), and
it ends on the last day the feed has published. Past that day Bahrain falls
back to the calculated times, a minute or two off, which matters most for the
alarms people set around Fajr. release.sh warns 120 days before the end and
stops 30 days before it.

    python3 scripts/refresh_bahrain_prayer_table.py            # merge and write
    python3 scripts/refresh_bahrain_prayer_table.py --check    # report only
    python3 scripts/refresh_bahrain_prayer_table.py --selftest # layout check

Days already bundled are kept and new days are added. Nothing is written if
the feed has a gap, a missing prayer or a time that is not HH:MM, or if it
changes a day the app already ships (check why, then pass --allow-changes).
Afterwards run: flutter test test/bahrain_prayer_table_test.dart
"""
import argparse
import datetime as dt
import json
import re
import sys
import urllib.request
from pathlib import Path

SOURCE = "https://static.prd.govapps.bh/config/UNIF/contents/PRAYER_TIMINGS/PRAYER_TIMINGS.json"
ASSET = Path(__file__).resolve().parent.parent / "assets" / "prayer" / "bahrain_official.json"
ORDER = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def render(doc, tail):
    """The asset's own layout: one value per line, no indentation."""
    return json.dumps(doc, indent=0, ensure_ascii=False) + tail


def feed_days(feed):
    days = {}
    for key, entry in feed["prayerTimings"].items():
        dt.date.fromisoformat(key)
        times = {t["timeOfDay"]: t["time"] for t in entry["timings"]}
        missing = [p for p in ORDER if p not in times]
        if missing:
            sys.exit(f"{key}: the feed has no {', '.join(missing)}")
        bad = [f"{p}={times[p]}" for p in ORDER if not TIME.match(times[p])]
        if bad:
            sys.exit(f"{key}: malformed time {', '.join(bad)}")
        days[key] = " ".join(times[p] for p in ORDER)
    return days


def require_continuous(keys, what):
    dates = [dt.date.fromisoformat(k) for k in sorted(keys)]
    for a, b in zip(dates, dates[1:]):
        if (b - a).days != 1:
            sys.exit(f"{what} has a gap between {a} and {b}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="report, write nothing")
    parser.add_argument("--allow-changes", action="store_true",
                        help="accept feed values that differ from bundled days")
    parser.add_argument("--selftest", action="store_true",
                        help="confirm the writer reproduces the asset byte for byte")
    args = parser.parse_args()

    raw = ASSET.read_text(encoding="utf-8")
    doc = json.loads(raw)
    tail = raw[len(raw.rstrip("\n")):]
    if args.selftest:
        same = render(doc, tail) == raw
        print("asset layout reproduces byte for byte" if same else "asset layout DIFFERS")
        sys.exit(0 if same else 1)

    with urllib.request.urlopen(SOURCE, timeout=60) as response:
        fresh = feed_days(json.load(response))
    require_continuous(fresh, "the feed")
    bundled = doc["days"]
    added = sorted(k for k in fresh if k not in bundled)
    changed = sorted(k for k in fresh if k in bundled and fresh[k] != bundled[k])

    print(f"bundled: {doc['first']} to {doc['last']} ({len(bundled)} days, fetched {doc['fetched']})")
    print(f"feed:    {min(fresh)} to {max(fresh)} ({len(fresh)} days)")
    print(f"new days: {len(added)}" + (f" ({added[0]} to {added[-1]})" if added else ""))
    for key in changed[:10]:
        print(f"changed {key}: {bundled[key]} -> {fresh[key]}")
    if changed and not args.allow_changes:
        sys.exit(f"{len(changed)} bundled day(s) differ from the feed; check why, "
                 "then rerun with --allow-changes")
    if not added and not changed:
        print("nothing to write: the bundled table already matches the feed")
        return
    if args.check:
        return

    merged = {**bundled, **fresh}
    require_continuous(merged, "the merged table")
    keys = sorted(merged)
    out = {
        "source": SOURCE,
        "authority": doc["authority"],
        "fetched": dt.date.today().isoformat(),
        "timezone": doc["timezone"],
        "order": ORDER,
        "first": keys[0],
        "last": keys[-1],
        "days": {k: merged[k] for k in keys},
    }
    ASSET.write_text(render(out, tail), encoding="utf-8")
    print(f"wrote assets/prayer/bahrain_official.json: {keys[0]} to {keys[-1]}")


if __name__ == "__main__":
    main()
