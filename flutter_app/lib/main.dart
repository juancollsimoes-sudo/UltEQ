import 'package:flutter/material.dart';
import 'package:flutter_app/src/rust/frb_generated.dart';
import 'package:flutter_app/ui/canvas/logarithmic_canvas.dart';
import 'package:flutter_app/ui/layout/main_workspace.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const UltEqApp());
}

class UltEqApp extends StatelessWidget {
  const UltEqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UltEQ',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0F12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16191E),
          elevation: 0,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('UltEQ - Surgical Audio Precision')),
        body: const MainWorkspace(),
      ),
    );
  }
}
