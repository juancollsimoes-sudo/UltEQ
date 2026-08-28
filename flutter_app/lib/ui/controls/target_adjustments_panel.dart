import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart';

class TargetAdjustmentsPanel extends StatefulWidget {
  const TargetAdjustmentsPanel({super.key});

  @override
  State<TargetAdjustmentsPanel> createState() => _TargetAdjustmentsPanelState();
}

class _TargetAdjustmentsPanelState extends State<TargetAdjustmentsPanel> {
  double tilt = 0.0;
  double bassBoost = 0.0;
  double earGain = 0.0;
  double treble = 0.0;
  
  String? selectedTarget;
  List<String> targets = [];

  @override
  void initState() {
    super.initState();
    targets = getTargets(dbPath: 'ulteq.db');
    if (targets.isNotEmpty) {
      selectedTarget = targets.first;
    }
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
              DropdownButton<String>(
                value: selectedTarget,
                dropdownColor: const Color(0xFF262B34),
                items: targets.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => selectedTarget = val);
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
