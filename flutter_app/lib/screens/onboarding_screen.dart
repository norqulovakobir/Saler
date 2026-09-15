import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';

/// Birinchi kirishdagi tanishtiruv: avval til tanlanadi, keyin shu tildagi 7 ta banner
/// (hikoyalar kabi o'zi o'tib turadi, bosib tezlatish yoki o'tkazib yuborish mumkin), oxirida hisob ekrani.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  AppLang? lang; // null: hali til tanlanmagan

  Future<void> _pick(AppLang l) async {
    await AppState.instance.setLang(l);
    if (!mounted) return;
    // Bannerlar sakramasdan chiqishi uchun oldindan yuklanadi
    await Future.wait([for (final path in _bannerPaths(l)) precacheImage(AssetImage(path), context).catchError((_) {})]);
    if (mounted) setState(() => lang = l);
  }

  Future<void> _finish() async {
    await AppState.instance.setOnboarded();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) => lang == null
      ? _LanguageStep(onPick: _pick)
      : _BannersStep(key: ValueKey(lang), lang: lang!, onChangeLang: () => setState(() => lang = null), onDone: _finish);
}

const _bannerCount = 7;
List<String> _bannerPaths(AppLang l) => [for (var i = 1; i <= _bannerCount; i++) 'assets/onboarding/${l.name}/${i.toString().padLeft(2, '0')}.webp'];

/// Bannerlarning sariq foni: rasm atrofidagi joy ham shu rangda bo'ladi
const _bannerBg = Color(0xFFFDD528);

// ---------- 1-qadam: til ----------
class _LanguageStep extends StatelessWidget {
  final ValueChanged<AppLang> onPick;
  const _LanguageStep({required this.onPick});

  static const _subtitle = {AppLang.uz: "O'zingizga mos tilni tanlang", AppLang.ru: 'Выберите удобный язык', AppLang.en: 'Choose your language'};

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(children: [
          Positioned(top: -150, left: -110, child: _Glow(p.accent.withValues(alpha: .16), 420)),
          Positioned(bottom: -170, right: -130, child: _Glow(const Color(0xFFFF8A00).withValues(alpha: .12), 420)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: p.accent.withValues(alpha: .35), blurRadius: 44, offset: const Offset(0, 16))]),
                        child: Image.asset('assets/img/logo_circle.png', fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text('Saler AI', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                    const SizedBox(height: 6),
                    // Uch tilda: foydalanuvchi hali tilni tanlamagan
                    Text('${_subtitle[AppLang.uz]}\n${_subtitle[AppLang.ru]} · ${_subtitle[AppLang.en]}',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 14, height: 1.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 28),
                    for (final l in AppLang.values) ...[
                      _LangCard(l, onTap: () => onPick(l)),
                      const SizedBox(height: 10),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LangCard extends StatefulWidget {
  final AppLang lang;
  final VoidCallback onTap;
  const _LangCard(this.lang, {required this.onTap});
  @override
  State<_LangCard> createState() => _LangCardState();
}

class _LangCardState extends State<_LangCard> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: Colors.white.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy
            ? null
            : () {
                setState(() => busy = true);
                widget.onTap();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .12))),
          child: Row(children: [
            Text(L10n.flags[widget.lang]!, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(child: Text(L10n.names[widget.lang]!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
            busy
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                : Icon(Icons.arrow_forward_rounded, color: p.accent),
          ]),
        ),
      ),
    );
  }
}

// ---------- 2-qadam: bannerlar ----------
class _BannersStep extends StatefulWidget {
  final AppLang lang;
  final VoidCallback onChangeLang;
  final VoidCallback onDone;
  const _BannersStep({super.key, required this.lang, required this.onChangeLang, required this.onDone});
  @override
  State<_BannersStep> createState() => _BannersStepState();
}

