import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api.dart';
import '../../l10n.dart';
import '../../theme.dart';

/// Ro'yxatdan o'tish va kirish ekranlarining umumiy qismlari:
/// qora brend foni, maydonlar, xato matni va 6 xonali kodni tasdiqlash qadami.

const kAuthBg = Color(0xFF0A0A0A);

/// Viloyatlar — server ro'yxati bilan bir xil (server/src/util.js REGIONS)
const kRegions = <String>[
  'Toshkent shahri', 'Toshkent viloyati', 'Andijon', "Farg'ona", 'Namangan', 'Samarqand', 'Buxoro', 'Navoiy',
  'Qashqadaryo', 'Surxondaryo', 'Jizzax', 'Sirdaryo', 'Xorazm', "Qoraqalpog'iston",
];

/// Viloyat markazlari: xarita shu joyga ochiladi
const kRegionCenter = <String, List<double>>{
  'Toshkent shahri': [41.311, 69.240], 'Toshkent viloyati': [41.040, 69.357], 'Andijon': [40.783, 72.344],
  "Farg'ona": [40.389, 71.787], 'Namangan': [40.998, 71.673], 'Samarqand': [39.655, 66.960], 'Buxoro': [39.768, 64.421],
  'Navoiy': [40.103, 65.374], 'Qashqadaryo': [38.861, 65.790], 'Surxondaryo': [37.224, 67.278], 'Jizzax': [40.116, 67.842],
  'Sirdaryo': [40.490, 68.784], 'Xorazm': [41.550, 60.631], "Qoraqalpog'iston": [42.460, 59.603],
};

/// Xatoni o'qiladigan matnga aylantiradi (ishlab chiqish rejimida asl xato ham ko'rinadi)
String authError(Object e) => e is ApiException
    ? e.message
    : kDebugMode
        ? 'Xato: $e'
        : tr("Serverga ulanib bo'lmadi. Internetni tekshiring");

class AuthGlow extends StatelessWidget {
  final Color color;
  final double size;
  const AuthGlow(this.color, this.size, {super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])),
        ),
      );
}

/// Qora brend ekrani: orqaga tugmasi, qadam ko'rsatkichi, sarlavha va kontent
class AuthShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;
  final int? step;
  final int? steps;
  final Widget? action;
  const AuthShell({super.key, required this.title, this.subtitle, required this.children, this.onBack, this.step, this.steps, this.action});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: kAuthBg,
        resizeToAvoidBottomInset: true,
        body: Stack(children: [
          Positioned(top: -150, left: -110, child: AuthGlow(p.accent.withValues(alpha: .16), 420)),
          Positioned(bottom: -170, right: -130, child: AuthGlow(const Color(0xFFFF8A00).withValues(alpha: .12), 420)),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
                child: Row(children: [
                  if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .08)),
                    )
                  else
                    const SizedBox(width: 8),
                  const Spacer(),
                  if (step != null && steps != null)
                    Text('$step / $steps', style: TextStyle(color: Colors.white.withValues(alpha: .55), fontWeight: FontWeight.w800, fontSize: 13)),
                  if (action != null) ...[const SizedBox(width: 8), action!],
                ]),
              ),
              if (step != null && steps != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: step! / steps!, minHeight: 4, color: p.accent, backgroundColor: Colors.white.withValues(alpha: .1)),
                  ),
                ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.15)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 8),
                            Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 14, height: 1.45, fontWeight: FontWeight.w500)),
                          ],
                          const SizedBox(height: 20),
                          ...children,
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Oq kartochka: maydonlar shu ichida (qora fonda o'qish qulay bo'lishi uchun)
class AuthCard extends StatelessWidget {
  final List<Widget> children;
  const AuthCard({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(color: context.p.card, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Bo'limcha sarlavhasi (DO'KON, KIRISH MA'LUMOTLARI ...)
class AuthLabel extends StatelessWidget {
  final String text;
  const AuthLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .8, color: context.p.muted)),
      );
}

class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final String? prefixText;
  final TextInputType? keyboard;
  final bool obscure;
  final Widget? suffix;
  final List<TextInputFormatter>? formatters;
  final TextInputAction action;
  final VoidCallback? onSubmit;
  final TextCapitalization caps;
  final int? maxLines;
  final bool enabled;
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.hint,
    this.prefixText,
    this.keyboard,
    this.obscure = false,
    this.suffix,
    this.formatters,
    this.action = TextInputAction.next,
    this.onSubmit,
    this.caps = TextCapitalization.none,
    this.maxLines = 1,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          obscureText: obscure,
          enabled: enabled,
          inputFormatters: formatters,
          textInputAction: action,
          textCapitalization: caps,
          maxLines: obscure ? 1 : maxLines,
          autocorrect: false,
          onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixText: prefixText,
            prefixIcon: icon == null ? null : Icon(icon, size: 20, color: context.p.muted),
            suffixIcon: suffix,
          ),
        ),
      );
}

