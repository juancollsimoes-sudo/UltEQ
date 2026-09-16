import 'package:flutter/material.dart';

class AppColors {
  // Deep obsidian / Raycast & Linear base
  static const Color bg = Color(0xFF08090B);
  static const Color surface = Color(0xFF0D0F14);
  static const Color surfaceRaised = Color(0xFF13161D);
  static const Color card = Color(0xFF12151C);
  static const Color cardHover = Color(0xFF181D26);
  static const Color cardSelected = Color(0xFF161A24);
  static const Color inputBg = Color(0xFF0A0C10);

  // Borders & Dividers
  static const Color borderSubtle = Color(0xFF1E222B);
  static const Color borderHover = Color(0xFF2E3544);
  static const Color borderActive = Color(0xFF6366F1);

  // Linear Indigo Accents
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color primaryGlow = Color(0x336366F1);

  // Status & Curves
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldLight = Color(0xFF34D399);
  static const Color emeraldGlow = Color(0x3310B981);

  static const Color cyan = Color(0xFF06B6D4);
  static const Color cyanLight = Color(0xFF22D3EE);

  static const Color amber = Color(0xFFF59E0B);
  static const Color amberLight = Color(0xFFFBBF24);

  static const Color rose = Color(0xFFF43F5E);
  static const Color roseLight = Color(0xFFFB7185);

  // Text
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF4B5563);
  static const Color textDisabled = Color(0xFF374151);

  // Canvas
  static const Color canvasBg = Color(0xFF07080A);
  static const Color gridDecade = Color(0x1FFFFFFF);
  static const Color gridSub = Color(0x0AFFFFFF);
  static const Color gridZero = Color(0x3DFFFFFF);
}

class AppTypography {
  static const String monoFont = 'monospace';

  static const TextStyle brand = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: AppColors.textMuted,
  );

  static const TextStyle title = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle monoSmall = TextStyle(
    fontFamily: monoFont,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
}

class AppDecorations {
  static BoxDecoration card({bool isSelected = false, bool isHovered = false}) {
    return BoxDecoration(
      color: isSelected
          ? AppColors.cardSelected
          : (isHovered ? AppColors.cardHover : AppColors.card),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isSelected
            ? AppColors.borderActive
            : (isHovered ? AppColors.borderHover : AppColors.borderSubtle),
        width: isSelected ? 1.5 : 1.0,
      ),
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: AppColors.primaryGlow,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }

  static BoxDecoration input({bool isFocused = false}) {
    return BoxDecoration(
      color: AppColors.inputBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: isFocused ? AppColors.borderActive : AppColors.borderSubtle,
        width: 1.0,
      ),
    );
  }
}
