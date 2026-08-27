import 'package:flutter/material.dart';
import 'package:flutter_app/ui/canvas/logarithmic_canvas.dart';
import 'package:flutter_app/ui/controls/band_list_panel.dart';
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
        // Left side (Canvas + Band List)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Canvas on top
              Expanded(
                flex: 2,
                child: LogarithmicCanvas(eqState: _eqState),
              ),
              // Band List on bottom
              Expanded(
                flex: 1,
                child: BandListPanel(eqState: _eqState),
              ),
            ],
          ),
        ),
        // Right side (Sidebar)
        Container(
          width: 300, // Fixed width for sidebar
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Colors.white24, width: 1)),
          ),
          child: const Sidebar(),
        ),
      ],
    );
  }
}
