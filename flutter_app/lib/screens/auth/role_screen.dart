import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n.dart';
import '../../state.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'auth_ui.dart';
import 'register_screen.dart';

/// Tanishtiruvdan keyingi qadam: foydalanuvchi kim bo'lib faoliyat yuritishini tanlaydi.
/// Xaridor — to'g'ridan to'g'ri ilovaga kiradi (kirish talab qilinmaydi).
/// Sotuvchi, kuryer va yuk tashuvchi — ro'yxatdan o'tadi yoki hisobiga kiradi.
///
/// To'rt rol ham bir ekranda ro'yxat bo'lib turadi; tanlangani ochilib,
/// imkoniyatlari va tugmalarini ko'rsatadi. Shu sababli tugmalar har bir
/// kartochkada takrorlanmaydi va hech narsani surib izlash kerak emas.
class RoleScreen extends StatefulWidget {
  final VoidCallback onDone;
  const RoleScreen({super.key, required this.onDone});
  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _Role {
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> features;
  final Color glow;
  const _Role(this.key, this.icon, this.title, this.subtitle, this.features, this.glow);
}

class _RoleScreenState extends State<RoleScreen> {
  int index = 0;

  List<_Role> get roles => [
        _Role('buyer', Icons.shopping_bag_rounded, tr('Xaridor'), tr("Do'konlarni ko'ring, Reels'dan mahsulot tanlang va buyurtma bering"),
            [tr("Minglab do'kon va mahsulot"), tr('Reels: siz uchun tanlangan mahsulotlar'), tr('AI sotuvchi bilan suhbat')], const Color(0xFF3B82F6)),
        _Role('seller', Icons.storefront_rounded, tr('Sotuvchi'), tr("Do'kon oching — AI sotuvchi mijozlar bilan 24/7 gaplashadi"),
            [tr('AI sotuvchi va avtomatik javoblar'), tr('Buyurtmalar, analitika va hisobotlar'), tr('Obunachilarga yangi mahsulot darhol ko\'rinadi')], const Color(0xFFFEDD06)),
        _Role('courier', Icons.two_wheeler_rounded, tr('Kuryer'), tr('Buyurtmalarni yetkazing va daromad qiling'),
            [tr('Yaqin buyurtmalar avtomatik biriktiriladi'), tr('Marshrut rejasi va navigatsiya'), tr('Daromad statistikasi va AI maslahatlar')], const Color(0xFF1F9D6A)),
        _Role('cargo', Icons.local_shipping_rounded, tr('Yuk tashuvchi'), tr('Viloyatlararo yuk tashing — mijozlar sizni topadi'),
            [tr('Labo, Damas, Gazel, Isuzu, fura'), tr('Yo\'nalish va tarif bo\'yicha narx'), tr('Buyurtmalar va daromad hisobi')], const Color(0xFFFF8A00)),
      ];

  void _pickBuyer() async {
    await AppState.instance.setRolePicked();
    widget.onDone();
  }

  Future<void> _open(String role, {required bool register}) async {
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => register
          ? RegisterScreen(role: role, onDone: _finishAccount)
          : LoginScreen(role: role, onDone: _finishAccount),
    ));
  }

  void _finishAccount() async {
    await AppState.instance.setRolePicked();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final list = roles;
    final dark = context.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: authOverlay(context),
      child: Scaffold(
        backgroundColor: authBg(context),
        body: Stack(children: [
          Positioned(top: -160, left: -120, child: AuthGlow(list[index].glow.withValues(alpha: dark ? .18 : .28), 460)),
          Positioned(bottom: -180, right: -130, child: AuthGlow(const Color(0xFFFEDD06).withValues(alpha: dark ? .10 : .34), 420)),
          SafeArea(
            // Keng ekranda (web, planshet) cho'zilib ketmasligi uchun
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 10, 0),
                    child: Row(children: [
                      Image.asset('assets/img/logo_circle.png', width: 32, height: 32),
                      const SizedBox(width: 10),
                      Text('Rydex', style: TextStyle(color: authFg(context), fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                      const Spacer(),
                      const ThemeBtn(size: 38),
                      const SizedBox(width: 8),
                      const LangBtn(size: 38),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Kim bo\'lib davom etasiz?'),
                          style: TextStyle(color: authFg(context), fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.15)),
                      const SizedBox(height: 5),
                      Text(tr("Keyinchalik o'zgartirishingiz mumkin"),
                          style: TextStyle(color: authFgSoft(context, .55), fontSize: 13.5, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (_, i) => _RoleTile(
                        role: list[i],
                        selected: i == index,
                        onTap: () => setState(() => index = i),
                        onPrimary: () => list[i].key == 'buyer' ? _pickBuyer() : _open(list[i].key, register: true),
                        onLogin: list[i].key == 'buyer' ? null : () => _open(list[i].key, register: false),
                      ),
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

class _RoleTile extends StatelessWidget {
  final _Role role;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPrimary;
  final VoidCallback? onLogin;
  const _RoleTile({required this.role, required this.selected, required this.onTap, required this.onPrimary, this.onLogin});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: dark
            ? (selected ? const Color(0xFF17171C) : Colors.white.withValues(alpha: .04))
            : (selected ? Colors.white : Colors.white.withValues(alpha: .7)),
        border: Border.all(
          color: selected ? role.glow.withValues(alpha: dark ? .55 : .8) : authSurface(context, .07),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: selected ? [BoxShadow(color: role.glow.withValues(alpha: dark ? .16 : .22), blurRadius: 28, offset: const Offset(0, 12))] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: role.glow.withValues(alpha: selected ? .2 : .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(role.icon, color: role.glow, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(role.title,
                        style: TextStyle(color: authFg(context), fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                    const SizedBox(height: 2),
                    Text(role.subtitle,
                        maxLines: selected ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: authFgSoft(context, .6), fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w500)),
                  ]),
                ),
                const SizedBox(width: 8),
                // Tanlangani belgi bilan, qolganlari "ochish" strelkasi bilan
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? role.glow : Colors.transparent,
                    border: selected ? null : Border.all(color: authSurface(context, .2)),
                  ),
                  child: selected ? const Icon(Icons.check_rounded, size: 15, color: Color(0xFF111111)) : null,
                ),
              ]),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOut,
                crossFadeState: selected ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 13),
                  for (final f in role.features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.check_rounded, size: 15, color: context.isDark ? role.glow.withValues(alpha: .9) : context.p.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(f,
                              style: TextStyle(color: authFgSoft(context, .78), fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  if (onLogin != null)
                    // Yonma-yon: to'rtta rol ham bitta ekranga sig'sin
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onLogin,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: authFg(context),
                            backgroundColor: authSurface(context, .07),
                            side: BorderSide(color: authSurface(context, .18)),
                          ),
                          child: Text(tr('Kirish')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: onPrimary,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                          child: Text(tr("Ro'yxatdan o'tish")),
                        ),
                      ),
                    ])
                  else ...[
                    FilledButton(
                      onPressed: onPrimary,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      child: Text(tr('Xarid qilishni boshlash')),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(tr("Buyurtma berishda email orqali tasdiqlaysiz"),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: authFgSoft(context, .4), fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
