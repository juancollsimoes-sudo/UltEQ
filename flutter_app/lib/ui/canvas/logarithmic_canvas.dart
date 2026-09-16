import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../src/rust/api/simple.dart';
import '../../models/eq_state.dart';
import '../theme/app_theme.dart';

class LogarithmicCanvas extends StatefulWidget {
  final EqState eqState;

  const LogarithmicCanvas({super.key, required this.eqState});

  @override
  State<LogarithmicCanvas> createState() => _LogarithmicCanvasState();
}

class _LogarithmicCanvasState extends State<LogarithmicCanvas> with TickerProviderStateMixin {
  List<Point> _responseCurve = [];
  List<Point> _startCurve = [];
  List<Point> _targetCurve = [];
  final FocusNode _focusNode = FocusNode();
  int? _hoveredNodeIndex;
  bool _isDragging = false;

  late final AnimationController _morphController;
  late final Animation<double> _morphAnimation;

  late final AnimationController _nodePulseController;
  late final Animation<double> _nodePulseAnimation;

  late final AnimationController _scanController;

  final double minFreq = 20.0;
  final double maxFreq = 20000.0;

  double get minDb {
    switch (widget.eqState.scaleMode) {
      case YAxisScaleMode.crinStandard:
        return 30.0;
      case YAxisScaleMode.crin50Db:
        return 35.0;
      case YAxisScaleMode.deltaGain:
        return -15.0;
    }
  }

  double get maxDb {
    switch (widget.eqState.scaleMode) {
      case YAxisScaleMode.crinStandard:
        return 85.0;
      case YAxisScaleMode.crin50Db:
        return 85.0;
      case YAxisScaleMode.deltaGain:
        return 15.0;
    }
  }

  double get refDb {
    switch (widget.eqState.scaleMode) {
      case YAxisScaleMode.crinStandard:
      case YAxisScaleMode.crin50Db:
        return 60.0;
      case YAxisScaleMode.deltaGain:
        return 0.0;
    }
  }

  @override
  void initState() {
    super.initState();

    // 1. Fluid Curve Morphing Animation
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _morphAnimation = CurvedAnimation(
      parent: _morphController,
      curve: Curves.easeOutCubic,
    )..addListener(() {
        if (_startCurve.isNotEmpty &&
            _targetCurve.isNotEmpty &&
            _startCurve.length == _targetCurve.length) {
          final t = _morphAnimation.value;
          final count = _startCurve.length;
          final morphed = List<Point>.generate(count, (i) {
            final y = _startCurve[i].y + (_targetCurve[i].y - _startCurve[i].y) * t;
            return Point(x: _targetCurve[i].x, y: y);
          });
          setState(() {
            _responseCurve = morphed;
          });
        }
      });

    // 2. Selected Node Breathing Glow Animation
    _nodePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _nodePulseAnimation = CurvedAnimation(
      parent: _nodePulseController,
      curve: Curves.easeInOut,
    );

    // 3. AutoEq Laser Scanline Beam Animation
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat();

    widget.eqState.addListener(_updateResponseCurve);
    _updateResponseCurve(immediate: true);
  }

