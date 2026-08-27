import 'package:flutter/material.dart';
import 'package:flutter_app/ui/canvas/logarithmic_canvas.dart';
import 'package:flutter_app/ui/controls/eq_panel.dart';
import 'package:flutter_app/ui/sidebar/sidebar.dart';

class MainWorkspace extends StatelessWidget {
  const MainWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left side (Canvas + EQ Panel)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Canvas on top
              const Expanded(
                flex: 2,
                child: LogarithmicCanvas(),
              ),
              // EQ Panel on bottom
              const Expanded(
                flex: 1,
                child: EqPanel(),
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
