/// Cue phrases that already carry their own preposition — e.g. "Before
/// sleep" — must not be prefixed with "After" again, or the sentence reads
/// as nonsense: "After Before sleep, I will ...". This lets every
/// "implementation intention" sentence in the app (stored habit
/// descriptions, the live add-habit preview) stay grammatical regardless of
/// which routine anchor the user picks from the chips or types themselves.
bool cueHasOwnPreposition(String cue) {
  final trimmed = cue.trim();
  final lower = trimmed.toLowerCase();
  const englishPrepositions = ['before', 'after', 'during', 'when', 'once', 'while'];
  if (englishPrepositions.any((p) => lower.startsWith('$p '))) return true;
  // Arabic has no case to lowercase, so this checks the trimmed original —
  // needed now that the routine-cue chips emit Arabic text ("قبل النوم")
  // directly, or "بعد قبل النوم" (After before sleep) would slip through.
  const arabicPrepositions = ['قبل', 'بعد', 'أثناء', 'خلال', 'عند', 'وقت'];
  return arabicPrepositions.any((p) => trimmed.startsWith('$p '));
}

String capitalizeFirst(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// "After Fajr, I will pray." / "Before sleep, I will pray." — the plain
/// English sentence stored as a custom habit's description.
String buildIntentionSentence(String cue, String habitName) {
  final trimmedCue = cue.trim();
  if (trimmedCue.isEmpty) return '';
  final clause = cueHasOwnPreposition(trimmedCue)
      ? capitalizeFirst(trimmedCue)
      : 'After $trimmedCue';
  return '$clause, I will $habitName.';
}