  @override
  void didUpdateWidget(covariant LogarithmicCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eqState != widget.eqState) {
      oldWidget.eqState.removeListener(_updateResponseCurve);
      widget.eqState.addListener(_updateResponseCurve);
      _updateResponseCurve();
    }
  }

  @override
  void dispose() {
    widget.eqState.removeListener(_updateResponseCurve);
    _morphController.dispose();
    _nodePulseController.dispose();
    _scanController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateResponseCurve({bool immediate = false}) {
    final filters = widget.eqState.nodes.map((node) {
      FilterType rType = FilterType.peaking;
      if (node.type == EqFilterType.lowShelf) rType = FilterType.lowShelf;
      if (node.type == EqFilterType.highShelf) rType = FilterType.highShelf;
      return ActiveFilter(filterType: rType, freq: node.freq, gain: node.gain, q: node.q);
    }).toList();

    List<Point> biquadPoints = [];
    try {
      biquadPoints = calculateBiquadResponse(filters: filters);
    } catch (_) {}

    if (biquadPoints.isEmpty) {
      for (int i = 0; i < 200; i++) {
        double f = 20.0 * math.pow(1000.0, i / 199.0);
        biquadPoints.add(Point(x: f, y: 0.0));
      }
    }

    double getHeadphoneGain(double freq) {
      final hpCurve = widget.eqState.headphoneCurve;
      if (hpCurve.isEmpty) return 0.0;
      if (freq <= hpCurve.first.x) return hpCurve.first.y;
      if (freq >= hpCurve.last.x) return hpCurve.last.y;

      for (int i = 0; i < hpCurve.length - 1; i++) {
        if (freq >= hpCurve[i].x && freq <= hpCurve[i + 1].x) {
          final x0 = hpCurve[i].x;
          final y0 = hpCurve[i].y;
          final x1 = hpCurve[i + 1].x;
          final y1 = hpCurve[i + 1].y;
          if (x1 == x0) return y0;
          return y0 + (y1 - y0) * (freq - x0) / (x1 - x0);
        }
      }
      return 0.0;
    }

    final combinedCurve = biquadPoints.map((bp) {
      return Point(x: bp.x, y: bp.y + getHeadphoneGain(bp.x));
    }).toList();

    if (immediate || _isDragging || _responseCurve.isEmpty || _responseCurve.length != combinedCurve.length) {
      _morphController.stop();
      setState(() {
        _responseCurve = combinedCurve;
        _startCurve = combinedCurve;
        _targetCurve = combinedCurve;
      });
    } else {
      _startCurve = List<Point>.from(_responseCurve);
      _targetCurve = combinedCurve;
      _morphController.forward(from: 0.0);
    }
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

    final normalizedX = (x / width).clamp(0.0, 1.0);
    final logF = minLog + normalizedX * logRange;
    return math.pow(10, logF).toDouble();
  }

  double _gainToY(double gain, double height) {
    final yVal = refDb + gain;
    final normalizedY = 1.0 - ((yVal.clamp(minDb, maxDb) - minDb) / (maxDb - minDb));
    return normalizedY * height;
  }

  double _yToGain(double y, double height) {
    final normalizedY = (y / height).clamp(0.0, 1.0);
    final yVal = minDb + (1.0 - normalizedY) * (maxDb - minDb);
    final gain = yVal - refDb;
    return gain.clamp(-15.0, 15.0);
  }

  int? _findNodeAt(Offset position, double width, double height) {
    final nodes = widget.eqState.nodes;
    for (int i = nodes.length - 1; i >= 0; i--) {
      final node = nodes[i];
      final nodeX = _freqToX(node.freq, width);
      final nodeY = _gainToY(node.gain, height);
      final dist = math.sqrt(math.pow(nodeX - position.dx, 2) + math.pow(nodeY - position.dy, 2));
      if (dist < 22.0) {
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
          final selectedNodeIndex = widget.eqState.selectedIndex;
          if (selectedNodeIndex != null && selectedNodeIndex < widget.eqState.nodes.length) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.keyQ) {
              widget.eqState.nodes[selectedNodeIndex].type = EqFilterType.lowShelf;
              widget.eqState.triggerUpdate();
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.keyE) {
              widget.eqState.nodes[selectedNodeIndex].type = EqFilterType.highShelf;
              widget.eqState.triggerUpdate();
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.keyP) {
              widget.eqState.nodes[selectedNodeIndex].type = EqFilterType.peaking;
              widget.eqState.triggerUpdate();
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
              widget.eqState.removeNode(selectedNodeIndex);
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;

              return MouseRegion(
                onHover: (event) {
                  final idx = _findNodeAt(event.localPosition, width, height);
                  if (idx != _hoveredNodeIndex) {
                    setState(() {
                      _hoveredNodeIndex = idx;
                    });
                  }
                },
                child: Listener(
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      final hoverIndex = _findNodeAt(pointerSignal.localPosition, width, height);
                      if (hoverIndex != null) {
                        final node = widget.eqState.nodes[hoverIndex];
                        final scrollDelta = pointerSignal.scrollDelta.dy;
                        if (scrollDelta > 0) {
                          node.q = (node.q - 0.1).clamp(0.2, 9.0);
                        } else {
                          node.q = (node.q + 0.1).clamp(0.2, 9.0);
                        }
                        widget.eqState.triggerUpdate();
                      }
                    }
                  },
                  child: GestureDetector(
                    onSecondaryTapUp: (details) {
                      final freq = _xToFreq(details.localPosition.dx, width);
                      final gain = _yToGain(details.localPosition.dy, height);
                      widget.eqState.addNode(EqNode(freq: freq, gain: gain, q: 1.414));
                      _focusNode.requestFocus();
                    },
                    onDoubleTapDown: (details) {
                      final idx = _findNodeAt(details.localPosition, width, height);
                      if (idx == null) {
                        final freq = _xToFreq(details.localPosition.dx, width);
                        final gain = _yToGain(details.localPosition.dy, height);
                        widget.eqState.addNode(EqNode(freq: freq, gain: gain, q: 1.414));
                        _focusNode.requestFocus();
                      }
                    },
                    onTapDown: (details) {
                      final idx = _findNodeAt(details.localPosition, width, height);
                      widget.eqState.selectNode(idx);
                      _focusNode.requestFocus();
                    },
                    onPanStart: (details) {
                      _isDragging = true;
                      final idx = _findNodeAt(details.localPosition, width, height);
                      if (idx != null) {
                        widget.eqState.selectNode(idx);
                        _focusNode.requestFocus();
                      }
                    },
                    onPanEnd: (_) => _isDragging = false,
                    onPanCancel: () => _isDragging = false,
                    onPanUpdate: (details) {
                      final selectedNodeIndex = widget.eqState.selectedIndex;
                      if (selectedNodeIndex != null && selectedNodeIndex < widget.eqState.nodes.length) {
                        final node = widget.eqState.nodes[selectedNodeIndex];
                        final currentX = _freqToX(node.freq, width);
                        final currentY = _gainToY(node.gain, height);

                        final newX = currentX + details.delta.dx;
                        final newY = currentY + details.delta.dy;

                        node.freq = _xToFreq(newX, width).clamp(minFreq, maxFreq);
                        node.gain = _yToGain(newY, height).clamp(-15.0, 15.0);

                        widget.eqState.triggerUpdate();
                      }
                    },
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_nodePulseAnimation, _scanController]),
                      builder: (context, _) {
                        return Container(
                          color: AppColors.canvasBg,
                          child: CustomPaint(
                            painter: _PrecisionCanvasPainter(
                              responseCurve: _responseCurve,
                              targetCurve: widget.eqState.targetCurve,
                              headphoneCurve: widget.eqState.headphoneCurve,
                              isDualChannel: widget.eqState.isDualChannel,
                              matchChannels: widget.eqState.matchChannels,
                              headphoneCurveL: widget.eqState.headphoneCurveL,
                              headphoneCurveR: widget.eqState.headphoneCurveR,
                              matchedCurveL: widget.eqState.matchedCurveL,
                              matchedCurveR: widget.eqState.matchedCurveR,
                              nodes: widget.eqState.nodes,
                              selectedNodeIndex: widget.eqState.selectedIndex,
                              hoveredNodeIndex: _hoveredNodeIndex,
                              normalizeToTarget: widget.eqState.normalizeToTarget,
                              scaleMode: widget.eqState.scaleMode,
                              isBypassActive: widget.eqState.isBypassActive,
                              autoGainOffsetDb: widget.eqState.autoGainOffsetDb,
                              minFreq: minFreq,
                              maxFreq: maxFreq,
                              minDb: minDb,
                              maxDb: maxDb,
                              refDb: refDb,
                              nodePulseValue: _nodePulseAnimation.value,
                              scanProgress: widget.eqState.isComputingAutoeq ? _scanController.value : null,
                            ),
                            size: Size.infinite,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),

          // Floating Top Controls Bar (Linear Dock)
          Positioned(
            top: 14,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderSubtle),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Legend Pills
                  if (widget.eqState.isDualChannel) ...[
                    _buildLegendItem(AppColors.cyan, 'Raw L'),
                    const SizedBox(width: 8),
                    _buildLegendItem(AppColors.rose, 'Raw R'),
                  ] else ...[
                    _buildLegendItem(AppColors.cyan, 'Raw'),
                  ],
                  const SizedBox(width: 8),
                  _buildLegendItem(AppColors.primaryLight, 'Target', isDashed: true),
                  const SizedBox(width: 8),
                  _buildLegendItem(AppColors.emerald, 'Output EQ'),

                  // Match Channels / Test Balance Action
                  if (widget.eqState.isDualChannel) ...[
                    const SizedBox(width: 10),
                    Container(width: 1, height: 16, color: AppColors.borderSubtle),
                    const SizedBox(width: 8),
                    _buildMatchChannelsChip(),
                  ] else if (widget.eqState.headphoneCurve.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(width: 1, height: 16, color: AppColors.borderSubtle),
                    const SizedBox(width: 8),
                    _buildTestBalanceChip(),
                  ],

                  const SizedBox(width: 10),
                  Container(width: 1, height: 16, color: AppColors.borderSubtle),
                  const SizedBox(width: 8),

                  // Y-Axis Scale Mode Dropdown
                  _buildScaleModeDropdown(),

                  const SizedBox(width: 8),
                  Container(width: 1, height: 16, color: AppColors.borderSubtle),
                  const SizedBox(width: 8),

                  // Normalize Button (Compensated / Flat view)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => widget.eqState.toggleNormalize(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.eqState.normalizeToTarget
                            ? AppColors.emerald.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.eqState.normalizeToTarget
                              ? AppColors.emerald.withValues(alpha: 0.5)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.eqState.normalizeToTarget
                                ? Icons.check_circle_outline
                                : Icons.horizontal_rule,
                            size: 13,
                            color: widget.eqState.normalizeToTarget
                                ? AppColors.emeraldLight
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Compensated',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: widget.eqState.normalizeToTarget
                                  ? AppColors.emeraldLight
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 16, color: AppColors.borderSubtle),
                  const SizedBox(width: 8),

                  // Bypass A/B Toggle Chip
                  _buildBypassToggleChip(),
                ],
              ),
            ),
          ),

          // Bottom Left Keyboard Hints & Scale Indicator
          Positioned(
            bottom: 12,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderSubtle.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getScaleBadgeText(),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppTypography.monoFont,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '2x Click: Add Band • Drag: Adjust • Scroll: Q • Q/E: Shelf • Del: Remove',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: AppTypography.monoFont,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getScaleBadgeText() {
    switch (widget.eqState.scaleMode) {
      case YAxisScaleMode.crinStandard:
        return 'CRIN 30-85 dB SPL';
      case YAxisScaleMode.crin50Db:
        return 'CRIN 50dB SWEET SPOT';
      case YAxisScaleMode.deltaGain:
        return 'DAW GAIN ±15 dB';
    }
  }

  Widget _buildScaleModeDropdown() {
    String currentLabel;
    switch (widget.eqState.scaleMode) {
      case YAxisScaleMode.crinStandard:
        currentLabel = 'Crin (30–85 dB)';
        break;
      case YAxisScaleMode.crin50Db:
        currentLabel = 'Crin 50dB (35–85)';
        break;
      case YAxisScaleMode.deltaGain:
        currentLabel = 'DAW Gain (±15 dB)';
        break;
    }

    return PopupMenuButton<YAxisScaleMode>(
      initialValue: widget.eqState.scaleMode,
      tooltip: 'Select Y-Axis Scale',
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderSubtle),
      ),
      onSelected: (newMode) => widget.eqState.setScaleMode(newMode),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: YAxisScaleMode.crinStandard,
          height: 36,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Crinacle Standard (30–85 dB SPL)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text('Squiglink default • 55 dB span • 60 dB SPL ref', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: YAxisScaleMode.crin50Db,
          height: 36,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Crinacle 50dB (35–85 dB SPL)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text('Graphs 101 Sweet Spot • 16:9 proportional view', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: YAxisScaleMode.deltaGain,
          height: 36,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('DAW Filter Gain Mode (±15 dB)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text('Relative filter cut/boost around 0 dB', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: AppColors.cardHover,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stacked_line_chart, size: 13, color: AppColors.primaryLight),
            const SizedBox(width: 5),
            Text(
              currentLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLight,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.primaryLight),
          ],
        ),
      ),
    );
  }

  Widget _buildBypassToggleChip() {
    final isBypass = widget.eqState.isBypassActive;
    final autoGain = widget.eqState.autoGainOffsetDb;
    final autoGainStr = '${autoGain >= 0 ? "+" : ""}${autoGain.toStringAsFixed(1)} dB';

    return Tooltip(
      message: isBypass
          ? 'EQ Bypassed (Level Matched $autoGainStr) • Click to activate EQ'
          : 'EQ Active • Click to Bypass for A/B level-matched comparison',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.eqState.toggleBypass(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isBypass
                ? AppColors.amber.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isBypass
                  ? AppColors.amberLight.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isBypass ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                size: 13,
                color: isBypass ? AppColors.amberLight : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                isBypass ? 'Bypass (A/B)' : 'A/B Match',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isBypass ? AppColors.amberLight : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchChannelsChip() {
    final isMatched = widget.eqState.matchChannels;
    final avgImb = widget.eqState.avgImbalanceDb;
    final maxImb = widget.eqState.maxImbalanceDb;
    final maxFreq = widget.eqState.maxImbalanceFreq;
    final freqLabel = maxFreq >= 1000
        ? '${(maxFreq / 1000).toStringAsFixed(1)}k'
        : maxFreq.toInt().toString();

    return Tooltip(
      message: isMatched
          ? 'Channels calibrated symmetrically to acoustic midline (±0.0 dB residual)'
          : 'Channel imbalance detected: max ${maxImb.toStringAsFixed(1)} dB deviation at $freqLabel Hz',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.eqState.toggleMatchChannels(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            gradient: isMatched
                ? const LinearGradient(
                    colors: [Color(0xFF0284C7), AppColors.emerald],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isMatched ? null : AppColors.cardHover,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMatched
                  ? AppColors.emeraldLight.withValues(alpha: 0.65)
                  : AppColors.cyan.withValues(alpha: 0.4),
              width: isMatched ? 1.2 : 1.0,
            ),
            boxShadow: isMatched
                ? const [
                    BoxShadow(
                      color: AppColors.emeraldGlow,
                      blurRadius: 10,
                      offset: Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isMatched ? Icons.check_circle : Icons.sync_alt,
                size: 13,
                color: isMatched ? Colors.white : AppColors.cyanLight,
              ),
              const SizedBox(width: 5),
              Text(
                isMatched ? 'Matched' : 'Match Channels',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isMatched ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isMatched
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppColors.rose.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isMatched ? '±0.0 dB' : 'Δ ${avgImb.toStringAsFixed(1)} dB',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontFamily: AppTypography.monoFont,
                    fontWeight: FontWeight.w700,
                    color: isMatched ? Colors.white : AppColors.roseLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestBalanceChip() {
    return Tooltip(
      message: 'Simulate physical driver tolerance (±1.4 dB) to test channel matching',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.eqState.simulateDualChannel(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.cardHover,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 12, color: AppColors.cyanLight),
              SizedBox(width: 4),
              Text(
                'Test Balance',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, {bool isDashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _PrecisionCanvasPainter extends CustomPainter {
  final List<Point> responseCurve;
  final List<Point> targetCurve;
  final List<Point> headphoneCurve;
  final bool isDualChannel;
  final bool matchChannels;
  final List<Point> headphoneCurveL;
  final List<Point> headphoneCurveR;
  final List<Point> matchedCurveL;
  final List<Point> matchedCurveR;
  final List<EqNode> nodes;
  final int? selectedNodeIndex;
  final int? hoveredNodeIndex;
  final bool normalizeToTarget;
  final YAxisScaleMode scaleMode;
  final bool isBypassActive;
  final double autoGainOffsetDb;

  final double minFreq;
  final double maxFreq;
  final double minDb;
  final double maxDb;
  final double refDb;

  final double nodePulseValue;
  final double? scanProgress;

  _PrecisionCanvasPainter({
    required this.responseCurve,
    required this.targetCurve,
    required this.headphoneCurve,
    required this.isDualChannel,
    required this.matchChannels,
    required this.headphoneCurveL,
    required this.headphoneCurveR,
    required this.matchedCurveL,
    required this.matchedCurveR,
    required this.nodes,
    required this.selectedNodeIndex,
    required this.hoveredNodeIndex,
    required this.normalizeToTarget,
    required this.scaleMode,
    required this.isBypassActive,
    required this.autoGainOffsetDb,
    required this.minFreq,
    required this.maxFreq,
    required this.minDb,
    required this.maxDb,
    required this.refDb,
    required this.nodePulseValue,
    this.scanProgress,
  });

  double _getTargetGain(double freq) {
    if (targetCurve.isEmpty) return 0.0;
    if (freq <= targetCurve.first.x) return targetCurve.first.y;
    if (freq >= targetCurve.last.x) return targetCurve.last.y;

    for (int i = 0; i < targetCurve.length - 1; i++) {
      if (freq >= targetCurve[i].x && freq <= targetCurve[i + 1].x) {
        final x0 = targetCurve[i].x;
        final y0 = targetCurve[i].y;
        final x1 = targetCurve[i + 1].x;
        final y1 = targetCurve[i + 1].y;
        if (x1 == x0) return y0;
        return y0 + (y1 - y0) * (freq - x0) / (x1 - x0);
      }
    }
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    if (scanProgress != null) {
      _drawAutoEqScanBeam(canvas, size, scanProgress!);
    }
    _drawTargetCurve(canvas, size);
    _drawHeadphoneCurve(canvas, size);
    _drawResponseGlowAndCurve(canvas, size);
    _drawNodes(canvas, size);
    if (isBypassActive) {
      _drawBypassOverlay(canvas, size);
    }
  }

  void _drawAutoEqScanBeam(Canvas canvas, Size size, double progress) {
    final x = progress * size.width;
    final beamGradient = ui.Gradient.linear(
      Offset(x - 36, 0),
      Offset(x + 36, 0),
      [
        Colors.transparent,
        AppColors.primary.withValues(alpha: 0.12),
        AppColors.primaryLight.withValues(alpha: 0.35),
        AppColors.primary.withValues(alpha: 0.12),
        Colors.transparent,
      ],
      [0.0, 0.35, 0.5, 0.65, 1.0],
    );
    final beamPaint = Paint()
      ..shader = beamGradient
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(x - 36, 0, 72, size.height), beamPaint);

    final linePaint = Paint()
      ..color = AppColors.primaryLight.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    // Horizontal dB Lines
    final bool isCrinMode = (scaleMode == YAxisScaleMode.crinStandard || scaleMode == YAxisScaleMode.crin50Db);

    final List<double> dbValues = [];
    if (isCrinMode) {
      for (double d = minDb; d <= maxDb; d += 5.0) {
        dbValues.add(d);
      }
    } else {
      for (double d = -15.0; d <= 15.0; d += 3.0) {
        dbValues.add(d);
      }
    }

    for (final db in dbValues) {
      final normalizedY = 1.0 - ((db - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;

      final isRef = (db - refDb).abs() < 0.1;
      final isMajor = isCrinMode ? (db % 10.0 == 0.0) : (db % 6.0 == 0.0);

      if (isRef) {
        linePaint.color = AppColors.primaryLight.withValues(alpha: 0.45);
        linePaint.strokeWidth = 1.4;
      } else if (isMajor) {
        linePaint.color = AppColors.gridDecade;
        linePaint.strokeWidth = 0.8;
      } else {
        linePaint.color = AppColors.gridSub;
        linePaint.strokeWidth = 0.5;
      }

      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

      // Label
      String labelStr;
      if (isCrinMode) {
        labelStr = isRef ? '${db.toInt()} dB SPL' : '${db.toInt()}';
      } else {
        labelStr = '${db > 0 ? '+' : ''}${db.toInt()} dB';
      }

      textPainter.text = TextSpan(
        text: labelStr,
        style: TextStyle(
          color: isRef ? AppColors.primaryLight : (isMajor ? AppColors.textSecondary : AppColors.textMuted),
          fontSize: isRef ? 10.0 : 9.0,
          fontFamily: AppTypography.monoFont,
          fontWeight: (isRef || isMajor) ? FontWeight.w600 : FontWeight.w400,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(8, y - textPainter.height - 2));
    }

    // Vertical Frequency Lines
    final allFreqs = [
      20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0,
      100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0,
      1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7000.0, 8000.0, 9000.0,
      10000.0, 20000.0
    ];

    final majorFreqs = [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];

    for (final freq in allFreqs) {
      final logF = math.log(freq) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      final isMajor = majorFreqs.contains(freq);
      final isDecade = (freq == 20.0 || freq == 100.0 || freq == 1000.0 || freq == 10000.0);

      linePaint.color = isDecade
          ? AppColors.gridDecade
          : (isMajor ? AppColors.gridSub.withValues(alpha: 0.12) : AppColors.gridSub);
      linePaint.strokeWidth = isDecade ? 1.0 : 0.6;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      if (isMajor) {
        String labelText;
        if (freq >= 1000) {
          final k = freq / 1000;
          labelText = k % 1 == 0 ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
        } else {
          labelText = '${freq.toInt()}';
        }

        textPainter.text = TextSpan(
          text: labelText,
          style: TextStyle(
            color: isDecade ? AppColors.textSecondary : AppColors.textMuted,
            fontSize: 9.5,
            fontFamily: AppTypography.monoFont,
            fontWeight: isDecade ? FontWeight.w600 : FontWeight.w400,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - textPainter.height - 4));
      }
    }
  }

  void _drawTargetCurve(Canvas canvas, Size size) {
    if (targetCurve.isEmpty) return;

    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final path = Path();
    bool first = true;

    for (final point in targetCurve) {
      if (point.x < minFreq || point.x > maxFreq) continue;

      final logF = math.log(point.x) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      double db = point.y;
      if (normalizeToTarget) {
        db = 0.0;
      }
      final yVal = (refDb + db).clamp(minDb, maxDb);

      final normalizedY = 1.0 - ((yVal - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    // Dashed line
    final pathMetrics = path.computeMetrics();
    final dashedPath = Path();
    const dashWidth = 5.0;
    const dashSpace = 4.0;

    for (final metric in pathMetrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double end = distance + dashWidth;
        dashedPath.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += dashWidth + dashSpace;
      }
    }

    final paint = Paint()
      ..color = AppColors.primaryLight.withValues(alpha: 0.75)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    canvas.drawPath(dashedPath, paint);
  }

  void _drawHeadphoneCurve(Canvas canvas, Size size) {
    if (isDualChannel && headphoneCurveL.isNotEmpty && headphoneCurveR.isNotEmpty) {
      final activeL = (matchChannels && matchedCurveL.isNotEmpty) ? matchedCurveL : headphoneCurveL;
      final activeR = (matchChannels && matchedCurveR.isNotEmpty) ? matchedCurveR : headphoneCurveR;

      // 1. Draw imbalance difference fill when not matched
      if (!matchChannels) {
        _drawImbalanceFill(canvas, size, activeL, activeR);
      }

      // 2. Draw Left Curve (Sky Blue Cyan)
      _drawSingleCurve(
        canvas,
        size,
        activeL,
        AppColors.cyan.withValues(alpha: matchChannels ? 0.90 : 0.75),
        matchChannels ? 1.5 : 1.3,
      );

      // 3. Draw Right Curve (Coral Rose)
      _drawSingleCurve(
        canvas,
        size,
        activeR,
        AppColors.rose.withValues(alpha: matchChannels ? 0.90 : 0.75),
        matchChannels ? 1.5 : 1.3,
      );
    } else if (headphoneCurve.isNotEmpty) {
      _drawSingleCurve(
        canvas,
        size,
        headphoneCurve,
        AppColors.cyan.withValues(alpha: 0.5),
        1.3,
      );
    }
  }

  void _drawImbalanceFill(Canvas canvas, Size size, List<Point> curveL, List<Point> curveR) {
    if (curveL.isEmpty || curveR.isEmpty) return;
    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final fillPath = Path();
    bool first = true;

    for (final p in curveL) {
      if (p.x < minFreq || p.x > maxFreq) continue;
      final logF = math.log(p.x) / math.ln10;
      final x = ((logF - minLog) / logRange) * size.width;
      double db = p.y;
      if (normalizeToTarget) db -= _getTargetGain(p.x);
      final yVal = (refDb + db).clamp(minDb, maxDb);
      final y = (1.0 - ((yVal - minDb) / (maxDb - minDb))) * size.height;

      if (first) {
        fillPath.moveTo(x, y);
        first = false;
      } else {
        fillPath.lineTo(x, y);
      }
    }

    for (int i = curveR.length - 1; i >= 0; i--) {
      final p = curveR[i];
      if (p.x < minFreq || p.x > maxFreq) continue;
      final logF = math.log(p.x) / math.ln10;
      final x = ((logF - minLog) / logRange) * size.width;
      double db = p.y;
      if (normalizeToTarget) db -= _getTargetGain(p.x);
      final yVal = (refDb + db).clamp(minDb, maxDb);
      final y = (1.0 - ((yVal - minDb) / (maxDb - minDb))) * size.height;
      fillPath.lineTo(x, y);
    }
    fillPath.close();

    final fillPaint = Paint()
      ..color = AppColors.rose.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);
  }

  void _drawSingleCurve(Canvas canvas, Size size, List<Point> pts, Color color, double strokeWidth) {
    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final path = Path();
    bool first = true;

    for (final point in pts) {
      if (point.x < minFreq || point.x > maxFreq) continue;

      final logF = math.log(point.x) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      double db = point.y;
      if (normalizeToTarget) {
        db -= _getTargetGain(point.x);
      }
      final yVal = (refDb + db).clamp(minDb, maxDb);

      final normalizedY = 1.0 - ((yVal - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);
  }

  void _drawResponseGlowAndCurve(Canvas canvas, Size size) {
    if (responseCurve.isEmpty) return;

    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    final curvePath = Path();
    final fillPath = Path();
    bool first = true;
    double firstX = 0;
    double lastX = size.width;

    final refNormalizedY = 1.0 - ((refDb - minDb) / (maxDb - minDb));
    final baselineY = refNormalizedY * size.height;

    for (final point in responseCurve) {
      if (point.x < minFreq || point.x > maxFreq) continue;

      final logF = math.log(point.x) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      double db = point.y;
      if (normalizeToTarget) {
        db -= _getTargetGain(point.x);
      }
      final yVal = (refDb + db).clamp(minDb, maxDb);

      final normalizedY = 1.0 - ((yVal - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;

      if (first) {
        curvePath.moveTo(x, y);
        fillPath.moveTo(x, baselineY);
        fillPath.lineTo(x, y);
        firstX = x;
        first = false;
      } else {
        curvePath.lineTo(x, y);
        fillPath.lineTo(x, y);
        lastX = x;
      }
    }

    fillPath.lineTo(lastX, baselineY);
    fillPath.lineTo(firstX, baselineY);
    fillPath.close();

    if (isBypassActive) {
      // Attenuated/dimmed curve in bypass mode (opacity 0.30)
      final strokePaint = Paint()
        ..color = AppColors.emerald.withValues(alpha: 0.30)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(curvePath, strokePaint);
    } else {
      // 1. Translucent Ambient Glow Fill
      final fillGradient = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          AppColors.emerald.withValues(alpha: 0.22),
          AppColors.emerald.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        [0.0, 0.65, 1.0],
      );

      final fillPaint = Paint()
        ..shader = fillGradient
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);

      // 2. Subtle Glow Bloom Layer for Curve
      final bloomPaint = Paint()
        ..color = AppColors.emeraldLight.withValues(alpha: 0.25)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(curvePath, bloomPaint);

      // 3. Crisp High-Definition Response Stroke
      final strokePaint = Paint()
        ..color = AppColors.emerald
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(curvePath, strokePaint);
    }
  }

  void _drawBypassOverlay(Canvas canvas, Size size) {
    final text =
        'BYPASS ACTIVE  •  LEVEL MATCHED (${autoGainOffsetDb >= 0 ? "+" : ""}${autoGainOffsetDb.toStringAsFixed(1)} dB)';
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: AppColors.amberLight,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        fontFamily: AppTypography.monoFont,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + 24;
    const pillHeight = 24.0;
    final pillX = (size.width - pillWidth) / 2;
    const pillY = 16.0;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
      const Radius.circular(12),
    );

    final bgPaint = Paint()
      ..color = AppColors.surfaceRaised.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..color = AppColors.amberLight.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(pillX + 12, pillY + (pillHeight - textPainter.height) / 2),
    );
  }

  void _drawNodes(Canvas canvas, Size size) {
    final minLog = math.log(minFreq) / math.ln10;
    final maxLog = math.log(maxFreq) / math.ln10;
    final logRange = maxLog - minLog;

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final isSelected = i == selectedNodeIndex;
      final isHovered = i == hoveredNodeIndex;

      final logF = math.log(node.freq) / math.ln10;
      final normalizedX = (logF - minLog) / logRange;
      final x = normalizedX * size.width;

      final yVal = (refDb + node.gain).clamp(minDb, maxDb);
      final normalizedY = 1.0 - ((yVal - minDb) / (maxDb - minDb));
      final y = normalizedY * size.height;

      Color nodeAccent;
      String typeLabel;
      switch (node.type) {
        case EqFilterType.lowShelf:
          nodeAccent = AppColors.cyanLight;
          typeLabel = 'LS';
          break;
        case EqFilterType.highShelf:
          nodeAccent = AppColors.amberLight;
          typeLabel = 'HS';
          break;
        case EqFilterType.peaking:
          nodeAccent = AppColors.primaryLight;
          typeLabel = 'PK';
          break;
      }

      // Q factor bandwidth guides (whiskers)
      final qSpan = (12.0 / math.max(0.3, node.q)) * 4.0;
      final whiskerPaint = Paint()
        ..color = nodeAccent.withValues(alpha: isSelected ? 0.6 : 0.25)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(x - qSpan, y), Offset(x + qSpan, y), whiskerPaint);
      canvas.drawLine(Offset(x - qSpan, y - 3), Offset(x - qSpan, y + 3), whiskerPaint);
      canvas.drawLine(Offset(x + qSpan, y - 3), Offset(x + qSpan, y + 3), whiskerPaint);

      // Outer Selection Glow with Breathing Animation
      if (isSelected) {
        final animatedHaloRadius = 10.5 + 4.5 * nodePulseValue;
        final animatedHaloOpacity = 0.16 + 0.22 * nodePulseValue;
        final haloPaint = Paint()
          ..color = nodeAccent.withValues(alpha: animatedHaloOpacity)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), animatedHaloRadius, haloPaint);
      }

      // Node Body
      final bodyRadius = isSelected ? 8.0 : (isHovered ? 7.5 : 6.0);
      final bodyPaint = Paint()
        ..color = AppColors.card
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), bodyRadius, bodyPaint);

      // Node Ring Border
      final ringPaint = Paint()
        ..color = isSelected ? Colors.white : nodeAccent
        ..strokeWidth = isSelected ? 2.5 : 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(x, y), bodyRadius, ringPaint);

      // Center Core Pip
      final pipPaint = Paint()
        ..color = isSelected ? nodeAccent : Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 2.5, pipPaint);

      // Floating Info Pill for Selected or Hovered Node
      if (isSelected || isHovered) {
        _drawNodePill(canvas, Offset(x, y), node, typeLabel, nodeAccent);
      }
    }
  }

  void _drawNodePill(
    Canvas canvas,
    Offset pos,
    EqNode node,
    String typeLabel,
    Color accent,
  ) {
    final freqStr = node.freq >= 1000
        ? '${(node.freq / 1000).toStringAsFixed(2)} kHz'
        : '${node.freq.toStringAsFixed(0)} Hz';
    final gainStr = '${node.gain >= 0 ? '+' : ''}${node.gain.toStringAsFixed(1)} dB';
    final splStr = scaleMode != YAxisScaleMode.deltaGain
        ? ' (${(refDb + node.gain).toStringAsFixed(1)} dB SPL)'
        : '';
    final qStr = 'Q ${node.q.toStringAsFixed(2)}';

    final textSpan = TextSpan(
      children: [
        TextSpan(
          text: '$typeLabel  ',
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            fontFamily: AppTypography.monoFont,
          ),
        ),
        TextSpan(
          text: '$freqStr   $gainStr$splStr   $qStr',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 10,
            fontFamily: AppTypography.monoFont,
          ),
        ),
      ],
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    const hPadding = 8.0;
    const vPadding = 4.0;
    final pillWidth = textPainter.width + hPadding * 2;
    final pillHeight = textPainter.height + vPadding * 2;

    double pillX = pos.dx - pillWidth / 2;
    double pillY = pos.dy - 30;
    if (pillY < 10) pillY = pos.dy + 16;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
      const Radius.circular(6),
    );

    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    canvas.drawRRect(
      rrect,
      Paint()..color = AppColors.surfaceRaised,
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.borderHover
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    textPainter.paint(canvas, Offset(pillX + hPadding, pillY + vPadding));
  }

  @override
  bool shouldRepaint(covariant _PrecisionCanvasPainter oldDelegate) {
    return true;
  }
}
