import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';

// Phosphor Icons, bold weight (DESIGN.md §4): the same SVGs as the web, bundled so they work offline.
// App names stay stable and match the web AppIcon; only the glyphs behind them change.
enum AppIconName {
  addLocation('map-pin-plus-bold', 'map-pin-plus-fill'),
  aed('heartbeat-bold'),
  call('phone-bold'),
  checkCircle('check-circle-bold'),
  chevronLeft('caret-left-bold'),
  chevronRight('caret-right-bold'),
  close('x-bold'),
  directionsWalk('person-simple-walk-bold'),
  doorFront('door-open-bold'),
  error('warning-circle-bold'),
  expandMore('caret-down-bold'),
  filterList('funnel-simple-bold', 'funnel-simple-fill'),
  flag('flag-bold'),
  forkLeft('arrow-up-left-bold'),
  forkRight('arrow-up-right-bold'),

  /// The Simple Icons logo (CC0).
  googleMaps('google-maps'),
  info('info-bold', 'info-fill'),
  layers('circles-three-bold', 'circles-three-fill'),
  list('list-bullets-bold'),
  locationOn('map-pin-bold'),
  lock('lock-simple-bold'),
  more('dots-three-bold'),
  myLocation('gps-fix-bold'),
  navigation('navigation-arrow-bold'),
  nearMe('navigation-arrow-bold'),
  roundaboutLeft('arrow-counter-clockwise-bold'),
  roundaboutRight('arrow-clockwise-bold'),
  route('path-bold'),
  schedule('clock-bold', 'clock-fill'),
  search('magnifying-glass-bold'),
  stairs('stairs-bold'),
  straight('arrow-up-bold'),
  turnLeft('arrow-bend-up-left-bold'),
  turnRight('arrow-bend-up-right-bold'),
  turnSharpLeft('arrow-bend-down-left-bold'),
  turnSharpRight('arrow-bend-down-right-bold'),
  turnSlightLeft('arrow-up-left-bold'),
  turnSlightRight('arrow-up-right-bold'),
  uTurnLeft('arrow-u-down-left-bold'),
  warning('warning-bold');

  const AppIconName(this._file, [this._filledFile]);

  final String _file;

  /// Switched-on state of toggle controls.
  final String? _filledFile;

  /// Asset path inside the `design_system` package; [filled] picks the filled glyph when there is one.
  String asset({bool filled = false}) => 'assets/icons/${(filled ? _filledFile : null) ?? _file}.svg';
}

/// Icons take the surrounding text color unless [color] is given, like `currentColor` on web.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 24, this.color, this.filled = false, this.label});

  final AppIconName name;
  final double size;
  final Color? color;

  /// Switched-on state: the filled glyph when there is one.
  final bool filled;

  /// Accessible name; omit for decorative icons next to a text label.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? DefaultTextStyle.of(context).style.color ?? AppColors.textPrimary;
    return SvgPicture.asset(
      name.asset(filled: filled),
      package: 'design_system',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: label,
      excludeFromSemantics: label == null,
    );
  }
}
