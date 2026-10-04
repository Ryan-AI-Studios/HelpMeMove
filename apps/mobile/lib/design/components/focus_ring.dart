import 'package:flutter/material.dart';

/// Draws a 2 dp accent outline 2 dp outside [child] while a descendant is focused.
class OutsideFocusRing extends StatelessWidget {
  const OutsideFocusRing({
    super.key,
    required this.color,
    required this.borderRadius,
    required this.child,
  });

  final Color color;
  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      child: Builder(
        builder: (BuildContext context) {
          return ListenableBuilder(
            listenable: FocusManager.instance,
            builder: (BuildContext context, Widget? child) {
              final bool focused = Focus.of(context).hasFocus;
              return CustomPaint(
                painter: focused
                    ? _OutsideRingPainter(
                        color: color,
                        buttonRadius: borderRadius,
                      )
                    : null,
                child: Padding(padding: const EdgeInsets.all(4), child: child),
              );
            },
            child: child,
          );
        },
      ),
    );
  }
}

class _OutsideRingPainter extends CustomPainter {
  const _OutsideRingPainter({required this.color, required this.buttonRadius});

  final Color color;
  final double buttonRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final RRect ring = RRect.fromRectAndRadius(
      bounds.deflate(1),
      Radius.circular(buttonRadius + 3),
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawRRect(ring, paint);
  }

  @override
  bool shouldRepaint(covariant _OutsideRingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.buttonRadius != buttonRadius;
  }
}
