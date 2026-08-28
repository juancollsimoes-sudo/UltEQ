import 'package:flutter/material.dart';
import 'package:flutter_app/ui/canvas/logarithmic_canvas.dart';
import 'package:flutter_app/ui/controls/band_list_panel.dart';
import 'package:flutter_app/ui/controls/target_adjustments_panel.dart';
import 'package:flutter_app/ui/sidebar/sidebar.dart';
import 'package:flutter_app/models/eq_state.dart';

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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left + Center + Bottom Area
        Expanded(
          child: Column(
            children: [
              // Top Area: Left Panel + Canvas
              Expanded(
                child: Row(
                  children: [
                    // Left Side: Band List
                    Container(
                      width: 350,
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
              const TargetAdjustmentsPanel(),
            ],
          ),
        ),
        // Right side (Sidebar)
        Container(
          width: 300,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Colors.white24, width: 1)),
          ),
          child: const Sidebar(),
        ),
      ],
    );
  }
}
