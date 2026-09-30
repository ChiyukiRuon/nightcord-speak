// The 4px grid, from `docs/UI设计与配色规范.md` §13.
//
// Every gap, inset and gap between sections is one of these ten numbers. The
// point is not the numbers themselves but that a reviewer can tell a deliberate
// 12 from an accidental 13: before this file the app used 2, 3, 4, 6, 8, 10, 12,
// 14, 16, 18, 20, 24 and 32 interchangeably, and nothing distinguished a choice
// from a typo.

/// Distances, on the 4px grid.
abstract final class AppSpacing {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 32;
  static const double space8 = 40;
  static const double space9 = 48;
  static const double space10 = 64;
}
