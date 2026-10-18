import 'dart:math';

import 'package:flutter/widgets.dart';

import 'app_icon.dart';
import 'defi_icon_button.dart';
import 'tokens.dart';

enum SheetSnap {
  compact(0.32),
  medium(0.7),
  expanded(1);

  const SheetSnap(this.fraction);
  final double fraction;
}

const _minHeight = 168.0;

/// The one bottom sheet over the map (DESIGN.md §6): compact, medium or expanded, dragged by its handle.
class DefiSheet extends StatefulWidget {
  const DefiSheet({
    super.key,
    required this.child,
    required this.maxHeight,
    this.initialSnap = SheetSnap.medium,
    this.onHeightChanged,
    this.onClose,
  });

  /// Sheet content; scrolls itself, e.g. with [DefiSheetScroll].
  final Widget child;

  /// Viewport height minus the space kept free above the expanded sheet (app header).
  final double maxHeight;
  final SheetSnap initialSnap;

  /// Height the sheet covers at the bottom of the screen.
  final ValueChanged<double>? onHeightChanged;

  /// Shows a close button in the top-right corner.
  final VoidCallback? onClose;

  static double heightFor(SheetSnap snap, double maxHeight) =>
      min(maxHeight, max(_minHeight, (maxHeight * snap.fraction).roundToDouble()));

  @override
  State<DefiSheet> createState() => _DefiSheetState();
}

class _DefiSheetState extends State<DefiSheet> {
  late SheetSnap _snap = widget.initialSnap;
  double? _dragHeight;
  double? _reported;

  double get _height => _dragHeight ?? DefiSheet.heightFor(_snap, widget.maxHeight);

  void _report() {
    final height = _height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHeightChanged?.call(height);
    });
  }

  void _toggle() => setState(() => _snap = _snap == SheetSnap.expanded ? SheetSnap.medium : SheetSnap.expanded);

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _dragHeight = (_height - details.delta.dy).clamp(_minHeight, widget.maxHeight));
  }

  void _onDragEnd(DragEndDetails _) {
    final dragged = _dragHeight;
    if (dragged == null) return;
    double distance(SheetSnap s) => (DefiSheet.heightFor(s, widget.maxHeight) - dragged).abs();
    setState(() {
      _snap = SheetSnap.values.reduce((best, s) => distance(s) < distance(best) ? s : best);
      _dragHeight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    _report();
    final expanded = _snap == SheetSnap.expanded;
    final closable = widget.onClose != null;

    final handle = Semantics(
      button: true,
      expanded: expanded,
      label: expanded ? 'Zwiń szczegóły' : 'Pokaż szczegóły',
      onTap: _toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () => _onDragEnd(DragEndDetails()),
        child: SizedBox(
          // With a close button the handle row grows to 48 and holds it, so long titles never run under it.
          height: closable ? 48 : 32,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: const BoxDecoration(color: AppColors.borderControl, borderRadius: AppRadius.pill),
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Extends the handle's hit area to 48 above the sheet without adding visible space.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: const SizedBox(height: 16, width: double.infinity),
        ),
        AnimatedContainer(
          duration: _dragHeight == null ? AppDurations.panel : Duration.zero,
          curve: Curves.easeOut,
          height: _height,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.sheet,
            boxShadow: AppShadows.panel,
          ),
          child: Column(
            children: [
              Stack(
                children: [
                  handle,
                  if (closable)
                    Positioned(
                      top: 0,
                      right: AppSpacing.s8,
                      child: DefiIconButton(icon: AppIconName.close, label: 'Zamknij', onPressed: widget.onClose),
                    ),
                ],
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ],
    );
  }
}

/// Scrolling body of the sheet, clear of the home indicator at the bottom.
class DefiSheetScroll extends StatelessWidget {
  const DefiSheetScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: child,
    );
  }
}
