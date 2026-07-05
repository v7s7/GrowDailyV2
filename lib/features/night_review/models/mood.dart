/// A single evening emotional check-in. Tracked per day so the app can
/// surface trends between mood and the habits/streaks logged that same day.
enum Mood {
  great,
  good,
  neutral,
  sad,
  exhausted;

  String toJson() => name;

  static Mood? fromJsonOrNull(String? v) {
    if (v == null) return null;
    for (final m in values) {
      if (m.name == v) return m;
    }
    return null;
  }

  String get emoji => switch (this) {
        great => '😀',
        good => '🙂',
        neutral => '😐',
        sad => '😔',
        exhausted => '😢',
      };

  String label(bool isAr) => switch (this) {
        great => isAr ? 'رائع' : 'Great',
        good => isAr ? 'جيد' : 'Good',
        neutral => isAr ? 'عادي' : 'Neutral',
        sad => isAr ? 'حزين' : 'Sad',
        exhausted => isAr ? 'منهك' : 'Exhausted',
      };
}
