import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart'; // FFI imports

class LogarithmicCanvas extends StatefulWidget {
  const LogarithmicCanvas({Key? key}) : super(key: key);

  @override
  State<LogarithmicCanvas> createState() => _LogarithmicCanvasState();
}

class _LogarithmicCanvasState extends State<LogarithmicCanvas> {
  List<Point> _responseCurve = [];

  @override
  void initState() {
    super.initState();
    // Boceto: llamada a la función de Rust vía FFI
    _updateResponseCurve();
  }

  void _updateResponseCurve() {
    // Ejemplo de llamada a Rust
    // Esto es síncrono según la configuración actual del FFI en simple.rs
    final points = calculateBiquadResponse(freq: 1000.0, gain: 6.0, q: 0.707);
    setState(() {
      _responseCurve = points;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0F12),
      child: CustomPaint(
        painter: _LogarithmicGridPainter(responseCurve: _responseCurve),
        size: Size.infinite,
      ),
    );
  }
}

class _LogarithmicGridPainter extends CustomPainter {
  final List<Point> responseCurve;
  
  final double minFreq = 20.0;
  final double maxFreq = 20000.0;
  final double minDb = -15.0;
  final double maxDb = 15.0;
  final Color gridColor = const Color(0xFF262B34);
  final Color curveColor = const Color(0xFF00FF00); // Color de la curva

  _LogarithmicGridPainter({required this.responseCurve});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawCurve(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw horizontal lines (Linear Y axis: -15dB to +15dB)
    final dbStep = 5.0;
    for (double db = minDb; db <= maxDb; db += dbStep) {
      final normalizedY = 1.0 - ((db - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;
      
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);

      textPainter.text = TextSpan(
        text: '${db > 0 ? '+' : ''}${db.toInt()} dB',
        style: TextStyle(color: gridColor, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(5, y - textPainter.height - 2));
    }

    // Draw vertical lines (Logarithmic X axis: 20Hz to 20kHz)
    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final List<double> freqs = [
      20, 30, 40, 50, 60, 70, 80, 90,
      100, 200, 300, 400, 500, 600, 700, 800, 900,
      1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000,
      10000, 20000
    ];

    final List<double> labels = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];

    for (final freq in freqs) {
      final logF = math.log(freq) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      final isMajor = labels.contains(freq);
      paint.strokeWidth = isMajor ? 1.0 : 0.5;
      paint.color = isMajor ? gridColor : gridColor.withOpacity(0.5);

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

      if (isMajor) {
        String labelText = freq >= 1000 
            ? '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}k' 
            : '${freq.toInt()}';
        
        textPainter.text = TextSpan(
          text: labelText,
          style: TextStyle(color: gridColor, fontSize: 10),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, size.height - textPainter.height - 2));
      }
    }
  }

  void _drawCurve(Canvas canvas, Size size) {
    if (responseCurve.isEmpty) return;

    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final paint = Paint()
      ..color = curveColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool first = true;

    for (final point in responseCurve) {
      // Ignorar puntos fuera del rango visible si es necesario
      if (point.x < minFreq || point.x > maxFreq) continue;

      final logF = math.log(point.x) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      // Clamping dB to visible area optional
      final db = point.y.clamp(minDb, maxDb);
      final normalizedY = 1.0 - ((db - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LogarithmicGridPainter oldDelegate) {
    return oldDelegate.responseCurve != responseCurve;
  }
}
