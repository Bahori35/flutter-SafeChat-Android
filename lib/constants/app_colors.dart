import 'package:flutter/material.dart';

class AppColors {
  // Brand & Accent Colors (Modern Neo-Dark Aesthetic)
  static const Color primary = Color(0xFF6366F1); // Electric Indigo
  static const Color primaryDark = Color(0xFF4338CA);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color accent = Color(0xFF06B6D4); // Neon Cyan
  static const Color accentPurple = Color(0xFF8B5CF6); // Neon Violet
  
  // Backgrounds & Surface
  static const Color background = Color(0xFF0B0E14); // Deep Space Obsidian
  static const Color surface = Color(0xFF161B26); // Frosted Card
  static const Color surfaceLight = Color(0xFF222938); // Elevated Slate
  static const Color chatBackground = Color(0xFF0D111A); // Deep Chat Canvas
  static const Color cardBorder = Color(0x1FFFFFFF); // Subtle 12% white border
  
  // Chat Bubbles
  static const Color myMessageBubble = Color(0xFF4F46E5);
  static const Color peerMessageBubble = Color(0xFF1C2230);

  // Text Colors (High Contrast & Crisp)
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Status & Calls
  static const Color callGreen = Color(0xFF10B981);
  static const Color callRed = Color(0xFFEF4444);
  static const Color unreadBadge = Color(0xFF6366F1);
  static const Color onlineGreen = Color(0xFF22C55E);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bubbleGradient = LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient storyRingGradient = LinearGradient(
    colors: [Color(0xFFF43F5E), Color(0xFF8B5CF6), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
