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
  late final PageController pager = PageController(viewportFraction: .86);
  int index = 0;

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  List<_Role> get roles => [
        _Role('buyer', Icons.shopping_bag_rounded, tr('Xaridor'), tr("Do'konlarni ko'ring, Reels'dan mahsulot tanlang va buyurtma bering"),
            [tr("Minglab do'kon va mahsulot"), tr('Reels: siz uchun tanlangan mahsulotlar'), tr('AI sotuvchi bilan suhbat')], const Color(0xFF3B82F6)),
        _Role('seller', Icons.storefront_rounded, tr('Sotuvchi'), tr("Do'kon oching — AI sotuvchi mijozlar bilan 24/7 gaplashadi"),
            [tr('AI sotuvchi va avtomatik javoblar'), tr('Buyurtmalar, analitika va hisobotlar'), tr('Obunachilarga yangi mahsulot darhol ko\'rinadi')], const Color(0xFFFFCC00)),
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
    final p = context.p;
    final list = roles;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: kAuthBg,
        body: Stack(children: [
          Positioned(top: -160, left: -120, child: AuthGlow(list[index].glow.withValues(alpha: .18), 460)),
          Positioned(bottom: -180, right: -130, child: AuthGlow(const Color(0xFFFF8A00).withValues(alpha: .10), 420)),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                child: Row(children: [
                  Image.asset('assets/img/logo_circle.png', width: 34, height: 34),
                  const SizedBox(width: 10),
                  const Text('Rydex', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                  const Spacer(),
                  const LangBtn(),
                ]),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Kim bo\'lib davom etasiz?'), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.15)),
                  const SizedBox(height: 6),
                  Text(tr("Yonga suring va o'zingizga mos bo'limni tanlang"), style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 14, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: PageView.builder(
                  controller: pager,
                  itemCount: list.length,
                  onPageChanged: (i) => setState(() => index = i),
                  itemBuilder: (_, i) => AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: i == index ? 4 : 18),
                    child: _RoleCard(
                      role: list[i],
                      onPrimary: () => list[i].key == 'buyer' ? _pickBuyer() : _open(list[i].key, register: true),
                      onLogin: list[i].key == 'buyer' ? null : () => _open(list[i].key, register: false),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < list.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == index ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(color: i == index ? p.accent : Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(4)),
                  ),
              ]),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _pickBuyer,
                child: Text(tr("Hozircha shunchaki ko'rib chiqaman"), style: TextStyle(color: Colors.white.withValues(alpha: .65), fontWeight: FontWeight.w700)),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 2 : 10),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final _Role role;
  final VoidCallback onPrimary;
  final VoidCallback? onLogin;
  const _RoleCard({required this.role, required this.onPrimary, this.onLogin});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final buyer = onLogin == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF16161A),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: [BoxShadow(color: role.glow.withValues(alpha: .18), blurRadius: 40, offset: const Offset(0, 18))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(color: role.glow.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
          child: Icon(role.icon, color: role.glow, size: 32),
        ),
        const SizedBox(height: 16),
        Text(role.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5)),
        const SizedBox(height: 6),
        Text(role.subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .66), fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500)),
        const SizedBox(height: 16),
        for (final f in role.features)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_circle_rounded, size: 17, color: role.glow.withValues(alpha: .9)),
              const SizedBox(width: 9),
              Expanded(child: Text(f, style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 13, height: 1.35, fontWeight: FontWeight.w600))),
            ]),
          ),
        const Spacer(),
        FilledButton(
          onPressed: onPrimary,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: Text(buyer ? tr('Xarid qilishni boshlash') : tr("Ro'yxatdan o'tish")),
        ),
        if (onLogin != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onLogin,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .07),
              side: BorderSide(color: Colors.white.withValues(alpha: .18)),
            ),
            child: Text(tr('Hisobim bor — Kirish')),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Text(tr("Buyurtma berishda email orqali tasdiqlaysiz"), style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}
