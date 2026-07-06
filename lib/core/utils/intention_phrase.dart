/// Cue phrases that already carry their own preposition — e.g. "Before
/// sleep" — must not be prefixed with "After" again, or the sentence reads
/// as nonsense: "After Before sleep, I will ...". This lets every
/// "implementation intention" sentence in the app (stored habit
/// descriptions, the live add-habit preview) stay grammatical regardless of
/// which routine anchor the user picks from the chips or types themselves.
bool cueHasOwnPreposition(String cue) {
  final lower = cue.trim().toLowerCase();
  const prepositions = ['before', 'after', 'during', 'when', 'once', 'while'];
  return prepositions.any((p) => lower.startsWith('$p '));
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
