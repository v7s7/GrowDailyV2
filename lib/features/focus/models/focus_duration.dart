/// The three sprint lengths offered on the Focus screen, plus the XP each
/// one pays out on completion. Lives in its own file (rather than nested in
/// focus_screen.dart, where it originally was) so both the screen and
/// [FocusTimerNotifier] can depend on it without a screen-to-notifier import.
enum FocusDuration {
  short(25, 30),
  medium(50, 60),
  long(90, 100);

  const FocusDuration(this.minutes, this.xpReward);
  final int minutes;
  final int xpReward;
  int get seconds => minutes * 60;
}
