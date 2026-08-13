# GrowDaily — Full Project Overview

*Written to hand to any AI (or any new team member) so they understand the whole app without reading the codebase. Based on a direct audit of the GrowDaily V2 Flutter codebase, July 2026.*

## What this app is

GrowDaily is an iOS habit-tracking and personal-growth app built specifically around a Muslim user's daily life, not a generic tracker with a prayer-times feature bolted on. Its tagline, taken straight from the app's own metadata, is "a visual life progress system — color your life, one square at a time." The core idea is that a life well-lived is made of small, repeated daily actions, and the app's job is to make those actions visible, rewarding, and socially reinforced, rather than just logged in a list.

Two things make it distinct from a generic habit tracker. First, it's built culturally and religiously specific: the five daily prayers are individually-reminded catalog habits with real astronomical calculation (not a single generic "pray today" checkbox), the pre-built habit catalog is Quran/Athkar/fasting/sadaqah-centered, the character art is Gulf/Khaleeji-styled (ghutra, bisht), and the app is genuinely bilingual — English and Arabic, with real right-to-left layout, not a translated skin over an English-first app. Second, it's gamified in an RPG-lite way: completing habits earns XP and gold, XP produces levels, gold buys cosmetic gear for a customizable character, and streaks are tracked and defensible (streak freezes). The whole system is designed so that "did I live today the way I meant to" has an immediate, colorful, rewarding answer.

The app is currently iOS-only (no Android project exists yet), built in Flutter, backed by Firebase (Firestore for synced data, Firebase Auth for accounts) with Hive as a local offline-first cache, RevenueCat for the Premium subscription, and Riverpod for state management. It supports a full guest mode (try the app without an account, with limits) as well as signed-in accounts.

## The core loop

A user's habits — whether picked from the built-in Islamic catalog or created from scratch — live on a weekly grid, one row per habit, one column per day. Tapping a square cycles it through a small state machine (typically incomplete → done → a bonus/"green" state) and that action is the one thing that ripples through the rest of the app: it pays out XP and gold, it can extend or protect a streak, it can complete a Weekly Challenge or a Quick Win, it can nudge an Achievement toward unlocking, and if the habit is prayer-linked or timed, it's what a smart reminder was scheduled around in the first place. Nothing about "leveling up" in this app is abstract — it is always a direct receipt for something the user actually did that day.

Around that loop sit three supporting ideas. Reminders are smart, not just alarms: a habit can be cued off a clock time or off a real prayer time (calculated live, with an offline astronomical fallback), offset by a signed number of minutes (e.g. "15 minutes after Maghrib"), and everything respects quiet hours unless a specific habit is allowed through. Progress is social when the user wants it to be, through Rooms — group challenges with a shared code, a leaderboard, and optionally a shared habit plan. And reflection is a first-class citizen, not an afterthought: a Night Review closes each day with a mood check-in and a written reflection, and a morning Intention-setting ritual lets a user name their top priorities before the day starts.

## Navigation: the three tabs

The entire app lives inside one shell (`HomeShell`) holding a single swipeable `PageView` with one shared bottom nav bar (`GameNavBar`). There is no fourth tab, no drawer, no separate "home" screen in the main navigation — everything else in the app is reached by pushing a screen on top of one of these three tabs. In code and bar order, the three tabs are **Grid, Profile, Matrix**.

### Tab 1 — Grid (the flagship screen)

Grid is described in its own source comment as "the flagship 'color your life' experience," and it's the literal answer to the app's tagline. Rows are the user's active habits; columns are the seven days of the current week (Saturday through Friday, matching a Gulf-region week). Tapping a square cycles its color to record that day's result for that habit; a long-press opens a fuller palette plus a spot to leave a short reflection note for that specific day. Long-pressing a habit's name (rather than a square) starts multi-select, letting several habits be checked off or removed together in one action, the same interaction pattern the Matrix tab uses for tasks.

Grid deliberately carries only the habit-completion experience itself — a "Get Started" checklist and spotlight overlay walk a brand-new user through adding their first habit and task, but heavier secondary content (streak-at-risk warnings, the Night Review prompt, the Friday weekly-recap card) was deliberately relocated out to the Profile tab so Grid could "lead with the habit squares themselves" rather than being cluttered. This is where a user spends most of their daily, in-the-moment interaction with the app.

### Tab 2 — Profile (the personal hub)

Profile is not a narrow settings page; it's the hub for everything about the user's progress, identity, and configuration that isn't the moment-to-moment act of checking off a habit. Scrolling down, it holds: a hero header with the user's chosen character avatar, name, level and streak; a stats row; the secondary dashboard content moved here from Grid (streak-at-risk nudges, the Night Review prompt, the Friday recap card — rendering nothing at all on a quiet day with nothing to say); a set of link rows into the app's other major destinations; and a settings section.

