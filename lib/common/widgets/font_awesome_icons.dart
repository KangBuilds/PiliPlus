import 'package:flutter/widgets.dart' show IconData;

/// The Font Awesome Free icons the app uses, from the fonts in assets/fonts.
///
/// Font Awesome by Fonticons, Inc. (https://fontawesome.com), licensed under
/// https://fontawesome.com/license/free (Icons: CC BY 4.0, Fonts: SIL OFL 1.1).
///
/// These replace package:font_awesome_flutter, which also shipped its brands
/// font whole: Flutter trims an icon font to the icons in use only when at
/// least one of them is.
// dart format off
abstract final class FontAwesomeIcons {
  static const _kRegular = 'FontAwesomeRegular';
  static const _kSolid = 'FontAwesomeSolid';

  static const IconData arrowLeft = IconData(0xf060, fontFamily: _kSolid);
  static const IconData b = IconData(0x42, fontFamily: _kSolid);
  static const IconData circleDown = IconData(0xf358, fontFamily: _kRegular);
  static const IconData circlePlay = IconData(0xf144, fontFamily: _kRegular);
  static const IconData clock = IconData(0xf017, fontFamily: _kRegular);
  static const IconData comment = IconData(0xf075, fontFamily: _kRegular);
  static const IconData ghost = IconData(0xf6e2, fontFamily: _kSolid);
  static const IconData house = IconData(0xf015, fontFamily: _kSolid);
  static const IconData lock = IconData(0xf023, fontFamily: _kSolid);
  static const IconData lockOpen = IconData(0xf3c1, fontFamily: _kSolid);
  static const IconData shareFromSquare = IconData(0xf14d, fontFamily: _kRegular);
  static const IconData solidClock = IconData(0xf017, fontFamily: _kSolid);
  static const IconData solidStar = IconData(0xf005, fontFamily: _kSolid);
  static const IconData solidThumbsDown = IconData(0xf165, fontFamily: _kSolid);
  static const IconData solidThumbsUp = IconData(0xf164, fontFamily: _kSolid);
  static const IconData star = IconData(0xf005, fontFamily: _kRegular);
  static const IconData thumbsDown = IconData(0xf165, fontFamily: _kRegular);
  static const IconData thumbsUp = IconData(0xf164, fontFamily: _kRegular);
}
// dart format on
