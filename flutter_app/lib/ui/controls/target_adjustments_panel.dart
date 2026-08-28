import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart';
import '../../models/eq_state.dart';

class TargetAdjustmentsPanel extends StatefulWidget {
  final EqState eqState;
  
  const TargetAdjustmentsPanel({super.key, required this.eqState});

  @override
  State<TargetAdjustmentsPanel> createState() => _TargetAdjustmentsPanelState();
}

class _TargetAdjustmentsPanelState extends State<TargetAdjustmentsPanel> {
  double tilt = 0.0;
  double bassBoost = 0.0;
  double earGain = 0.0;
  double treble = 0.0;
  
  String? selectedTarget;
  List<String> allTargets = [];

  @override
  void initState() {
    super.initState();
    allTargets = getTargets(dbPath: 'ulteq.db');
    widget.eqState.addListener(_onEqStateChanged);
    _updateSelectedTarget();
  }

  @override
  void dispose() {
    widget.eqState.removeListener(_onEqStateChanged);
    super.dispose();
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
      // call setState just in case we need to rebuild
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
      return false; // unknown
    }).toList();
  }

  Widget _buildKnob(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        Slider(
          value: value,
          min: -10.0,
          max: 10.0,
          onChanged: onChanged,
        ),
        Text('${value.toStringAsFixed(1)} dB', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.eqState.activeHeadphone;
    final filteredTargets = _getFilteredTargets();
    final bool hasHeadphone = active != null;

    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1E2128),
      child: Row(
        children: [
          // Target Dropdown
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Target', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              if (!hasHeadphone || filteredTargets.isEmpty)
                const Text('No valid targets', style: TextStyle(color: Colors.white38))
              else
                DropdownButton<String>(
                  value: selectedTarget,
                  dropdownColor: const Color(0xFF262B34),
                  items: filteredTargets.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => selectedTarget = val);
                      widget.eqState.loadTarget(val);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(width: 32),
          const VerticalDivider(color: Colors.white24),
          const SizedBox(width: 32),
          // Adjustments
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(child: _buildKnob('Tilt', tilt, (v) => setState(() => tilt = v))),
                Expanded(child: _buildKnob('Bass Boost', bassBoost, (v) => setState(() => bassBoost = v))),
                Expanded(child: _buildKnob('Ear Gain', earGain, (v) => setState(() => earGain = v))),
                Expanded(child: _buildKnob('Treble', treble, (v) => setState(() => treble = v))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
