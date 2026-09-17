import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/profile/screens/help_support_screen.dart';

/// What the upsell copy promises, pinned against the gates behind it. Each
/// line here was false once: a free account "removed the cap" (it is
/// kFreeHabitLimit), Premium stacked "as many" reminders as you need (8 per
/// task, kMaxHabitReminders per habit), voice notes recorded "reflections"
/// (they exist on tasks only), the last trial day "ended today" when it can
/// end tomorrow, Premium was "everything Grow Daily has to offer", Android
/// read the Apple ID fine print, and the FAQ listed half the benefits.
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

  test('stacked reminders are sold as more than one, not as many as you like',
      () {
    expect(en.reminderGateBody, isNot(contains('as many')));
    expect(en.reminderGateHabitBody, isNot(contains('as many')));
  });

  test('voice notes are sold where they exist, on tasks', () {
    expect(en.premiumBenefitVoiceDesc, contains('task'));
    expect(ar.premiumBenefitVoiceDesc, contains('مهمة'));
    expect(ar.premiumBenefitVoiceDesc, isNot(contains('تأمل')));
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