import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../src/rust/api/simple.dart'; // FFI imports

enum EqFilterType {
  peaking,
  lowShelf,
  highShelf,
}

class EqNode {
  double freq;
  double gain;
  double q;
  EqFilterType type;

  EqNode({
    required this.freq,
    required this.gain,
    required this.q,
    this.type = EqFilterType.peaking,
  });
}

class LogarithmicCanvas extends StatefulWidget {
  const LogarithmicCanvas({Key? key}) : super(key: key);

  @override
  State<LogarithmicCanvas> createState() => _LogarithmicCanvasState();
}

class _LogarithmicCanvasState extends State<LogarithmicCanvas> {
  List<Point> _responseCurve = [];
  final List<EqNode> _nodes = [];
  int? _selectedNodeIndex;
  final FocusNode _focusNode = FocusNode();

  final double minFreq = 20.0;
  final double maxFreq = 20000.0;
  final double minDb = -15.0;
  final double maxDb = 15.0;

  @override
  void initState() {
    super.initState();
    _nodes.add(EqNode(freq: 1000.0, gain: 0.0, q: 0.707));
    _updateResponseCurve();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _updateResponseCurve() {
    if (_nodes.isEmpty) {
      setState(() {
        _responseCurve = [];
      });
      return;
    }

    List<Point>? combined;

    for (var node in _nodes) {
      // Usamos el backend de rust que por ahora calcula un PeakingEQ.
      final points = calculateBiquadResponse(freq: node.freq, gain: node.gain, q: node.q);
      if (combined == null) {
        combined = points;
      } else {
        for (int i = 0; i < combined.length && i < points.length; i++) {
          combined[i] = Point(x: combined[i].x, y: combined[i].y + points[i].y);
        }
      }
    }

    setState(() {
      _responseCurve = combined ?? [];
    });
  }

  double _freqToX(double freq, double width) {
    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final logF = math.log(freq.clamp(minFreq, maxFreq)) / math.ln10;
    final normalizedX = (logF - minLog) / logRange;
    return normalizedX * width;
  }

  double _xToFreq(double x, double width) {
    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final normalizedX = x / width;
    final logF = minLog + normalizedX * logRange;
    return math.pow(10, logF).toDouble();
  }

  double _gainToY(double gain, double height) {
    final normalizedY = 1.0 - ((gain.clamp(minDb, maxDb) - minDb) / (maxDb - minDb));
    return normalizedY * height;
  }

  double _yToGain(double y, double height) {
    final normalizedY = y / height;
    final gain = minDb + (1.0 - normalizedY) * (maxDb - minDb);
    return gain;
  }

  int? _findNodeAt(Offset position, double width, double height) {
    for (int i = _nodes.length - 1; i >= 0; i--) {
      final node = _nodes[i];
      final nodeX = _freqToX(node.freq, width);
      final nodeY = _gainToY(node.gain, height);
      final dist = math.sqrt(math.pow(nodeX - position.dx, 2) + math.pow(nodeY - position.dy, 2));
      if (dist < 20.0) {
        return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) {
          if (_selectedNodeIndex != null) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.keyQ) {
              setState(() {
                _nodes[_selectedNodeIndex!].type = EqFilterType.lowShelf;
                _updateResponseCurve();
              });
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.keyE) {
              setState(() {
                _nodes[_selectedNodeIndex!].type = EqFilterType.highShelf;
                _updateResponseCurve();
              });
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          return Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                final hoverIndex = _findNodeAt(pointerSignal.localPosition, width, height);
                if (hoverIndex != null) {
                  setState(() {
                    final node = _nodes[hoverIndex];
                    final scrollDelta = pointerSignal.scrollDelta.dy;
                    if (scrollDelta > 0) {
                      node.q = (node.q - 0.1).clamp(0.1, 10.0);
                    } else {
                      node.q = (node.q + 0.1).clamp(0.1, 10.0);
                    }
                    _updateResponseCurve();
                  });
                }
              }
            },
            child: GestureDetector(
              onSecondaryTapUp: (details) {
                final freq = _xToFreq(details.localPosition.dx, width);
                final gain = _yToGain(details.localPosition.dy, height);
                setState(() {
                  _nodes.add(EqNode(freq: freq, gain: gain, q: 0.707));
                  _selectedNodeIndex = _nodes.length - 1;
                  _focusNode.requestFocus();
                  _updateResponseCurve();
                });
              },
              onTapDown: (details) {
                final idx = _findNodeAt(details.localPosition, width, height);
                setState(() {
                  _selectedNodeIndex = idx;
                  if (idx != null) {
                    _focusNode.requestFocus();
                  }
                });
              },
              onPanStart: (details) {
                final idx = _findNodeAt(details.localPosition, width, height);
                if (idx != null) {
                  setState(() {
                    _selectedNodeIndex = idx;
                    _focusNode.requestFocus();
                  });
                }
              },
              onPanUpdate: (details) {
                if (_selectedNodeIndex != null) {
                  setState(() {
                    final node = _nodes[_selectedNodeIndex!];
                    final currentX = _freqToX(node.freq, width);
                    final currentY = _gainToY(node.gain, height);

                    final newX = currentX + details.delta.dx;
                    final newY = currentY + details.delta.dy;

                    node.freq = _xToFreq(newX, width).clamp(minFreq, maxFreq);
                    node.gain = _yToGain(newY, height).clamp(minDb, maxDb);
                    
                    _updateResponseCurve();
                  });
                }
              },
              child: Container(
                color: const Color(0xFF0D0F12),
                child: CustomPaint(
                  painter: _LogarithmicGridPainter(
                    responseCurve: _responseCurve,
                    nodes: _nodes,
                    selectedNodeIndex: _selectedNodeIndex,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    minDb: minDb,
                    maxDb: maxDb,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LogarithmicGridPainter extends CustomPainter {
  final List<Point> responseCurve;
  final List<EqNode> nodes;
  final int? selectedNodeIndex;
  
  final double minFreq;
  final double maxFreq;
  final double minDb;
  final double maxDb;

  final Color gridColor = const Color(0xFF262B34);
  final Color curveColor = const Color(0xFF00FF00); // Color de la curva

  _LogarithmicGridPainter({
    required this.responseCurve,
    required this.nodes,
    required this.selectedNodeIndex,
    required this.minFreq,
    required this.maxFreq,
    required this.minDb,
    required this.maxDb,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawCurve(canvas, size);
    _drawNodes(canvas, size);
  }

  void _drawNodes(Canvas canvas, Size size) {
    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final isSelected = i == selectedNodeIndex;

      final logF = math.log(node.freq) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      final normalizedY = 1.0 - ((node.gain - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;

      final paint = Paint()
        ..color = isSelected ? Colors.white : Colors.grey
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(Offset(x, y), isSelected ? 8.0 : 6.0, paint);

      // Draw Q indicator (bandwidth hint)
      final qPaint = Paint()
        ..color = (isSelected ? Colors.white : Colors.grey).withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      
      final qWidth = (10.0 / node.q) * 5.0;
      canvas.drawLine(Offset(x - qWidth, y), Offset(x + qWidth, y), qPaint);

      // Label for type
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );
      String typeStr = 'PK';
      if (node.type == EqFilterType.lowShelf) typeStr = 'LS';
      if (node.type == EqFilterType.highShelf) typeStr = 'HS';
      textPainter.text = TextSpan(
        text: typeStr,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - 24));
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw horizontal lines
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

    // Draw vertical lines
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
      if (point.x < minFreq || point.x > maxFreq) continue;

      final logF = math.log(point.x) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

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
    // Para simplificar la demo, repintamos siempre (podría optimizarse)
    return true;
  }
}
