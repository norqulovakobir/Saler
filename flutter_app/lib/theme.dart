import 'package:flutter/material.dart';

/// Dizayn tizimi: yumshoq premium (A yo'nalish)
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg, card, text, muted, accent, accentSoft, dark, onDark, success, successSoft, border, danger, imageA, imageB;
  /// Sariq fon ustidagi matn/ikonka (qora) va oq fon ustidagi urg'u matni (to'q oltin)
  final Color onAccent, accentText;
  const AppPalette({
    required this.bg,
    required this.card,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.dark,
    required this.onDark,
    required this.success,
    required this.successSoft,
    required this.border,
    required this.danger,
    required this.imageA,
    required this.imageB,
    this.onAccent = const Color(0xFF111111),
    this.accentText = const Color(0xFF8C6A00),
  });

  /// Brend sarig'i — ilova ikonkasidagi rang bilan bir xil (#FEDD06).
  static const brand = Color(0xFFFEDD06);

  static const light = AppPalette(
    bg: Color(0xFFF6F5F2),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF14161A),
    muted: Color(0xFF6B7280),
    accent: brand,
    accentSoft: Color(0xFFFFF6C2),
    // Oq fonda o'qilishi uchun to'q oltin (sariqning o'zi kontrastga yetmaydi)
    accentText: Color(0xFF7A5E00),
    dark: Color(0xFF14161A),
    onDark: Color(0xFFFFFFFF),
    success: Color(0xFF1F9D6A),
    successSoft: Color(0xFFE6F6EE),
    border: Color(0x0F14161A),
    danger: Color(0xFFE5484D),
    imageA: Color(0xFFE8ECF3),
    imageB: Color(0xFFF7F8FA),
  );

  static const dark_ = AppPalette(
    bg: Color(0xFF121417),
    card: Color(0xFF1C1F25),
    text: Color(0xFFF3F4F6),
    muted: Color(0xFF8A909C),
    accent: Color(0xFFFFE02E),
    accentSoft: Color(0x33FFE02E),
    accentText: Color(0xFFFFE02E),
    dark: Color(0xFF1C1F25),
    onDark: Color(0xFFFFFFFF),
    success: Color(0xFF34C58A),
    successSoft: Color(0x2634C58A),
    border: Color(0xFF262A33),
    danger: Color(0xFFFF6B70),
    imageA: Color(0xFF232833),
    imageB: Color(0xFF1C1F25),
  );

  @override
  AppPalette copyWith() => this;
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => this;
}

extension PaletteX on BuildContext {
  AppPalette get p => Theme.of(this).extension<AppPalette>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Kartochka soyasi
List<BoxShadow> softShadow(BuildContext c, {double y = 8, double blur = 24, double a = .05}) =>
    c.isDark ? const [] : [BoxShadow(color: const Color(0xFF14161A).withValues(alpha: a), offset: Offset(0, y), blurRadius: blur)];

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? AppPalette.dark_ : AppPalette.light;
  final base = ThemeData(brightness: b, useMaterial3: true);
  final text = base.textTheme.apply(fontFamily: 'Manrope').apply(bodyColor: p.text, displayColor: p.text);
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: p.accent, brightness: b).copyWith(primary: p.accent, onPrimary: p.onAccent, surface: p.card, onSurface: p.text, error: p.danger),
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'Manrope', fontSize: 20, fontWeight: FontWeight.w800, color: p.text, letterSpacing: -.4)),
    cardTheme: CardThemeData(
        color: p.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: b == Brightness.dark ? BorderSide(color: p.border) : BorderSide.none)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w500),
      labelStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.accent, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      // Asosiy tugma: Yandex uslubida sariq fon, qora matn
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shadowColor: p.accent.withValues(alpha: .45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w800, fontSize: 15),
      ).copyWith(elevation: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? 0 : (b == Brightness.dark ? 0 : 8))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.card,
        minimumSize: const Size.fromHeight(54),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.accentText, textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700))),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.dark,
      labelStyle: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 12, color: p.text),
      secondaryLabelStyle: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 12, color: p.onDark),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      showCheckmark: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.bg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), dragHandleColor: p.border),
    dialogTheme: DialogThemeData(backgroundColor: p.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    dividerColor: p.border,
    snackBarTheme: SnackBarThemeData(
        backgroundColor: p.dark,
        contentTextStyle: TextStyle(color: p.onDark, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    // Quyidagilar berilmasa Material o'zining binafsha/ko'k ranglarini ishlatadi
    // va brenddan chiqib ketadi.
    iconTheme: IconThemeData(color: p.text),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.accentSoft, circularTrackColor: Colors.transparent),
    textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent, selectionColor: p.accent.withValues(alpha: .28), selectionHandleColor: p.accent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.border),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : Colors.transparent),
      checkColor: WidgetStateProperty.all(p.onAccent),
      side: BorderSide(color: p.muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.muted),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: p.accent, thumbColor: p.accent, inactiveTrackColor: p.border),
    listTileTheme: ListTileThemeData(
      iconColor: p.muted,
      textColor: p.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(fontFamily: 'Manrope', fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
      subtitleTextStyle: TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.w500, color: p.muted),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.dark, borderRadius: BorderRadius.circular(10)),
      textStyle: TextStyle(fontFamily: 'Manrope', fontSize: 12, fontWeight: FontWeight.w600, color: p.onDark),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
      textStyle: TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(6),
      thumbColor: WidgetStateProperty.all(p.muted.withValues(alpha: .45)),
    ),
  );
}
