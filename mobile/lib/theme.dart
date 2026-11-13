import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'oak.dart';

// Vellum and walnut: pale paper for the library, shaded bindings for chrome.
// These are chosen as a complete palette so Material's generated amber/purple
// container colours cannot leak into the reader's quiet dark surfaces.
const parchmentBackground = Color(0xFFEFE5D0);
const parchmentText = Color(0xFF3B3026);
const libraryBackground = Color(0xFF3B342C);
const libraryText = Color(0xFFEAE3D8);

ThemeData quillTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark
      ? const ColorScheme.dark(
          primary: Color(0xFFC9BBA7),
          onPrimary: Color(0xFF211B16),
          primaryContainer: Color(0xFF383129),
          onPrimaryContainer: Color(0xFFE8DFD1),
          secondary: Color(0xFFB7AEA1),
          onSecondary: Color(0xFF252019),
          secondaryContainer: Color(0xFF302A23),
          onSecondaryContainer: Color(0xFFDDD5C9),
          tertiary: Color(0xFFBCAB9F),
          onTertiary: Color(0xFF29211C),
          tertiaryContainer: Color(0xFF372C25),
          onTertiaryContainer: Color(0xFFE3D5CA),
          error: Color(0xFFDEA59E),
          onError: Color(0xFF3D201D),
          errorContainer: Color(0xFF572F2A),
          onErrorContainer: Color(0xFFF0D8D3),
          surface: libraryBackground,
          onSurface: libraryText,
          onSurfaceVariant: Color(0xFFB5AB9C),
          surfaceContainerLowest: Color(0xFF302922),
          surfaceContainerLow: Color(0xFF443A30),
          surfaceContainer: Color(0xFF493E32),
          surfaceContainerHigh: Color(0xFF514435),
          surfaceContainerHighest: Color(0xFF5C4D3C),
          outline: Color(0xFF968977),
          outlineVariant: Color(0xFF554B3E),
          inverseSurface: libraryText,
          onInverseSurface: Color(0xFF29231C),
          inversePrimary: Color(0xFF65513A),
          surfaceTint: Colors.transparent,
        )
      : const ColorScheme.light(
          primary: Color(0xFF76513A),
          onPrimary: Color(0xFFFFF7E7),
          primaryContainer: Color(0xFFDCC8A6),
          onPrimaryContainer: Color(0xFF3D2D1E),
          secondary: Color(0xFF73624C),
          onSecondary: Color(0xFFFFF7E7),
          secondaryContainer: Color(0xFFE1D2B7),
          onSecondaryContainer: Color(0xFF403426),
          tertiary: Color(0xFF76584C),
          onTertiary: Color(0xFFFFF7E7),
          tertiaryContainer: Color(0xFFE8D2BF),
          onTertiaryContainer: Color(0xFF453127),
          surface: parchmentBackground,
          onSurface: parchmentText,
          onSurfaceVariant: Color(0xFF74634F),
          surfaceContainerLowest: Color(0xFFF8F1E2),
          surfaceContainerLow: Color(0xFFF3EAD7),
          surfaceContainer: Color(0xFFE8D9BC),
          surfaceContainerHigh: Color(0xFFDCC9A6),
          surfaceContainerHighest: Color(0xFFD4BF99),
          outline: Color(0xFF917B5D),
          outlineVariant: Color(0xFFC0AB87),
          inverseSurface: Color(0xFF44382B),
          onInverseSurface: Color(0xFFF1E7D3),
          inversePrimary: Color(0xFFD9BD93),
          surfaceTint: Colors.transparent,
        );
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  final light = brightness == Brightness.light;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 0.7, space: 20),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant, width: 0.7),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: scheme.outlineVariant, width: 0.7),
      ),
    ),
    // Oak header (bars add the grain with OakPanel) with ivory text, matching the bookcase.
    appBarTheme: AppBarTheme(
      backgroundColor: light ? oak : scheme.surfaceContainerHigh,
      foregroundColor: light ? oakIvory : scheme.onSurface,
      iconTheme: IconThemeData(color: light ? oakIvory : scheme.onSurface),
      actionsIconTheme: IconThemeData(color: light ? oakIvory : scheme.onSurface),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      surfaceTintColor: Colors.transparent,
      shape: light ? null : Border(bottom: BorderSide(color: scheme.outlineVariant, width: 0.7)),
      titleTextStyle: TextStyle(
        fontFamily: 'serif',
        fontSize: 19,
        fontWeight: FontWeight.w400,
        color: light ? oakIvory : scheme.onSurface,
      ),
    ),

    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w400),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w400),
    ),
  );
}