The link rows are the map to the rest of the app: **Progress Hub** (a merged destination for achievements, habit insights, and streak/progress stats — with a "PRO" badge signaling that some of its content is Premium-gated), **Closet** (the character customization screen), and **Rooms** (group challenges, badge-counted by how many rooms the user is currently in). The settings section handles notification preferences (including prayer-time location and calculation method), theme (11 full color themes plus font choice, and a light/dark toggle right in the Profile app bar), language (English/Arabic), account management (edit display name, delete account), and Premium/subscription management.

### Tab 3 — Matrix (task manager)

Matrix is a genuine Eisenhower-matrix task manager — Do First, Schedule, Delegate, Eliminate — living alongside the habit tracker rather than being a separate to-do app a user would otherwise need. Tasks are one-off (not recurring like habits), each belongs to exactly one quadrant, and each can optionally carry: a one-time reminder at an absolute date/time, a free-text description, and one or more recorded voice notes (Premium-gated). Tasks support a favorite flag, drag-and-drop reordering within and across quadrants, and multi-select for bulk actions.

The screen offers three lenses — Today, Fav, and All — plus an independent "Carried Over" toggle that surfaces tasks still open from a previous day, so nothing quietly gets lost in a long backlog. A task's "day" for these lenses is its reminder date if it has one, or its creation date otherwise, which is what lets a task deliberately deferred to a future date sit quietly out of the way instead of immediately reading as stale.

## Everything reachable from those three tabs

### Rooms — group challenges

A Room is a multi-person challenge identified by a short, easy-to-read six-character code (ambiguous characters like 0/O and 1/I are excluded). A leader creates one, choosing: a competitive mode (individually-ranked leaderboard, or a "team" mode layering a shared all-or-nothing bonus on top of that same leaderboard); a habit mode (everyone tracks the same shared plan of one or more habits, cloned into each joiner's own Grid, or each participant links their own existing habit instead); and a duration (quick-pick 7/14/30/90 days, no end date, or a custom day count). Rooms start in a "lobby" state where members gather before the leader presses Start, support a scheduled future start time with a live countdown, and can be extended by the leader later. Joining and sharing happen via the room code or a `growdaily://` deep link. A live leaderboard shows each participant's percentage complete, current streak, and a mini heatmap strip of recent days; a "team" room additionally shows a combined progress bar and pays out a one-time bonus once everyone, every day, has been perfect.

### Progress Hub — achievements, insights, and streak

This screen merges three things a user might otherwise hunt across separate screens for: a 20-achievement system (5 families — such as streak length, level, total lifetime completions, mastering a single habit, and total "green squares" — each climbing Bronze → Silver → Gold → Platinum, four tiers per family, with real unlock-celebration animations); a data-driven Insights engine that analyzes each habit's scheduled-vs-completed history to surface real patterns (a user's strongest day of the week overall, and per-habit, the specific weekday they most often miss — gated behind a minimum sample size so it never reports noise as a pattern); and the underlying streak/level/XP progress numbers themselves. Some of this content is Premium-gated, signaled honestly with a small "PRO" chip rather than hidden entirely.

### Character & Closet

Every account gets a customizable avatar: six selectable characters (three male, three female), all free and available from the start — switching your look is never gold-gated. What is gold-gated is cosmetic gear: six accessory slots (misbah/tasbih, umbrella, decorative frame, badge, lantern, notebook), each purchased once with in-app gold earned from habit completions, one item equippable per slot. This is the game layer's "spend what you earned" outlet — gold has somewhere to go beyond just accumulating.

### Night Review & mood

An evening ritual: a mood check-in (Great / Good / Neutral / Sad / Exhausted, each with its own icon and color) plus a written reflection, logged per day. This is explicitly designed to let the app eventually surface trends between mood and the habits/streaks logged that same day, and has its own history/calendar screen to look back over past entries.

### Intention setting

A short ritual screen (separate from Night Review, morning-facing rather than evening-facing) where a user names up to three priorities for the day, an "anchor" and a first action — a lightweight, explicit "what am I actually trying to do today" moment that feeds into the dashboard's own state rather than existing as a disconnected journal.

### Quick Wins

Small, optional, personalized suggestions shown alongside the main habit list — deliberately distinct from a real habit: completing one doesn't color a Grid square and doesn't touch a streak. Some are inferable automatically from existing habit data (e.g. a weekly win that completes itself once a category has enough green days that week); others need a manual "mark done" tap. This is the app's low-commitment on-ramp layer, for suggestions a user isn't ready to promote to a full tracked habit yet.

### Weekly Islamic Challenges

A rotating catalog of weekly challenges themed around Islamic practice — reading Quran five times in a week, fasting both Monday and Thursday (the Sunnah fast), keeping up morning or evening athkar all seven days, and others — each with its own XP and gold reward, refreshed on a weekly cadence.

### The Islamic Habit Catalog & curated Plans

