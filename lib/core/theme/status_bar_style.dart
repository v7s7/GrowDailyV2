import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The status bar's clock and battery drawn dark, for a light screen.
///
/// Status bar fields only: the navigation bar is left to the platform. The
/// ready-made [SystemUiOverlayStyle.dark] also paints Android's navigation
/// bar black, which the launch curtain did under its cream until 2026-09-30.
const kStatusIconsDark = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.light,
  statusBarIconBrightness: Brightness.dark,
);

/// The status bar's clock and battery drawn light, for a dark screen. Status
/// bar fields only, as [kStatusIconsDark].
const kStatusIconsLight = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.dark,
  statusBarIconBrightness: Brightness.light,
);

/// The icons that read on a screen of [background]'s brightness.
///
/// The app's own default, wrapped around every page in MaterialApp.builder
/// (main.dart): a page with an AppBar still sets its own, since the deeper
/// region wins. Without it, a page with no AppBar (the Grid, Tasks) kept
/// whatever was set last. After the launch curtain lifted that was the
/// curtain's: dark icons on the dark Grid, white ones on the cream Grid
/// after a night open. Seen on the simulator 2026-09-29.
SystemUiOverlayStyle statusIconsOver(Brightness background) =>
    background == Brightness.dark ? kStatusIconsLight : kStatusIconsDark;
