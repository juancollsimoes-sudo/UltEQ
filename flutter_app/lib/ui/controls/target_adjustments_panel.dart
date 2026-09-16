import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart';
import '../../models/eq_state.dart';
import '../theme/app_theme.dart';

class TargetAdjustmentsPanel extends StatefulWidget {
  final EqState eqState;

  const TargetAdjustmentsPanel({super.key, required this.eqState});

  @override
  State<TargetAdjustmentsPanel> createState() => _TargetAdjustmentsPanelState();
}

class _TargetAdjustmentsPanelState extends State<TargetAdjustmentsPanel> with SingleTickerProviderStateMixin {
  String? selectedTarget;
  List<String> allTargets = [];

  late final AnimationController _resetAnimController;

  @override
  void initState() {
    super.initState();
    allTargets = getTargets(dbPath: 'ulteq.db');
    widget.eqState.addListener(_onEqStateChanged);
    _resetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _updateSelectedTarget();
  }

  @override
  void dispose() {
    widget.eqState.removeListener(_onEqStateChanged);
    _resetAnimController.dispose();
    super.dispose();
  }

  void _animateReset() {
    final startTilt = widget.eqState.tilt;
    final startBass = widget.eqState.bass;
    final startEarGain = widget.eqState.earGain;
    final startTreble = widget.eqState.treble;

    final anim = CurvedAnimation(parent: _resetAnimController, curve: Curves.easeOutCubic);
    _resetAnimController.reset();

    void listener() {
      final t = anim.value;
      widget.eqState.updateModifiers(
        newTilt: startTilt * (1.0 - t),
        newBass: startBass * (1.0 - t),
        newEarGain: startEarGain * (1.0 - t),
        newTreble: startTreble * (1.0 - t),
      );
    }

    _resetAnimController.addListener(listener);
    _resetAnimController.forward().whenComplete(() {
      _resetAnimController.removeListener(listener);
      widget.eqState.resetModifiers();
    });
  }

  void _onEqStateChanged() {
    _updateSelectedTarget();
  }

  void _updateSelectedTarget() {
    final filtered = _getFilteredTargets();
    if (filtered.isEmpty) {
      if (selectedTarget != null) {
        setState(() => selectedTarget = null);
        widget.eqState.targetCurve = [];
      }
      return;
    }

    if (selectedTarget == null || !filtered.contains(selectedTarget)) {
      setState(() {
        selectedTarget = filtered.first;
      });
      widget.eqState.loadTarget(selectedTarget!);
    } else {
      setState(() {});
    }
  }

  List<String> _getFilteredTargets() {
    final active = widget.eqState.activeHeadphone;
    if (active == null || active.formFactor == null) return [];

    final ff = active.formFactor!.toLowerCase();

    return allTargets.where((t) {
      final targetLower = t.toLowerCase();
      if (ff.contains('in-ear') || ff == 'ie') {
        return targetLower.contains('in-ear');
      } else if (ff.contains('over-ear') || ff == 'oe') {
        return targetLower.contains('over-ear');
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.eqState.activeHeadphone;
    final filteredTargets = _getFilteredTargets();
    final bool hasHeadphone = active != null;

    return Container(
      height: 74,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Target Preset Selector
                SizedBox(
                  width: 190,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Text('TARGET PRESET', style: AppTypography.sectionHeader),
                          const Spacer(),
                          if (widget.eqState.tilt != 0.0 ||
                              widget.eqState.bass != 0.0 ||
                              widget.eqState.earGain != 0.0 ||
                              widget.eqState.treble != 0.0)
                            InkWell(
                              onTap: _animateReset,
                              child: const Text(
                                'Reset',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (!hasHeadphone || filteredTargets.isEmpty)
                        Container(
                          height: 30,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: const Text(
                            'Load headphone first',
                            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedTarget,
                              isExpanded: true,
                              dropdownColor: AppColors.surfaceRaised,
                              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
                              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                              items: filteredTargets.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(t, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => selectedTarget = val);
                                  widget.eqState.loadTarget(val);
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 14),
                Container(width: 1, height: 38, color: AppColors.borderSubtle),
                const SizedBox(width: 14),

                // Sliders Row
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildLinearSlider(
                          label: 'TILT',
                          value: widget.eqState.tilt,
                          min: -5.0,
                          max: 5.0,
                          onChanged: (v) => widget.eqState.updateModifiers(newTilt: v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildLinearSlider(
                          label: 'BASS',
                          value: widget.eqState.bass,
                          min: -10.0,
                          max: 10.0,
                          accentColor: AppColors.cyanLight,
                          onChanged: (v) => widget.eqState.updateModifiers(newBass: v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildLinearSlider(
                          label: 'EAR GAIN',
                          value: widget.eqState.earGain,
                          min: -6.0,
                          max: 6.0,
                          accentColor: AppColors.primaryLight,
                          onChanged: (v) => widget.eqState.updateModifiers(newEarGain: v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildLinearSlider(
                          label: 'TREBLE',
                          value: widget.eqState.treble,
                          min: -10.0,
                          max: 10.0,
                          accentColor: AppColors.amberLight,
                          onChanged: (v) => widget.eqState.updateModifiers(newTreble: v),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          if (constraints.maxWidth < 660) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: 660, child: content),
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildLinearSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    Color accentColor = AppColors.primaryLight,
    required ValueChanged<double> onChanged,
  }) {
    final isNeutral = value.abs() < 0.05;
    final valStr = '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} dB';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.sectionHeader,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onDoubleTap: () => onChanged(0.0),
                child: Text(
                  valStr,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFont,
                    fontSize: 9.5,
                    fontWeight: isNeutral ? FontWeight.w400 : FontWeight.w600,
                    color: isNeutral ? AppColors.textMuted : accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2.0,
            activeTrackColor: accentColor,
            inactiveTrackColor: AppColors.borderSubtle,
            thumbColor: isNeutral ? AppColors.textSecondary : Colors.white,
            overlayColor: accentColor.withValues(alpha: 0.15),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0, elevation: 1),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