/// Qizil xato qatori
class AuthErrorText extends StatelessWidget {
  final String? text;
  const AuthErrorText(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: p.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text!, style: TextStyle(fontSize: 13, color: p.danger, fontWeight: FontWeight.w600, height: 1.35))),
        ]),
      ),
    );
  }
}

/// Katta asosiy tugma
class AuthButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  final IconData? icon;
  const AuthButton(this.label, {super.key, this.busy = false, this.onTap, this.icon});
  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 18)],
              ]),
      );
}

/// Viloyat tanlash: bosilganda ro'yxat ochiladi
class RegionPicker extends StatelessWidget {
  final String? value;
  final String label;
  final ValueChanged<String> onPick;
  const RegionPicker({super.key, required this.value, required this.onPick, required this.label});

  static Future<String?> show(BuildContext context, {String? selected}) => showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Viloyatni tanlang'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in kRegions)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r, style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: r == selected ? Icon(Icons.check_circle_rounded, color: c.p.accent) : null,
                        onTap: () => Navigator.pop(c, r),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final r = await show(context, selected: value);
          if (r != null) onPick(r);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(Icons.map_outlined, size: 20, color: p.muted)),
          child: Text(value ?? tr('Tanlanmagan'), style: TextStyle(fontWeight: FontWeight.w600, color: value == null ? p.muted : p.text)),
        ),
      ),
    );
  }
}

/// 6 xonali kodni kiritish qadami: qayta yuborish taymeri bilan
class CodeStep extends StatefulWidget {
  final String email;

  /// Test rejimida server qaytargan kod (EmailJS sozlanmagan bo'lsa)
  final String? devCode;

  /// Kodni serverga yuboradi. Xato bo'lsa ApiException tashlaydi
  final Future<void> Function(String code) onSubmit;

  /// Kodni qayta yuboradi va test rejimidagi kodni qaytaradi
  final Future<String?> Function() onResend;
  final String buttonLabel;
  const CodeStep({super.key, required this.email, required this.onSubmit, required this.onResend, this.devCode, required this.buttonLabel});

  @override
  State<CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<CodeStep> {
  final code = TextEditingController();
  final focus = FocusNode();
  bool busy = false;
  String? error;
  String? devCode;
  int wait = 60;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    devCode = widget.devCode;
    if (devCode != null) code.text = devCode!;
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    focus.dispose();
    super.dispose();
  }

  void _startTimer([int from = 60]) {
    timer?.cancel();
    setState(() => wait = from);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => wait--);
      if (wait <= 0) t.cancel();
    });
  }

  Future<void> submit() async {
    final c = code.text.replaceAll(RegExp(r'\D'), '');
    if (c.length != 6) {
      setState(() => error = tr('6 xonali kodni kiriting'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSubmit(c);
      return; // ekran yopiladi
    } catch (e) {
      if (mounted) {
        setState(() => error = authError(e));
        if (e is ApiException && e.data['codeExpired'] == true) code.clear();
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> resend() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final d = await widget.onResend();
      if (!mounted) return;
      setState(() {
        devCode = d;
        if (d != null) code.text = d;
      });
      _startTimer();
    } catch (e) {
      if (mounted) {
        setState(() => error = authError(e));
        if (e is ApiException && e.data['retryAfter'] is num) _startTimer((e.data['retryAfter'] as num).toInt());
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AuthCard(children: [
      Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.mark_email_unread_outlined, color: p.accentText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(devCode == null ? tr('Kod yuborildi') : tr('Test kodi tayyor'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(widget.email, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      TextField(
        controller: code,
        focusNode: focus,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 14),
        decoration: InputDecoration(hintText: '– – – – – –', hintStyle: TextStyle(fontSize: 22, letterSpacing: 4, color: p.muted), counterText: ''),
        onChanged: (v) {
          if (v.replaceAll(RegExp(r'\D'), '').length == 6) submit();
        },
      ),
      const SizedBox(height: 12),
      if (devCode != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.science_outlined, size: 18, color: p.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text("${tr('Test rejimi: email xizmati sozlanmagan')} · ${tr('Kod')}: $devCode",
                    style: TextStyle(fontSize: 12.5, color: p.accentText, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      AuthErrorText(error),
      AuthButton(widget.buttonLabel, busy: busy, onTap: submit, icon: Icons.check_rounded),
      const SizedBox(height: 6),
      Center(
        child: TextButton(
          onPressed: busy || wait > 0 ? null : resend,
          child: Text(wait > 0 ? "${tr('Kodni qayta yuborish')} · ${wait}s" : tr('Kodni qayta yuborish'), style: TextStyle(fontWeight: FontWeight.w700, color: wait > 0 ? p.muted : p.accentText)),
        ),
      ),
    ]);
  }
}
