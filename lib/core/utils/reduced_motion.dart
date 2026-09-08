import 'package:flutter/widgets.dart';

/// Whether this person has asked their phone to stop animating things.
///
/// [MediaQuery.disableAnimationsOf] alone is NOT enough, and that is the whole
/// reason this helper exists. Two different platform flags carry this
/// preference and Flutter surfaces them in two different places:
///
///   - `AccessibilityFeatures.disableAnimations` is fed by Android's animator
///     duration scale. MediaQuery exposes it, so it rebuilds on change.
///   - `AccessibilityFeatures.reduceMotion` is documented in dart:ui as "only
///     supported on iOS", and MediaQuery does not expose it at all.
///
/// So on iOS, the platform this app ships on first, Settings > Accessibility >
/// Motion > Reduce Motion leaves `disableAnimations` false and every check
/// written against MediaQuery alone silently does nothing.
///
/// Reduce Motion is not a preference about speed. For someone who gets motion
/// sickness or vestibular symptoms from sliding and parallax, a faster slide
/// is the same problem in less time. Callers should drop the movement
/// entirely and keep at most a cross-fade.
///
/// One honest limitation: because MediaQuery does not carry `reduceMotion`,
/// a widget reading this does NOT rebuild when the setting is toggled while
/// the app is in the foreground. That is fine for what this is used for,
/// entrance animations on screens that are built fresh each time they appear,
/// and it is why this is a function rather than something dressed up as
/// reactive state. A surface that genuinely needs to react mid-session should
/// observe `didChangeAccessibilityFeatures` itself.
bool prefersReducedMotion(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  if (mq != null && mq.disableAnimations) return true;
  return View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
}
