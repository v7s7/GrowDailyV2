import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';

// ─── Support contact channels ──────────────────────────────────────────────
//
// Fill these in once real values exist - each row below only renders when
// its own constant is non-null, so leaving one (or all) of these null just
// quietly hides that row instead of showing a broken/fake contact option.
// No code changes needed anywhere else once these are set.

/// Plain email address, no "mailto:" prefix - e.g. 'support@growdaily.app'.
///
/// Set to the address privacy_policy.html already publishes as the contact
/// point, so the app and the policy agree. This being null shipped an app
/// with NO way to reach anyone from inside it, which App Review guideline
/// 1.2 requires for user-generated content (Rooms) and which App Store
/// Connect separately requires as a support URL.
const String? kSupportEmail = 'alkubaisi1818@gmail.com';

/// Full international phone number, digits only, no '+' or spaces -
/// e.g. '97312345678' for a Bahrain number. This is what wa.me/<number>
/// needs.
const String? kSupportWhatsApp = null;

/// Instagram handle without the leading '@' - e.g. 'growdaily.app'.
const String? kSupportInstagram = null;

// ─── Guide videos ───────────────────────────────────────────────────────────
//
// Empty for now - the whole Guides section stays hidden until at least one
// entry exists here (see HelpSupportScreen.build). Add a real video link
// later as (titleEn: ..., titleAr: ..., url: ...) and it shows up
// automatically. Named record fields (not plain positional) so a call site
// can't accidentally swap titleEn/titleAr - matches the same ({...}) shape
// main.dart/home_widget_service.dart already use for their own record
// lists.
const List<({String titleEn, String titleAr, String url})> kGuideVideos = [];

// ─── FAQ content ─────────────────────────────────────────────────────────────

/// One FAQ card - bilingual fields directly on the entry, same shape
/// IslamicHabitTemplate already uses for catalog content, rather than
/// routing question/answer text through app_strings.dart (which is for UI
/// chrome, not this kind of long-form content - see that file's own
/// comment above these strings).
/// Which part of the app a question is about.
///
/// Sixteen questions in one undivided list meant reading all sixteen titles
/// to find yours, which is the difference between "there is a FAQ" and "I
/// found my answer". The order below is the order they appear, and it is the
/// order somebody meets the app in: the board first, then what it pays, then
/// the social part, then the corners, then the account.
enum FaqGroup { basics, rewards, rooms, features, account }

class FaqEntry {
  final String questionEn;
  final String questionAr;
  final String answerEn;
  final String answerAr;
  final FaqGroup group;
  const FaqEntry({
    required this.questionEn,
    required this.questionAr,
    required this.answerEn,
    required this.answerAr,
    required this.group,
  });

  String question(bool isAr) => isAr ? questionAr : questionEn;
  String answer(bool isAr) => isAr ? answerAr : answerEn;
}

