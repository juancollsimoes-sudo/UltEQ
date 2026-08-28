import 'package:flutter/material.dart';
import 'package:flutter_app/ui/canvas/logarithmic_canvas.dart';
import 'package:flutter_app/ui/controls/band_list_panel.dart';
import 'package:flutter_app/ui/controls/target_adjustments_panel.dart';
import 'package:flutter_app/ui/sidebar/sidebar.dart';
import 'package:flutter_app/models/eq_state.dart';
import 'package:flutter_app/src/rust/api/simple.dart';

class MainWorkspace extends StatefulWidget {
  const MainWorkspace({super.key});

  @override
  State<MainWorkspace> createState() => _MainWorkspaceState();
}

class _MainWorkspaceState extends State<MainWorkspace> {
  late final EqState _eqState;

  @override
  void initState() {
    super.initState();
    _eqState = EqState();
  }

  @override
  void dispose() {
    _eqState.dispose();
    super.dispose();
  }

  Future<void> _showAudioConfigDialog() async {
    final devices = getAudioDevices();
    String? selected = devices.isNotEmpty ? devices.first : null;

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Audio Config'),
              content: DropdownButton<String>(
                value: selected,
                isExpanded: true,
                items: devices.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (val) {
                  setState(() => selected = val);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('Select'),
                ),
              ],
            );
          }
        );
      }
    );

    if (result != null) {
      _eqState.selectedOutputDevice = result;
      _eqState.triggerUpdate();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected Audio Device: $result')));
    }
  }

  void _applyEq() {
    if (_eqState.selectedOutputDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an Audio Device first!')));
      return;
    }
    final filters = _eqState.nodes.map((n) {
      FilterType t = FilterType.peaking;
      if (n.type == EqFilterType.lowShelf) t = FilterType.lowShelf;
      if (n.type == EqFilterType.highShelf) t = FilterType.highShelf;
      return ActiveFilter(filterType: t, freq: n.freq, gain: n.gain, q: n.q);
    }).toList();
    applyEqToDevice(deviceName: _eqState.selectedOutputDevice!, filters: filters);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('EQ Applied!')));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left + Center + Bottom Area
        Expanded(
          child: Column(
            children: [
              Container(
                height: 60,
                color: const Color(0xFF16191E),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListenableBuilder(
                  listenable: _eqState,
                  builder: (context, _) {
                    return Row(
                      children: [
                        const Text('UltEQ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyan)),
                        const Spacer(),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.settings),
                          label: const Text('Audio Config'),
                          onPressed: _showAudioConfigDialog,
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('AutoEq'),
                          onPressed: _eqState.headphoneCurve.isNotEmpty && _eqState.targetCurve.isNotEmpty ? () {
                            final filters = generateAutoeq(headphone: _eqState.headphoneCurve, target: _eqState.targetCurve, bands: BigInt.from(10));
                            _eqState.nodes.clear();
                            for (final f in filters) {
                              _eqState.nodes.add(EqNode(freq: f.freq, gain: f.gain, q: f.q, type: EqFilterType.peaking));
                            }
                            _eqState.triggerUpdate();
                          } : null,
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Apply EQ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _applyEq,
                        ),
                      ],
                    );
                  }
                ),
              ),
              // Top Area: Left Panel + Canvas
              Expanded(
                child: Row(
                  children: [
                    // Left Side: Band List
                    Container(
                      width: 280,
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.white24, width: 1)),
                      ),
                      child: BandListPanel(eqState: _eqState),
                    ),
                    // Center: Canvas
                    Expanded(
                      child: LogarithmicCanvas(eqState: _eqState),
                    ),
                  ],
                ),
              ),
              // Bottom: Target Adjustments Panel
              TargetAdjustmentsPanel(eqState: _eqState),
            ],
          ),
        ),
        // Right side (Sidebar)
        Container(
          width: 300,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Colors.white24, width: 1)),
          ),
          child: Sidebar(eqState: _eqState),
        ),
      ],
    );
  }
}
