*Draft — reviewed against the app's actual code, not a template. Have a
lawyer (or at least a careful re-read) confirm it before you publish it or
submit to the App Store / Play Store. Fill in the bracketed placeholders
before publishing.*

# Privacy Policy for GrowDaily

**Last updated:** [DATE]

GrowDaily ("the app," "we," "us") is a personal habit-tracking app. This
policy explains what data the app collects, how it's used, and what choices
you have.

## Summary

- You can use GrowDaily as a Guest with no account at all — in that mode,
  your data stays only on your device and is never sent to us.
- If you create an account, we store your habit data so it syncs across
  your devices and survives a reinstall. We do not sell your data, and we
  do not show ads or share your data with advertisers.
- There is currently no analytics or tracking SDK in the app beyond what's
  described below.

## Information we collect

**Account information.** If you register, we collect the email address and
password you provide. Your password is handled entirely by Firebase
Authentication (operated by Google) — GrowDaily never sees or stores your
password itself.

**Habit and progress data.** Once you have an account, the following is
stored in our database (Cloud Firestore, operated by Google) tied to your
account:
- The habits you create or activate, and your daily completions
- Streaks, XP, levels, in-app currency ("gold"), and unlocked achievements
- Content you write inside the app: daily intentions, priorities, and
  night-review reflections
- Focus timer sessions, Eisenhower Matrix tasks, and weekly challenge
  progress
- Your subscription status (whether GrowDaily Premium is active)

**Guest mode data.** If you use the app without creating an account, all of
the above is stored only in local storage on your device and is never
transmitted to us. It stays there until you delete the app or clear its
data.

**What we don't collect.** GrowDaily does not access your contacts,
photos, camera, microphone, or precise location. We do not use advertising
SDKs, and as of this writing the app has no third-party analytics service
integrated — in-app event logging exists in the code but currently only
writes to the local debug console and is not transmitted anywhere.
[Update this section if/when an analytics or crash-reporting SDK is added.]

## How we use your information

- To sync your habits, streaks, and progress across your devices
- To let you sign back in and recover your data after reinstalling
- To operate GrowDaily Premium (identifying whether your account has an
  active subscription)
- To send you the daily reminder notification you configure — this is
  scheduled locally on your device and does not require sending your data
  to us

## Who we share it with

We share data with the infrastructure providers that run the app, and
nobody else:
- **Google Firebase** (Authentication, Cloud Firestore) — our backend
  provider. See Google's own privacy policy for how they handle
  infrastructure-level data: https://policies.google.com/privacy
- [If you add RevenueCat, Apple/Google in-app purchase processing, or any
  analytics/crash-reporting tool later, list each one here along with what
  it receives.]

We do not sell your personal data, and we do not share it with advertisers.

## Your choices

- **Guest mode** — use the app without an account; nothing leaves your
  device.
- **Notifications** — the daily reminder is entirely optional and can be
  turned off at any time from Profile settings.
- **Account deletion** — [Placeholder: at the time of writing, in-app
  self-service account deletion is not yet implemented. Until it is, email
  [SUPPORT EMAIL] to request deletion of your account and associated data.
  Note: Apple's App Store guidelines require apps that support account
  creation to also support account deletion from within the app before
  submission — this needs to be built, not just documented, before you
  submit to the App Store.]

## Children's privacy

GrowDaily is not directed at children under 13 (or the relevant age of
digital consent in your country), and we do not knowingly collect
information from children. If you believe a child has provided us with
personal information, contact us at [SUPPORT EMAIL] and we will delete it.

## Data retention

We retain your account data for as long as your account exists. If you
delete your account, your data is deleted from our systems [within X days],
except where retention is required by law.

## Security

We rely on Firebase Authentication and Firestore security rules to ensure
only you can read or write your own data. No method of transmission or
storage is 100% secure, and we can't guarantee absolute security.

## Changes to this policy

We may update this policy as the app changes. We'll update the "Last
updated" date above when we do. Material changes will be noted in the app
or on this page.

## Contact us

Questions about this policy or your data: [SUPPORT EMAIL]

---

*Placeholders still to fill in: [DATE], [SUPPORT EMAIL], data-deletion
timeframe, and the account-deletion flow itself. This document also needs a
permanent public URL (e.g. hosted on Firebase Hosting or GitHub Pages)
before you can enter it in App Store Connect / Play Console.*
