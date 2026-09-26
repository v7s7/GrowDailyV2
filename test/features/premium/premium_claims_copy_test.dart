import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/voice_note_allowance.dart';
import 'package:grow_daily_v2/features/profile/screens/help_support_screen.dart';

/// What the upsell copy promises, pinned against the gates behind it. Each
/// line here was false once: a free account "removed the cap" (it is
/// kFreeHabitLimit), Premium stacked "as many" reminders as you need (8 per
/// task, kMaxHabitReminders per habit), voice notes recorded "reflections"
/// (they exist on tasks only), the last trial day "ended today" when it can
/// end tomorrow, Premium was "everything Grow Daily has to offer", Android
/// read the Apple ID fine print, the FAQ listed half the benefits, and the
/// reminders row sold tasks only while the habit gate opened on it.
void main() {
  const en = S(Locale('en'));
  const ar = S(Locale('ar'));

  test('the guest limit sheet names the free cap, not unlimited habits', () {
    expect(en.guestLimitBody, contains('$kFreeHabitLimit'));
    expect(ar.guestLimitBody, contains('$kFreeHabitLimit'));
    expect(en.guestLimitBody, isNot(contains('removes the cap')));
    expect(ar.guestLimitBody, isNot(contains('غير محدود')));
    // «التجربة» names the legacy Premium trial line (premiumTrialLine), not
    // the guest cap.
    expect(ar.guestLimitTitle, isNot(contains('التجربة')));
  });

  // The guest cap is written out as a digit in three places, none of which
  // reads the constant, so raising it from 3 to 5 meant finding all three by
  // hand. Pinned as "<n> habits" / "<n> عادات" rather than the bare digit, so
  // a 5 elsewhere in a sentence cannot pass for it.
  test('every sentence that states the guest cap states kGuestHabitLimit', () {
    final faq = kFaqEntries
        .firstWhere((e) => e.questionEn.contains('a guest, a free account'));
    for (final line in [en.authGuestFact, en.guestLimitBody, faq.answerEn]) {
      expect(line, contains('$kGuestHabitLimit habits'), reason: line);
    }
    for (final line in [ar.authGuestFact, ar.guestLimitBody, faq.answerAr]) {
      expect(line, contains('$kGuestHabitLimit عادات'), reason: line);
    }
  });

  test('stacked reminders are sold as more than one, not as many as you like',
      () {
    expect(en.reminderGateBody, isNot(contains('as many')));
    expect(en.reminderGateHabitBody, isNot(contains('as many')));
    expect(en.premiumBenefitTaskRemindersDesc, isNot(contains('as many')));
  });

  // The habit reminder gate opens the paywall with this row on top
  // (PremiumReason.tasks), so a row about tasks alone answered someone who
  // had just tried a second Maghrib reminder with a line about something
  // else, and a habit's stack was sold on no line at all.
  test('the reminders row sells habits as well as tasks', () {
    expect(en.premiumBenefitTaskRemindersDesc, contains('habit'));
    expect(en.premiumBenefitTaskRemindersDesc, contains('task'));
    // The bare nouns, not «العادة» / «المهمة»: a preposition fuses with the
    // article («للعادة», «للمهمة») and drops its alif, so the article form is
    // not a substring of the most natural way to write either.
    expect(ar.premiumBenefitTaskRemindersDesc, contains('عادة'));
    expect(ar.premiumBenefitTaskRemindersDesc, contains('مهمة'));
    expect(en.premiumBenefitTaskRemindersTitle, isNot(contains('task')));
    expect(ar.premiumBenefitTaskRemindersTitle, isNot(contains('مهمة')));
  });

  // Tasks, and since 2026-09-25 a habit's day (square_voice_notes.dart);
  // still never "reflections", which no build ever had.
  test('voice notes are sold where they exist, on tasks and habit days', () {
    for (final line in [en.premiumBenefitVoiceDesc, en.voiceNoteGateBody]) {
      expect(line, contains('task'), reason: line);
      expect(line, contains('habit'), reason: line);
    }
    for (final line in [ar.premiumBenefitVoiceDesc, ar.voiceNoteGateBody]) {
      expect(line, contains('مهمة'), reason: line);
      expect(line, contains('عادات'), reason: line);
      expect(line, isNot(contains('تأمل')), reason: line);
    }
    final faq = kFaqEntries
        .firstWhere((e) => e.questionEn.contains('a guest, a free account'));
    expect(faq.answerEn, contains('voice notes on tasks and habit days'));
    expect(faq.answerAr, contains('ملاحظات صوتية للمهام وأيام العادات'));
  });

  // The monthly allowance (voice_note_allowance.dart) is stated where Premium
  // is explained, so a paying account never meets it as a surprise. Written
  // out as a digit, like the guest cap above, and pinned to the constant.
  test('the FAQ states the monthly voice note allowance', () {
    final faq = kFaqEntries
        .firstWhere((e) => e.questionEn.contains('a guest, a free account'));
    expect(faq.answerEn, contains('up to $kVoiceNotesPerMonth a month'));
    expect(faq.answerAr, contains('لحد $kVoiceNotesPerMonth في الشهر'));
  });

  test('the last trial day makes no calendar claim', () {
    // trialDaysLeft is 1 for the final 24 hours, which often cross midnight.
    expect(en.premiumTrialLine(1), isNot(contains('today')));
    expect(ar.premiumTrialLine(1), isNot(contains('اليوم')));
  });

  test('Premium is not sold as everything the app has', () {
    expect(en.premiumSubhead, isNot(contains('Everything Grow Daily')));
    expect(ar.premiumSubhead, isNot(contains('كل ما يقدّمه')));
  });

  test('the Play fine print never names Apple', () {
    for (final s in [en, ar]) {
      expect(s.premiumFinePrintMonthlyPlay, contains('Google Play'));
      expect(s.premiumFinePrintMonthlyPlay, isNot(contains('Apple')));
    }
  });

  test('the Premium FAQ answer matches the tiers and the benefit list', () {
    final entry = kFaqEntries
        .firstWhere((e) => e.questionEn.contains('a guest, a free account'));
    expect(entry.questionAr, isNot(contains('الاشتراك المميز')));
    for (final answer in [entry.answerEn, entry.answerAr]) {
      expect(answer, contains('$kFreeHabitLimit'));
      expect(answer, contains('9'));
    }
    expect(entry.answerEn, contains('bottom bar'));
    expect(entry.answerAr, contains('شريط سفلي'));
  });

  test('the bottom bar FAQ counts the pinned tabs inside the 5', () {
    final entry = kFaqEntries
        .firstWhere((e) => e.questionEn.contains('tabs in the bottom bar'));
    expect(entry.answerEn, isNot(contains('Add up to')));
    expect(entry.answerAr, isNot(contains('أضف لحد')));
  });

  test('FAQ text uses no em dash and no Arabic-Indic digits', () {
    for (final e in kFaqEntries) {
      for (final text in [e.questionEn, e.questionAr, e.answerEn, e.answerAr]) {
        // U+2014 and U+0660 to U+0669, escaped so this file holds neither.
        expect(text.contains('\u2014'), isFalse, reason: text);
        expect(
          RegExp('[\u0660-\u0669]').hasMatch(text),
          isFalse,
          reason: text,
        );
      }
    }
  });
}