/// Answers verified against this app's actual mechanics at the time they
/// were written (streak-freeze auto-consume logic in
/// dashboard_notifier_loading.dart, the 10 AM day cutoff in
/// datetime_ext.dart, Room habit-editing in rooms_notifier.dart, guest/free
/// habit caps in custom_habits_notifier.dart, Premium's real benefit list in
/// premium_screen.dart, Night Review's screen, the bottom bar customiser in
/// nav_bar_settings_screen.dart,
/// the Journey/Life Timeline milestone log, prayer-time reminders in
/// notification_service.dart/prayer_times_service.dart, and account
/// deletion in delete_account_sheet.dart) rather than generic copy. Plain,
/// short, no dashes on purpose - reads like a person answering, not a spec.
/// If any of these mechanics change, double check these still describe them
/// accurately.
const List<FaqEntry> kFaqEntries = [
  FaqEntry(
    questionEn: 'How do I mark a habit done?',
    questionAr: 'كيف أعلّم عادة بأنها منجزة؟',
    answerEn:
        'Tap a square on the Grid to move it through empty, halfway, and done. Hold your finger on it for more options, like marking it failed or skipped, or adding a note.',
    answerAr:
        'اضغط على المربع في الجدول لينتقل بين فارغ، نصف مُنجز، ومكتمل. اضغط مطوّلاً عليه لخيارات أكثر، مثل تعليمه فاشل أو متروك، أو إضافة ملاحظة.',
    group: FaqGroup.basics,
  ),
  FaqEntry(
    questionEn: 'How does my streak work?',
    questionAr: 'كيف تعمل سلسلتي؟',
    answerEn:
        'It counts the days in a row where you finished everything on your board, not just one habit. And your day doesn\'t end at midnight. Anything you finish before 10 AM the next day still counts for the day before.',
    answerAr:
        'تحسب الأيام المتتالية التي أنجزت فيها كل ما في جدولك، وليس عادة واحدة فقط. ويومك لا ينتهي عند منتصف الليل. أي شيء تنجزه قبل الساعة 10 من صباح اليوم التالي يُحتسب لليوم السابق.',
    group: FaqGroup.basics,
  ),
  FaqEntry(
    questionEn: 'What happens if I miss a day?',
    questionAr: 'ماذا يحدث إذا فوّت يومًا؟',
    answerEn:
        'Your streak breaks, unless you have a streak freeze saved up. You start with one and earn another each week automatically. It kicks in on its own the moment you miss a day.',
    answerAr:
        'تنكسر سلسلتك، إلا إذا كان لديك تجميد سلسلة محفوظ. تبدأ بواحد وتكسب آخر كل أسبوع تلقائيًا. يعمل من تلقاء نفسه لحظة تفويتك يومًا.',
    group: FaqGroup.basics,
  ),
  FaqEntry(
    questionEn: 'Why doesn\'t my day end at midnight?',
    questionAr: 'ليش يومي ما ينتهي عند منتصف الليل؟',
    answerEn:
        'So a late night, or a late morning, doesn\'t cost you anything. Your day stays open until 10 AM the next day. Finish a habit at 2 AM or at 9 AM and it still counts for the day before instead of getting marked as missed.',
    answerAr:
        'عشان السهر، أو النوم لين متأخر، ما يكلّفك شي. يومك يظل مفتوح لين الساعة 10 من صبح اليوم التالي. لو أنجزت عادة الساعة 2 الفجر أو الساعة 9 الصبح، تنحسب لليوم السابق بدل ما تنعدّ فايتة.',
    group: FaqGroup.basics,
  ),
  FaqEntry(
    questionEn: 'What\'s the difference between XP and Gold?',
    questionAr: 'ما الفرق بين الخبرة والذهب؟',
    answerEn:
        'Both come from finishing habits and tasks. XP levels up your character. Gold is money you spend in the Shop.',
    answerAr:
        'كلاهما تكسبهما بإنجاز عاداتك ومهامك. الخبرة ترفع مستوى شخصيتك. والذهب مال تنفقه في المتجر.',
    group: FaqGroup.rewards,
  ),
  FaqEntry(
    questionEn: 'Is there a limit to how much I can earn in a day?',
    questionAr: 'في حد للي أقدر أكسبه في اليوم؟',
    answerEn:
        'Yes. XP and Gold stop adding up once a day reaches a very high total, so the app can\'t be farmed. A normal day never gets near it, and your streak, medals and squares are never capped.',
    answerAr:
        'إي. الخبرة والذهب يوقفون عند مجموع يومي عالي، عشان ما أحد يستغل التطبيق. يومك العادي ما يوصله، وسلسلتك وأوسمتك ومربعاتك ما عليها حد.',
    group: FaqGroup.rewards,
  ),
  FaqEntry(
    questionEn: 'What\'s the difference between the Shop and Level Prestige?',
    questionAr: 'ما الفرق بين المتجر ومرتبة المستوى؟',
    answerEn:
        'The Shop sells accessories for your character with Gold, and it\'s totally optional. Level Prestige is a free title next to your name that unlocks as you level up, like Seeker or Legacy. They\'re two separate things, one has nothing to do with the other.',
    answerAr:
        'المتجر يبيع إكسسوارات لشخصيتك بالذهب، وهو اختياري بالكامل. مرتبة المستوى لقب مجاني بجانب اسمك يُفتح كلما ارتفع مستواك، مثل الباحث أو الإرث. هما نظامان منفصلان تمامًا، لا علاقة لأحدهما بالآخر.',
    group: FaqGroup.rewards,
  ),
  FaqEntry(
    questionEn: 'What are Rooms?',
    questionAr: 'ما هي الغرف؟',
    answerEn:
        'A shared space to build habits with friends or family. The leader can set one plan everyone follows together, or let everyone track their own habits. Either way, you can see each other\'s progress.',
    answerAr:
        'مساحة مشتركة لبناء العادات مع الأصدقاء أو العائلة. يمكن للقائد وضع خطة واحدة يتبعها الجميع، أو ترك كل شخص يتابع عاداته الخاصة. وفي الحالتين يرى الجميع تقدّم بعضهم.',
    group: FaqGroup.rooms,
  ),
  FaqEntry(
    questionEn: 'Can the leader add a new habit to a Room later?',
    questionAr: 'هل يمكن للقائد إضافة عادة جديدة للغرفة لاحقًا؟',
    answerEn:
        'Yes, anytime. Everyone in the room gets a prompt to link one of their own habits to it.',
    answerAr:
        'نعم، في أي وقت. سيظهر لكل من في الغرفة تنبيه لربط إحدى عاداتهم بها.',
    group: FaqGroup.rooms,
  ),
  FaqEntry(
    questionEn: 'What is Night Review?',
    questionAr: 'ما هو تقييم الليل؟',
    answerEn:
        'A quick check-in at the end of your day. Pick how you felt and write a short reflection if you want. You\'ll also see what you got done. Open it anytime, and you can edit it later.',
    answerAr:
        'تسجيل سريع في نهاية يومك. اختر كيف كان شعورك واكتب تأملاً قصيرًا إن أردت. سترى أيضًا ما أنجزته. افتحه في أي وقت، ويمكنك تعديله لاحقًا.',
    group: FaqGroup.features,
  ),
  FaqEntry(
    questionEn: 'Why is my Journey or Timeline page empty?',
    questionAr: 'لماذا صفحة الرحلة أو الخط الزمني فارغة؟',
    answerEn:
        'Those pages only started recording from the day this feature launched. They can\'t pull in history from before that, even if you\'ve used Grow Daily for months. Everything from now on will show up.',
    answerAr:
        'هاتان الصفحتان بدأتا التسجيل فقط من يوم إطلاق هذه الميزة. لا يمكنهما استرجاع ما قبل ذلك، حتى لو كنت تستخدم Grow Daily منذ أشهر. كل ما يحدث من الآن سيظهر.',
    group: FaqGroup.features,
  ),
  FaqEntry(
    questionEn: 'Can I change the tabs in the bottom bar?',
    questionAr: 'أقدر أغيّر الشريط السفلي؟',
    answerEn:
        'Yes, with Premium. Go to Settings, then Bottom bar, or press and hold the bar itself. Add up to 5 tabs like Rooms, Progress or Tasbih, drag them into the order you like, or remove Tasks. Habits and Profile always stay. If Premium ends, the bar stays the way you left it, and Reset to default is always available.',
    answerAr:
        'نعم، مع بريميوم. روح للإعدادات ثم الشريط السفلي، أو اضغط مطولًا على الشريط نفسه. أضف لحد 5 تبويبات مثل الغرف أو التقدّم أو السبحة، ورتّبها مثل ما تبي، أو احذف المهام. العادات وملفي دائمًا موجودين. وإذا انتهى بريميوم، الشريط يبقى مثل ما تركته، واسترجاع الافتراضي متاح دائمًا.',
    group: FaqGroup.features,
  ),
  FaqEntry(
    questionEn: 'What\'s the difference between a guest, a free account, '
        'and Premium?',
    questionAr: 'ما الفرق بين الضيف والحساب المجاني والاشتراك المميز؟',
    answerEn:
        'As a guest you can try the app with up to 3 habits, but everything stays on this one device. A free account raises that to 10 habits and backs up your progress. Premium removes the habit limit entirely and unlocks your full history, deeper insights, extra themes, and voice notes.',
    answerAr:
        'كضيف يمكنك تجربة التطبيق بـ 3 عادات، لكن كل شيء يبقى على هذا الجهاز فقط. الحساب المجاني يرفع الحد إلى 10 عادات ويحفظ نسخة من تقدّمك. الاشتراك المميز يزيل حد العادات تمامًا ويفتح سجلّك الكامل، رؤى أعمق، سمات إضافية، وملاحظات صوتية.',
    group: FaqGroup.account,
  ),
  FaqEntry(
    questionEn: 'Why isn\'t my prayer-time reminder going off?',
    questionAr: 'لماذا لا يعمل تذكير الصلاة؟',
    answerEn:
        'Most likely your location isn\'t set. Without it, the app can\'t work out prayer times for you. Go to Notification Settings, set your location, and check the reminder is still on for that habit.',
    answerAr:
        'الأرجح أن موقعك غير محدَّد. وبدونه، لا يستطيع التطبيق حساب أوقات الصلاة لك. اذهب إلى إعدادات الإشعارات، حدّد موقعك، وتأكد أن التذكير مفعّل لتلك العادة.',
    group: FaqGroup.account,
  ),
  FaqEntry(
    questionEn: 'How do I set a reminder for a task?',
    questionAr: 'كيف أضبط تذكيرًا لمهمة؟',
    answerEn:
        'When you add a task, the reminder option is right there under the title. No extra tapping needed.',
    answerAr:
        'عند إضافة مهمة، خيار التذكير موجود مباشرة أسفل العنوان. بلا حاجة لأي ضغط إضافي.',
    group: FaqGroup.account,
  ),
  FaqEntry(
    questionEn: 'Can I delete my account?',
    questionAr: 'هل يمكنني حذف حسابي؟',
    answerEn:
        'Yes. Go to Settings and tap Delete Account. You\'ll re-enter your password to confirm. After that it\'s permanent.',
    answerAr:
        'نعم. اذهب إلى الإعدادات واضغط على حذف الحساب. ستُعيد إدخال كلمة المرور للتأكيد. وبعدها يكون نهائيًا.',
    group: FaqGroup.account,
  ),
];

