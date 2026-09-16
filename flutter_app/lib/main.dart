import 'package:flutter/material.dart';
import 'package:flutter_app/src/rust/frb_generated.dart';
import 'package:flutter_app/ui/layout/main_workspace.dart';
import 'package:flutter_app/ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const UltEqApp());
}

class UltEqApp extends StatelessWidget {
  const UltEqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UltEQ — Precision Audio Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        canvasColor: AppColors.bg,
        cardColor: AppColors.card,
        dividerColor: AppColors.borderSubtle,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.emerald,
          surface: AppColors.surface,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: MainWorkspace(),
        ),
      ),
    );
  }
}
