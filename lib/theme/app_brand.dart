import 'package:flutter/material.dart';

/// Colours taken from the supplied PUST gate, bus and road artwork.
class AppBrand {
  static const maroon = Color(0xFF7D2638);
  static const cream = Color(0xFFF5F1EA);
  static const charcoal = Color(0xFF292624);
  static const stone = Color(0xFF786B5C);
  static const logo = 'assets/branding/pust-mobility-transparent.png';
  static const whiteLogo = 'assets/branding/pust-mobility-white.png';

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: maroon,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFF0B5BF) : maroon,
          onPrimary: dark ? const Color(0xFF4B0B1B) : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF512733)
              : const Color(0xFFF3DFE2),
          onPrimaryContainer: dark
              ? const Color(0xFFFFDDE3)
              : const Color(0xFF5D1929),
          secondary: dark ? const Color(0xFFD5C4AA) : stone,
          surface: dark ? const Color(0xFF252220) : const Color(0xFFFFFCF8),
          onSurface: dark ? const Color(0xFFF0E8DF) : charcoal,
          outlineVariant: dark
              ? const Color(0xFF514741)
              : const Color(0xFFE2D9CE),
        );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansBengali',
      colorScheme: scheme,
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? const Color(0xFF191716) : cream,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 44, this.decorative = false});
  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) => Image.asset(
    AppBrand.logo,
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: decorative ? null : 'PUST campus gate, bus and road logo',
    excludeFromSemantics: decorative,
  );
}

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.title = 'PUST LiveBus'});
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppBrand.cream,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const BrandLogo(size: 36, decorative: true),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}