/// "Help & Support" - a new, previously-nonexistent Settings destination
/// (see ProfileScreen's Settings section). Three independent sections, each
/// able to ship on its own timeline: FAQ has real content today; Contact
/// and Guides are built to switch on the moment kSupportEmail/kSupportWhatsApp/
/// kSupportInstagram/kGuideVideos above actually have values, without
/// showing a half-finished "coming soon" placeholder to real users in the
/// meantime.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final hasContact =
        kSupportEmail != null || kSupportWhatsApp != null || kSupportInstagram != null;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.helpSupportRowTitle,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(s.helpFaqSectionTitle,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          _FaqList(isAr: isAr),
          if (hasContact) ...[
            const SizedBox(height: 24),
            Text(s.helpContactSectionTitle,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                    letterSpacing: 1.5)),
            const SizedBox(height: 12),
            _ContactCard(),
          ],
          if (kGuideVideos.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(s.helpGuidesSectionTitle,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                    letterSpacing: 1.5)),
            const SizedBox(height: 12),
            _GuidesCard(isAr: isAr),
          ],
        ],
      ),
    );
  }
}

// ─── FAQ accordion ──────────────────────────────────────────────────────────

class _FaqList extends StatefulWidget {
  final bool isAr;
  const _FaqList({required this.isAr});

