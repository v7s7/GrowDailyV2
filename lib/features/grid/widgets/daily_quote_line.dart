import 'package:flutter/material.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/daily_quotes.dart';
import '../../../core/theme/game_theme.dart';

/// The day's line, above the board.
///
/// Deliberately quiet: no card, no border, no icon competing with the squares.
/// Everything else on this screen is either a control or a score, and a line
/// that is neither should not be dressed as one. It reads as a caption over the
/// week, which is the only role it has.
///
/// Not animated on purpose. The Grid already fires a confetti burst on
/// completion and the comeback card breathes; one more moving thing on the
/// app's home screen is the point where ambient becomes busy.
class DailyQuoteLine extends StatelessWidget {
  const DailyQuoteLine({super.key});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // effectiveDay, not the raw clock: the line turns over with the app's own
    // day (6am) like the board underneath it, so someone up at 2am is not
    // handed tomorrow's quote above today's still-open squares.
    final quote = quoteForDay(DateTime.now().effectiveDay);
    final source = quote.source(s.isAr);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            quote.text(s.isAr),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: gp.textSec,
              // Italic is a Latin convention. Arabic script has no italic
              // form, so asking for one makes the engine synthesise a slant
              // that reads as a rendering fault rather than as emphasis.
              fontStyle: s.isAr ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          if (source != null) ...[
            const SizedBox(height: 4),
            Text(
              source,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: gp.textTert,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
