import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';
import '../../shared/widgets/segmented_tabs.dart';

/// A throwaway side-by-side of the three ways this app could draw a toggle.
///
/// The question is NOT "Flutter or native". It is which of three things the
/// premium feel actually comes from:
///   1. Material Switch  - what the app ships in all four places today
///   2. CupertinoSwitch  - Flutter's own iOS switch, free, no dependency
///   3. CNSwitch         - a real UIKit switch in a platform view
///
/// If 2 is indistinguishable from 3 then the gap Aziz is reacting to is
/// Material-versus-Apple, not Flutter-versus-native, and the dependency
/// buys nothing. Delete this file once the answer is recorded.
class ControlBakeoffScreen extends StatefulWidget {
  const ControlBakeoffScreen({super.key});

  @override
  State<ControlBakeoffScreen> createState() => _ControlBakeoffScreenState();
}

class _ControlBakeoffScreenState extends State<ControlBakeoffScreen> {
  bool _a = true;
  bool _b = true;
  bool _c = true;
  int _segMine = 0;
  int _segNative = 0;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: gp.bg,
        body: SafeArea(
          // A ListView on purpose: the package warns that its glass views
          // jank inside long scrolling lists, and this app's main screen IS
          // a long scrolling list.
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _row(context, 'Material Switch (today)',
                  Switch(value: _a, onChanged: (v) => setState(() => _a = v))),
              _row(
                context,
                'CupertinoSwitch (free)',
                CupertinoSwitch(
                  value: _b,
                  activeTrackColor: GameColors.emerald,
                  onChanged: (v) => setState(() => _b = v),
                ),
              ),
              _row(
                context,
                'CNSwitch (real UIKit)',
                SizedBox(
                  width: 52,
                  height: 32,
                  child: CNSwitch(
                    value: _c,
                    color: GameColors.emerald,
                    onChanged: (v) => setState(() => _c = v),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('segmented', style: TextStyle(color: gp.textTert)),
              const SizedBox(height: 8),
              SegmentedTabs(
                labels: const ['كل الأيام', 'آخر 7 أيام'],
                selected: _segMine,
                onChanged: (i) => setState(() => _segMine = i),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                child: CNSegmentedControl(
                  labels: const ['كل الأيام', 'آخر 7 أيام'],
                  selectedIndex: _segNative,
                  color: GameColors.emerald,
                  onValueChanged: (i) => setState(() => _segNative = i),
                ),
              ),
              const SizedBox(height: 24),
              Text('buttons', style: TextStyle(color: gp.textTert)),
              const SizedBox(height: 8),
              CNButton(
                label: 'أضف عادة',
                config: const CNButtonConfig(style: CNButtonStyle.filled),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, Widget control) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
          ),
          control,
        ],
      ),
    );
  }
}