  @override
  State<_FaqList> createState() => _FaqListState();
}

class _FaqListState extends State<_FaqList> {
  // Only one open at a time - same shape PlanPickerSheet's _expandedPlanId
  // already uses for the same reason: reading one answer at a time is the
  // point, not accumulating a wall of open text.
  //
  // Keyed on the question rather than an index now that the list is split
  // into cards: an index is only unique within its own card, so two answers
  // in two groups would have opened together.
  String? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // One card per group, each under its own quiet heading. Groups with no
    // questions in them simply do not appear, so adding or moving an entry
    // above needs nothing here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in FaqGroup.values)
          if (kFaqEntries.where((e) => e.group == group).isNotEmpty) ...[
            if (group != FaqGroup.values.first) const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 2, left: 2),
              child: Text(
                s.faqGroupTitle(group.name),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                ),
              ),
            ),
            _groupCard(kFaqEntries.where((e) => e.group == group).toList()),
          ],
      ],
    );
  }

  Widget _groupCard(List<FaqEntry> entries) {
    final gp = context.gp;
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i != 0) Container(height: 0.5, color: gp.divider),
            _FaqRow(
              entry: entries[i],
              isAr: widget.isAr,
              isExpanded: _expandedIndex == entries[i].questionEn,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expandedIndex =
                    _expandedIndex == entries[i].questionEn
                        ? null
                        : entries[i].questionEn);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  final FaqEntry entry;
  final bool isAr;
  final bool isExpanded;
  final VoidCallback onTap;
  const _FaqRow({
    required this.entry,
    required this.isAr,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.question(isAr),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: gp.textPrimary,
                        height: 1.3),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: GameMotion.standard,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: gp.textTert),
                ),
              ],
            ),
            AnimatedSize(
              duration: GameMotion.standard,
              curve: Curves.easeOutCubic,
              child: isExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        entry.answer(isAr),
                        style: TextStyle(
                            fontSize: 13, color: gp.textSec, height: 1.5),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Contact ────────────────────────────────────────────────────────────────

/// The support address with a subject and the device already written into it.
///
/// A bare `mailto:` opened a blank message, so every conversation started
/// with the same two questions back: which phone, and which version. The
/// person writing in has no idea, and asking them costs a round trip before
/// anyone has even read the problem.
///
/// What is here needs no plugin: dart:io knows the platform and the OS
/// build, and the sheet knows the language. The APP's own version is the one
/// field still missing, and it is the most useful of the lot — it needs
/// package_info_plus, which is a dependency decision rather than a code one.
///
/// The body is left in the person's own language and ends with a blank line
/// under a divider, so what they type lands above the technical part instead
/// of after it.
///
/// [appVersion] is null only in the moment before package_info answers, which
/// is a frame or two after the screen opens. The line is dropped rather than
/// filled with "unknown": a support mail that says the version is unknown is
/// no better than one that does not mention it, and worse to read.
String supportMailto(S s, {String? appVersion}) {
  final device = [
    'App: Grow Daily${appVersion == null ? '' : ' $appVersion'}',
    'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'Language: ${s.isAr ? 'ar' : 'en'}',
  ].join('\n');
  final body = '${s.helpEmailBodyLead}\n\n\n--\n$device';
  return Uri(
    scheme: 'mailto',
    path: kSupportEmail,
    query: Uri.encodeFull('subject=${s.helpEmailSubject}&body=$body')
        .replaceAll('#', '%23'),
  ).toString();
}

/// Loads the app's version once and hands it to the mailto.
///
/// Stateful only for that: package_info is a platform channel, so it cannot
/// be read while building. A failure leaves the version out and the rest of
/// the mail intact, because not knowing the build is a far smaller problem
/// than a support screen that throws.
class _ContactCard extends StatefulWidget {
  @override
  State<_ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends State<_ContactCard> {
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {
      // Leave it null; see supportMailto.
    }
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final rows = [
      if (kSupportEmail != null)
        (
          icon: Icons.email_outlined,
          label: s.helpContactEmailLabel,
          url: supportMailto(s, appVersion: _appVersion),
        ),
      if (kSupportWhatsApp != null)
        (
          icon: Icons.chat_outlined,
          label: s.helpContactWhatsAppLabel,
          url: 'https://wa.me/$kSupportWhatsApp',
        ),
      if (kSupportInstagram != null)
        (
          icon: Icons.camera_alt_outlined,
          label: s.helpContactInstagramLabel,
          url: 'https://instagram.com/$kSupportInstagram',
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0) Container(height: 0.5, color: gp.divider),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                _openLink(context, rows[i].url);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(rows[i].icon, size: 20, color: gp.textSec),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(rows[i].label,
                          style: TextStyle(
                              fontSize: 15,
                              color: gp.textPrimary,
                              fontWeight: FontWeight.w500)),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: gp.textTert),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Guides (video) ─────────────────────────────────────────────────────────

class _GuidesCard extends StatelessWidget {
  final bool isAr;
  const _GuidesCard({required this.isAr});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < kGuideVideos.length; i++) ...[
            if (i != 0) Container(height: 0.5, color: gp.divider),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                _openLink(context, kGuideVideos[i].url);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.play_circle_outline_rounded,
                        size: 20, color: gp.textSec),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          isAr
                              ? kGuideVideos[i].titleAr
                              : kGuideVideos[i].titleEn,
                          style: TextStyle(
                              fontSize: 15,
                              color: gp.textPrimary,
                              fontWeight: FontWeight.w500)),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: gp.textTert),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared link opener ─────────────────────────────────────────────────────

/// Same "open externally, fall back to a snackbar on failure" behavior as
/// PremiumScreen._openLink - kept as its own small copy here rather than
/// shared, matching this codebase's own stated preference for small
/// per-file duplication over cross-file sharing of similar-but-distinct
/// pieces, and specifically so a monetization-critical screen like
/// PremiumScreen never has to change just because this one does.
Future<void> _openLink(BuildContext context, String url) async {
  bool ok;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context).showOne(
    SnackBar(
      content: Text(S.of(context).premiumLinkOpenError),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );
}