class _BannersStepState extends State<_BannersStep> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _perPage = Duration(seconds: 4);
  final _pager = PageController();
  late final AnimationController _timer = AnimationController(vsync: this, duration: _perPage)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next(auto: true);
    });
  int page = 0;
  bool done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.dispose();
    _pager.dispose();
    super.dispose();
  }

  // Ilova orqaga o'tsa vaqt to'xtaydi, qaytganda davom etadi
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _timer.forward();
    } else {
      _timer.stop();
    }
  }

  void _go(int i) {
    if (i < 0 || i >= _bannerCount || done) return;
    _pager.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _next({bool auto = false}) {
    if (page >= _bannerCount - 1) {
      _finish();
    } else {
      _go(page + 1);
    }
  }

  void _finish() {
    if (done) return;
    done = true;
    _timer.stop();
    widget.onDone();
  }

  void _onPage(int i) {
    setState(() => page = i);
    _timer
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final last = page == _bannerCount - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bannerBg,
        body: Stack(fit: StackFit.expand, children: [
          // Bannerlar: yonga surish mumkin; bosilganda o'ng tomon keyingisi, chap tomon oldingisi; ushlab turilsa vaqt to'xtaydi
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => d.localPosition.dx < MediaQuery.of(context).size.width * .3 ? _go(page - 1) : _next(),
            onLongPressStart: (_) => _timer.stop(),
            onLongPressEnd: (_) => _timer.forward(),
            child: PageView.builder(
              controller: _pager,
              onPageChanged: _onPage,
              itemCount: _bannerCount,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(top: pad.top + 22, bottom: pad.bottom + 96),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Image.asset(_bannerPaths(widget.lang)[i], fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
            ),
          ),
          // Hikoyalar uslubidagi vaqt chiziqlari
          Positioned(
            top: pad.top + 8,
            left: 14,
            right: 14,
            child: AnimatedBuilder(
              animation: _timer,
              builder: (_, __) => Row(children: [
                for (var i = 0; i < _bannerCount; i++)
                  Expanded(
                    child: Container(
                      height: 3.5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .18), borderRadius: BorderRadius.circular(2)),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < page ? 1 : i == page ? _timer.value : 0,
                        child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF14161A), borderRadius: BorderRadius.circular(2))),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          // Yuqori tugmalar: tilni o'zgartirish va o'tkazib yuborish
          Positioned(
            top: pad.top + 20,
            left: 12,
            right: 12,
            child: Row(children: [
              _Pill(icon: Icons.translate_rounded, label: L10n.names[widget.lang]!, onTap: widget.onChangeLang),
              const Spacer(),
              _Pill(label: tr("O'tkazib yuborish"), icon: Icons.fast_forward_rounded, trailing: true, onTap: _finish),
            ]),
          ),
          // Pastki tugma: keyingisi yoki boshlash
          Positioned(
            left: 20,
            right: 20,
            bottom: pad.bottom + 24,
            child: Row(children: [
              Text('${page + 1} / $_bannerCount', style: TextStyle(color: Colors.black.withValues(alpha: .55), fontWeight: FontWeight.w800, fontSize: 13)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _next(),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF14161A), foregroundColor: Colors.white, minimumSize: const Size(0, 50), padding: const EdgeInsets.symmetric(horizontal: 22)),
                icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 18),
                label: Text(last ? tr('Boshlash') : tr('Keyingisi'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool trailing;
  const _Pill({required this.icon, required this.label, required this.onTap, this.trailing = false});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (!trailing) ...[Icon(icon, size: 16, color: const Color(0xFF14161A)), const SizedBox(width: 6)],
              Text(label, style: const TextStyle(color: Color(0xFF14161A), fontWeight: FontWeight.w800, fontSize: 13)),
              if (trailing) ...[const SizedBox(width: 6), Icon(icon, size: 16, color: const Color(0xFF14161A))],
            ]),
          ),
        ),
      );
}

class _Glow extends StatelessWidget {
  final Color c;
  final double size;
  const _Glow(this.c, this.size);
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]))),
      );
}
