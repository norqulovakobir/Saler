import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../anim.dart';
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
/// Ilovaning birinchi ekrani — zamonaviy ilovalardagi uslub: yuqorida
/// sarlavha, o'rtada tanlanadigan ro'yxat, pastda doimiy "Davom etish" tugmasi.
/// Til bosilganda ekran darhol o'tib ketmaydi — sarlavha va tugma matni
/// o'sha tilga almashadi, foydalanuvchi natijani ko'rib turib tasdiqlaydi.
///
/// Bayroq emojilari ishlatilmaydi: Windows va ba'zi Android'larda ular
/// "UZ", "RU" qutichalari bo'lib chiqadi. O'rniga til kodi nishoni chizilgan.
class _LanguageStep extends StatefulWidget {
  final ValueChanged<AppLang> onPick;
  const _LanguageStep({required this.onPick});
  @override
  State<_LanguageStep> createState() => _LanguageStepState();
}

class _LanguageStepState extends State<_LanguageStep> {
  static const _title = {AppLang.uz: 'Tilni tanlang', AppLang.ru: 'Выберите язык', AppLang.en: 'Choose your language'};
  static const _sub = {
    AppLang.uz: "Ilovadan o'zingizga qulay tilda foydalaning",
    AppLang.ru: 'Пользуйтесь приложением на удобном языке',
    AppLang.en: 'Use the app in the language you prefer',
  };
  static const _cta = {AppLang.uz: 'Davom etish', AppLang.ru: 'Продолжить', AppLang.en: 'Continue'};
  static const _note = {
    AppLang.uz: "Keyinchalik sozlamalardan o'zgartirasiz",
    AppLang.ru: 'Позже можно изменить в настройках',
    AppLang.en: 'You can change this later in settings',
  };

  AppLang sel = AppLang.uz;
  bool busy = false;

  void _go() {
    setState(() => busy = true);
    widget.onPick(sel);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = context.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: brandOverlay(context),
      child: Scaffold(
        backgroundColor: brandBg(context),
        body: Stack(children: [
          Positioned(top: -190, left: -80, child: BrandGlow(p.accent.withValues(alpha: dark ? .16 : .45), 470)),
          Positioned(bottom: -200, right: -140, child: BrandGlow(const Color(0xFFFF8A00).withValues(alpha: dark ? .12 : .13), 430)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(children: [
                  // Yuqori qator: kichik logo va brend nomi
                  AppearIn(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                      child: Row(children: [
                        Image.asset('assets/img/logo_circle.png', width: 34, height: 34),
                        const SizedBox(width: 10),
                        Text('Rydex',
                            style: TextStyle(color: brandFg(context), fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 16),
                      children: [
                        // Sarlavha tanlangan tilda yoziladi va tanlov bilan almashadi
                        AppearIn(
                          delay: const Duration(milliseconds: 70),
                          child: AnimatedSwitcher(
                            duration: kMedium,
                            child: Text(_title[sel]!,
                                key: ValueKey(sel),
                                style: TextStyle(
                                    color: brandFg(context), fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.9, height: 1.15)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppearIn(
                          delay: const Duration(milliseconds: 120),
                          child: AnimatedSwitcher(
                            duration: kMedium,
                            child: Text(_sub[sel]!,
                                key: ValueKey(sel),
                                style: TextStyle(color: brandFgSoft(context, .55), fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500)),
                          ),
                        ),
                        const SizedBox(height: 26),
                        for (final (i, l) in AppLang.values.indexed)
                          AppearIn(
                            delay: Duration(milliseconds: 170 + i * 70),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _LangRow(lang: l, selected: sel == l, onTap: () => setState(() => sel = l)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Pastda doimiy tugma — ro'yxat uzun bo'lsa ham ko'rinib turadi
                  AppearIn(
                    delay: const Duration(milliseconds: 400),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
                      child: Column(children: [
                        FilledButton(
                          onPressed: busy ? null : _go,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          child: busy
                              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: p.onAccent))
                              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Text(_cta[sel]!, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded, size: 19),
                                ]),
                        ),
                        const SizedBox(height: 12),
                        Text(_note[sel]!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: brandFgSoft(context, .42), fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ro'yxat qatori: chapda til kodi nishoni, o'rtada nomi, o'ngda tanlov belgisi.
/// Tanlanganda sariq chegara va belgi paydo bo'ladi — sakrash yo'q.
class _LangRow extends StatelessWidget {
  static const _latin = {AppLang.uz: 'Uzbek', AppLang.ru: 'Russian', AppLang.en: 'English'};
  final AppLang lang;
  final bool selected;
  final VoidCallback onTap;
  const _LangRow({required this.lang, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = context.isDark;
    return AnimatedContainer(
      duration: kMedium,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? p.accentSoft : (dark ? p.card : Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? p.accent : brandBorder(context), width: selected ? 1.8 : 1),
        boxShadow: selected
            ? [BoxShadow(color: p.accent.withValues(alpha: .26), blurRadius: 22, offset: const Offset(0, 10))]
            : softShadow(context, y: 5, blur: 16, a: .04),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              // Til kodi nishoni — bayroq emojisiga bog'liq emas
              AnimatedContainer(
                duration: kMedium,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? p.accent : (dark ? Colors.white.withValues(alpha: .06) : const Color(0xFFF4F2EA)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(lang.name.toUpperCase(),
                    style: TextStyle(
                        color: selected ? p.onAccent : brandFgSoft(context, .6),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(L10n.names[lang]!,
                      style: TextStyle(color: brandFg(context), fontWeight: FontWeight.w800, fontSize: 16.5, letterSpacing: -.3)),
                  Text(_latin[lang]!,
                      style: TextStyle(color: brandFgSoft(context, .45), fontWeight: FontWeight.w600, fontSize: 12.5)),
                ]),
              ),
              // Radio belgisi: tanlanmaganda halqa, tanlanganda sariq nuqta
              AnimatedContainer(
                duration: kMedium,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? p.accent : Colors.transparent,
                  border: selected ? null : Border.all(color: brandFgSoft(context, .22), width: 1.8),
                ),
                child: selected ? Icon(Icons.check_rounded, size: 16, color: p.onAccent) : null,
              ),
            ]),
          ),
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

// Fon nuri endi umumiy: lib/theme.dart dagi BrandGlow