Thirty-two pre-built habit templates ship with the app across categories including Quran (a daily page, and a separate memorization track), morning and evening athkar, tahajjud (night prayer), sunnah fasting, daily sadaqah (charity), sleep schedule, six distinct marriage-preparation habits (dua, savings, gratitude, reading together, a regular check-in, and lowering the gaze), several focus/productivity habits (deep work blocks, inbox zero, daily planning, a no-phone morning, cold showers, waking early, cutting sugar), and all five daily prayers as individually-tracked entries. On top of that catalog sit seven curated bundles — Morning Warrior, Deen Essentials, Night Routine, 30-Day Discipline, Deep Focus, Marriage Preparation, and The Five Daily Prayers — so a new user can adopt a themed set of habits in one tap instead of building a routine from thirty-two individual options.

### The prayer-times engine

Real astronomical calculation, not a static table: a live fetch from the free Aladhan API first, falling back to an offline calculation (via the `adhan_dart` package) if there's no connection, both seeded with the same region-specific calculation method so the two rarely disagree. Location comes from on-device GPS or a typed city search. Six GCC countries (Bahrain, Qatar, Kuwait, UAE, Oman, Saudi Arabia) have been individually hand-verified against real published local timetables rather than just assumed from a plausible-sounding preset name — Bahrain specifically was checked against user-supplied official times and currently matches exactly with no correction needed. Around twenty more countries fall back to a documented official convention for that specific country, and anywhere else falls back to the globally-standard Muslim World League method. This is the engine every prayer-linked habit reminder is actually built on.

## Cross-cutting systems

**Notifications** are "smart" rather than fixed-clock: a habit's reminder can be tied to a real prayer moment rather than a wall-clock time, offset by a signed number of minutes either side of it, and everything respects a configurable quiet-hours window unless a specific habit is explicitly allowed through it.

**Bilingual and RTL** support is real, not cosmetic: essentially every user-facing string in the app has both an English and an Arabic form (including correct Arabic plural/cardinal-number agreement, which differs by count range), and Arabic renders with genuine right-to-left layout rather than a mirrored English layout with translated labels.

**Theming** offers eleven full color themes plus a font choice, and a light/dark mode toggle sits directly in the Profile app bar.

**Accounts** support both guest (try-before-you-sign-up, with explicit limits on history depth, habit count, and access to Rooms) and full signed-in accounts via Firebase Auth, with Firestore as the source of truth and Hive as a local offline-first cache so the app keeps working without a connection.

**Premium** is a subscription layer wrapped around RevenueCat (which itself wraps StoreKit), verified server-side rather than trusted from the client. Premium-gated content is signposted honestly in-line (a small gold "PRO" chip) rather than hidden outright, and includes things like voice notes on Matrix tasks and parts of the Progress Hub's deeper insights.

**Beyond the phone app itself**, there's an iOS home-screen widget (native Swift UI, bridged from the Dart side) and `growdaily://` deep links that can jump straight into specific actions (a Matrix quick-add, a pre-filled Join Room sheet) from outside the app.

## Where it sits competitively

Compared to the category leader among Islamic prayer/habit apps (Just Pray — 100,000+ active users, 4.9 stars), GrowDaily already covers real astronomical prayer times, a deep achievement system, genuinely bilingual real-RTL support, and Rooms (which alone covers what entire dedicated social-accountability apps like HabitFriend or Daily Pact are built around), plus a real Eisenhower task manager most habit apps don't attempt at all. What it doesn't yet have, relative to the current competitive landscape: a focus/do-not-disturb mode that blocks distracting apps during a prayer or focus window, a dedicated tap-to-count dhikr/tasbih tool, a Ramadan-specific mode (Suhoor/Iftar countdown, fasting-specific view), an AI coaching layer (several leading competitors now market this as their headline 2026 feature), Apple Health integration for auto-completing fitness habits, a fully cooperative (not just competitive) Rooms mode, a proactive weekly digest notification, user-facing data export, and Android support (the app is iOS-only today).

## Quick reference

App name: GrowDaily (internal codebase/project name "GrowDaily V2"). Bundle id: `com.growdaily.v2`. Platform: iOS only. Stack: Flutter/Dart, Firebase (Firestore, Auth, Analytics, Crashlytics), Hive (offline cache), Riverpod (state management), RevenueCat (subscriptions), Aladhan API + `adhan_dart` (prayer times), `flutter_local_notifications` (reminders). Navigation: three tabs — Grid, Profile, Matrix — in one shared `PageView`/`GameNavBar` shell, everything else reached by pushing a screen on top of one of them. Content scale: 32 built-in Islamic habit templates, 7 curated habit Plans, 20 achievements across 5 families × 4 tiers, 6 selectable characters, 6 cosmetic accessory categories, 11 color themes, full English/Arabic bilingual support with real RTL.
