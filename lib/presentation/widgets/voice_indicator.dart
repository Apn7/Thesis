import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/theme/app_colors.dart';

/// Animated voice activity indicator
class VoiceIndicator extends StatefulWidget {
  final bool isListening;
  final double size;
  
  const VoiceIndicator({
    super.key,
    required this.isListening,
    this.size = 80,
  });
  
  @override
  State<VoiceIndicator> createState() => _VoiceIndicatorState();
}

class _VoiceIndicatorState extends State<VoiceIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: widget.isListening 
          ? 'শুনছি। Listening.' 
          : 'ভয়েস কমান্ডের জন্য অপেক্ষা করছি। Waiting for voice command.',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _VoiceIndicatorPainter(
              animation: _controller.value,
              isListening: widget.isListening,
            ),
          );
        },
      ),
    );
  }
}

class _VoiceIndicatorPainter extends CustomPainter {
  final double animation;
  final bool isListening;
  
  _VoiceIndicatorPainter({
    required this.animation,
    required this.isListening,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 3;
    
    if (isListening) {
      // Animated ripple effect when listening
      for (int i = 0; i < 3; i++) {
        final rippleAnimation = (animation + (i * 0.33)) % 1.0;
        final rippleRadius = baseRadius + (rippleAnimation * baseRadius * 0.8);
        final rippleOpacity = (1.0 - rippleAnimation) * 0.3;
        
        final ripplePaint = Paint()
          ..color = AppColors.accent.withOpacity(rippleOpacity)
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(center, rippleRadius, ripplePaint);
      }
      
      // Pulsing core
      final pulseFactor = 1.0 + (math.sin(animation * 2 * math.pi) * 0.1);
      final corePaint = Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(center, baseRadius * pulseFactor, corePaint);
      
      // Mic icon
      _drawMicIcon(canvas, center, baseRadius * 0.5);
    } else {
      // Static state when not listening
      final staticPaint = Paint()
        ..color = AppColors.primary.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(center, baseRadius, staticPaint);
      
      // Mic icon
      _drawMicIcon(canvas, center, baseRadius * 0.5, inactive: true);
    }
  }
  
  void _drawMicIcon(Canvas canvas, Offset center, double size, {bool inactive = false}) {
    final iconPaint = Paint()
      ..color = inactive ? AppColors.textSecondary : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    // Simplified microphone shape
    final micRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - size * 0.2),
        width: size * 0.6,
        height: size * 0.8,
      ),
      Radius.circular(size * 0.3),
    );
    
    canvas.drawRRect(micRect, iconPaint);
    
    // Mic stand
    canvas.drawLine(
      Offset(center.dx, center.dy + size * 0.4),
      Offset(center.dx, center.dy + size * 0.7),
      iconPaint,
    );
    
    // Mic base
    canvas.drawLine(
      Offset(center.dx - size * 0.3, center.dy + size * 0.7),
      Offset(center.dx + size * 0.3, center.dy + size * 0.7),
      iconPaint,
    );
  }
  
  @override
  bool shouldRepaint(_VoiceIndicatorPainter oldDelegate) {
    return animation != oldDelegate.animation || isListening != oldDelegate.isListening;
  }
}
