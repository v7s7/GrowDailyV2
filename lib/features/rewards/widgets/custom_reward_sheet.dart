import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/custom_reward.dart';
import '../notifiers/custom_rewards_notifier.dart';

/// Add or edit one reward. Writes nothing until Save, so backing out with
/// the system gesture leaves the record untouched.
///
/// [existing] null means add. [prefillName] and [prefillPrice] are set when a
/// starter chip opened this, which is the whole point of the starter row: it
/// hands a first-time user a name and a price to react to rather than a
/// blank field to invent from.
Future<void> showCustomRewardSheet(
  BuildContext context,
  WidgetRef ref, {
  CustomReward? existing,
  String? prefillName,
  int? prefillPrice,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Without this the footer button renders under the home indicator.
    useSafeArea: true,
    builder: (_) => _CustomRewardSheet(
      existing: existing,
      prefillName: prefillName,
      prefillPrice: prefillPrice,
    ),
  );
}

class _CustomRewardSheet extends ConsumerStatefulWidget {
  final CustomReward? existing;
  final String? prefillName;
  final int? prefillPrice;

  const _CustomRewardSheet({
    this.existing,
    this.prefillName,
    this.prefillPrice,
  });

  @override
  ConsumerState<_CustomRewardSheet> createState() => _CustomRewardSheetState();
}

class _CustomRewardSheetState extends ConsumerState<_CustomRewardSheet> {
  late final TextEditingController _name;
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.existing?.name ?? widget.prefillName ?? '',
    );
    // Never blank. The empty price field is the one question a first-time
    // user has no basis to answer, and it is where this feature dies.
    _price = TextEditingController(
      text: (widget.existing?.priceGold ??
              widget.prefillPrice ??
              priceForDays(kSuggestedPriceDays.toDouble()))
          .toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  /// Deliberately no `inputFormatters`. FilteringTextInputFormatter.digitsOnly
  /// strips Arabic-Indic digits, and an Arabic keypad commonly defaults to
  /// ٠-٩, which would lock a user out of the one field this design rests on.
  /// The shared helper already exists precisely because three call sites had
  /// each grown their own copy of this loop.
  int? get _parsedPrice {
    final n = int.tryParse(toWesternDigits(_price.text.trim()));
    if (n == null || n < kCustomRewardMinPrice || n > kCustomRewardMaxPrice) {
      return null;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final rewards = ref.watch(customRewardsProvider);
    final editing = widget.existing != null;
    final price = _parsedPrice;
    final canSave =
        _name.text.trim().isNotEmpty && price != null && !rewards.loadFailed;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: GameColors.iconGold.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.card_giftcard_rounded,
                size: 26,
                color: GameColors.iconGold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              editing ? s.rewardsEditTitle : s.rewardsAdd,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.rewardsSheetBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: gp.textSec,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: _name.text.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              maxLength: kCustomRewardNameMaxChars,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.rewardsNameHint,
                counterText: '',
                filled: true,
                fillColor: gp.surface,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  borderSide: BorderSide(color: gp.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  borderSide: BorderSide(color: gp.border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                s.rewardsPriceLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                  // Wide letter-spacing is a Latin trick that breaks
                  // Arabic's joined script.
                  letterSpacing: s.isAr ? 0 : 1.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              maxLength: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: gp.surface,
                errorText: _price.text.trim().isEmpty || price != null
                    ? null
                    : s.rewardsPriceInvalid(
                        kCustomRewardMinPrice,
                        kCustomRewardMaxPrice,
                      ),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  borderSide: BorderSide(color: gp.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  borderSide: BorderSide(color: gp.border),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // The whole pricing intervention: it turns "420" into a claim
            // about time, which is the only unit anyone has an opinion
            // about, at the moment the price is being set.
            SizedBox(
              height: 18,
              child: Text(
                price == null ? '' : s.rewardsEffort(daysForPrice(price)),
                style: TextStyle(fontSize: 12, color: gp.textSec),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: canSave
                  ? () {
                      final n = ref.read(customRewardsProvider.notifier);
                      if (editing) {
                        n.update(
                          widget.existing!.id,
                          name: _name.text,
                          priceGold: price,
                        );
                      } else {
                        n.add(name: _name.text, priceGold: price);
                      }
                      Navigator.pop(context);
                    }
                  : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(s.rewardsSave),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.rewardsCancel),
            ),
            if (editing)
              TextButton(
                onPressed: rewards.loadFailed ? null : _confirmDelete,
                style: TextButton.styleFrom(
                  foregroundColor: GameColors.error,
                ),
                child: Text(s.rewardsDelete),
              ),
          ],
        ),
      ),
    );
  }

  /// Confirm, remove, then offer it straight back.
  ///
  /// The messenger is captured BEFORE the sheet pops: afterwards this
  /// widget's context is defunct and ScaffoldMessenger.of would throw. The
  /// undo hands back the exact record rather than re-creating one, so the id
  /// survives and a stale bar tapped twice cannot duplicate the row.
  Future<void> _confirmDelete() async {
    final s = S.of(context);
    final reward = widget.existing!;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(customRewardsProvider.notifier);

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.rewardsDeleteTitle),
        content: Text(s.rewardsDeleteBody(reward.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.rewardsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: GameColors.error,
            ),
            child: Text(s.rewardsDeleteConfirm),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    notifier.remove(reward.id);
    Navigator.pop(context);
    messenger.showOne(
      SnackBar(
        content: Text(s.rewardsDeleted(reward.name)),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: s.undo,
          onPressed: () => notifier.restore(reward),
        ),
      ),
    );
  }
}
