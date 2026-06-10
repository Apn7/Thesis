import 'package:flutter/material.dart';
import 'dart:math' as math;

class ColorfulWaveform extends StatefulWidget {
  final bool isListening;

  const ColorfulWaveform({super.key, required this.isListening});

  @override
  State<ColorfulWaveform> createState() => _ColorfulWaveformState();
}

class _ColorfulWaveformState extends State<ColorfulWaveform>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _heightController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _heightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    if (widget.isListening) {
      _waveController.repeat();
      _heightController.forward();
    }
  }

  @override
  void didUpdateWidget(ColorfulWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening != oldWidget.isListening) {
      if (widget.isListening) {
        _waveController.repeat();
        _heightController.forward();
      } else {
        _heightController.reverse().then((_) => _waveController.stop());
      }
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_waveController, _heightController]),
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 140),
          painter: _WaveformPainter(
            animationValue: _waveController.value,
            heightScale: _heightController.value,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double animationValue;
  final double heightScale;

  _WaveformPainter({required this.animationValue, required this.heightScale});

  @override
  void paint(Canvas canvas, Size size) {
    if (heightScale <= 0.01) return;

    final centerY = size.height;
    final maxAmplitude = size.height * 0.9 * heightScale;

    final colors = [
      const Color(0xFF4285F4), // Google Blue
      const Color(0xFFEA4335), // Google Red
      const Color(0xFFFBBC05), // Google Yellow
      const Color(0xFF34A853), // Google Green
    ];

    // Offsets and speeds to make waves look organic
    final offsets = [0.0, 0.25, 0.5, 0.75];
    final speeds = [1.0, 1.2, 0.8, 1.4];

    for (int i = 0; i < 4; i++) {
      final path = Path();
      path.moveTo(0, centerY);

      final phase =
          (animationValue * speeds[i] * 2 * math.pi) + (offsets[i] * math.pi);

      for (double x = 0; x <= size.width; x += 3) {
        // Taper the ends to 0 amplitude for a smooth start/end
        final normalizedX = x / size.width;
        final taper = math.sin(normalizedX * math.pi);

        final y =
            centerY -
            (math.sin((normalizedX * math.pi * 3) + phase) *
                maxAmplitude *
                taper);
        path.lineTo(x, y);
      }

      path.lineTo(size.width, centerY);
      path.close();

      final paint = Paint()
        ..color = colors[i].withOpacity(0.55)
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.heightScale != heightScale;
  }
}
