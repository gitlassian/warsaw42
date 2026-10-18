import 'dart:math';

import 'package:flutter/widgets.dart';

import 'app_text.dart';
import 'tokens.dart';

/// Decorative progress ring in the text color; always pair it with a text status.
class DefiSpinner extends StatefulWidget {
  const DefiSpinner({super.key});

  @override
  State<DefiSpinner> createState() => _DefiSpinnerState();
}

class _DefiSpinnerState extends State<DefiSpinner> with SingleTickerProviderStateMixin {
  late final _turns = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: a still ring, like the web.
    if (MediaQuery.disableAnimationsOf(context)) {
      _turns.stop();
    } else if (!_turns.isAnimating) {
      _turns.repeat();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ?? AppColors.textPrimary;
    return ExcludeSemantics(
      child: RotationTransition(
        turns: _turns,
        child: CustomPaint(size: const Size.square(20), painter: _RingPainter(color)),
      ),
    );
  }
}

/// A 2-wide ring with its right quarter left out (CSS: border-right-color: transparent).
class _RingPainter extends CustomPainter {
  const _RingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      (Offset.zero & size).deflate(1),
      pi / 4,
      3 * pi / 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// Spinner with a visible status text, e.g. while a panel loads.
class DefiLoadingText extends StatelessWidget {
  const DefiLoadingText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.body.copyWith(color: AppColors.textSecondary);
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DefaultTextStyle(
          style: style,
          child: Row(
            spacing: AppSpacing.s8,
            children: [
              const DefiSpinner(),
              Flexible(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}
