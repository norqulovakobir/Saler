import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import 'seller/auth_screen.dart';

/// Tanishtiruvdan keyingi tanlov: kim bo'lib foydalanasiz — Xaridor, Sotuvchi, Kuryer yoki Yuk tashuvchi.
/// Xaridor hisobsiz kiradi (buyurtma va Reelsda bir marta tasdiqlanadi). Qolganlar ro'yxatdan o'tadi yoki hisobiga kiradi.
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
  final List<String> points;
  final Color glow;
  const _Role(this.key, this.icon, this.title, this.subtitle, this.points, this.glow);
}

const _roles = <_Role>[
  _Role('buyer', Icons.shopping_bag_rounded, 'Xaridor', "Do'konlar, Reels, AI yordamchi va buyurtma",
      ["Ro'yxatdan o'tish shart emas — darhol ko'ring", 'Buyurtma yoki Reelsda bir marta tasdiqlaysiz', 'Kuryer va yuk mashinasini ham buyurtma qiling'], Color(0xFF3B6BFF)),
  _Role('seller', Icons.storefront_rounded, 'Sotuvchi', "Do'kon oching — AI sotuvchi 24/7 ishlaydi",
      ["Do'kon nomi, logo va xaritada joyi", 'AI sotuvchi (Madina) mijozlar bilan gaplashadi', 'Buyurtmalar, analitika, bildirishnomalar'], Color(0xFFFFCC00)),
  _Role('courier', Icons.two_wheeler_rounded, 'Kuryer', 'Shahar ichida buyurtma yetkazing',
      ["Onlayn bo'lsangiz buyurtma o'zi keladi", 'Xaritada marshrut va daromad hisobi', 'Piyoda, velosiped, moto yoki mashina'], Color(0xFF1F9D6A)),
  _Role('cargo', Icons.local_shipping_rounded, 'Yuk tashuvchi', 'Viloyatlar aro yuk tashing',
      ['Labo, Damas, Gazel, Isuzu, fura', "Yo'nalishlar, sig'im va narxingiz", 'Mijozlar buyurtma beradi, siz qabul qilasiz'], Color(0xFFFF8A00)),
];

class _RoleScreenState extends State<RoleScreen> {
  final _pager = PageController(viewportFraction: .86);
  int page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  _Role get role => _roles[page];

  /// Xaridor: hisobsiz ilovaga kiradi. Qolganlar: ro'yxatdan o'tish yoki kirish ekrani
  void _continue({bool login = false}) {
    final r = role;
    if (r.key == 'buyer') return _continueAs('buyer');
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthScreen(
        register: !login,
        courier: r.key != 'seller',
        cargo: r.key == 'cargo',
        onEntered: () => _continueAs(r.key),
      ),
    ));
  }

  void _continueAs(String key) {
    AppState.instance.setRole(key);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final pad = MediaQuery.of(context).padding;
    final buyer = role.key == 'buyer';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(children: [
          Positioned(top: -160, right: -120, child: _Glow(role.glow.withValues(alpha: .22), 460)),
          Positioned(bottom: -180, left: -140, child: _Glow(p.accent.withValues(alpha: .10), 420)),
          Column(children: [
            SizedBox(height: pad.top + 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(width: 34, height: 34, child: Image.asset('assets/img/logo_circle.png', fit: BoxFit.contain)),
                  const SizedBox(width: 10),
                  const Text('Saler AI', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _continueAs('buyer'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: .6)),
                    child: Text(tr("O'tkazib yuborish"), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 22),
                Text(tr("Kim bo'lib foydalanasiz?"), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.1)),
                const SizedBox(height: 6),
                Text(tr("Rolni tanlang — keyin profil orqali boshqa rolga o'tish mumkin"), style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)),
              ]),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _roles.length,
                onPageChanged: (i) => setState(() => page = i),
                itemBuilder: (_, i) => AnimatedScale(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  scale: i == page ? 1 : .93,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: i == page ? 1 : .55,
                    child: _RoleCard(
                      _roles[i],
                      selected: i == page,
                      onTap: () => i == page ? _continue() : _pager.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _roles.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  width: i == page ? 22 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: i == page ? p.accent : Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(4)),
                ),
            ]),
            const SizedBox(height: 18),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, pad.bottom + 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton(
                  onPressed: () => _continue(),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(buyer ? tr('Xarid qilishni boshlash') : '${tr("Ro'yxatdan o'tish")} · ${tr(role.title)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ]),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: buyer
                      ? Center(
                          child: Text(tr('Hisob shart emas. Buyurtma berishda email orqali tasdiqlaysiz'),
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .5), fontSize: 12, fontWeight: FontWeight.w600)))
                      : TextButton(
                          onPressed: () => _continue(login: true),
                          child: Text('${tr('Hisobim bor')} — ${tr('Kirish')}', style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final _Role role;
  final bool selected;
  final VoidCallback onTap;
  const _RoleCard(this.role, {required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: .10), Colors.white.withValues(alpha: .04)]),
              border: Border.all(color: selected ? role.glow.withValues(alpha: .7) : Colors.white.withValues(alpha: .10), width: selected ? 1.5 : 1),
              boxShadow: selected ? [BoxShadow(color: role.glow.withValues(alpha: .25), blurRadius: 40, offset: const Offset(0, 16))] : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: role.glow.withValues(alpha: .18), borderRadius: BorderRadius.circular(20), border: Border.all(color: role.glow.withValues(alpha: .35))),
                child: Icon(role.icon, color: role.glow, size: 32),
              ),
              const SizedBox(height: 18),
              Text(tr(role.title), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              const SizedBox(height: 6),
              Text(tr(role.subtitle), style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)),
              const Spacer(),
              for (final pt in role.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: role.glow.withValues(alpha: .2), shape: BoxShape.circle),
                        child: Icon(Icons.check_rounded, size: 12, color: role.glow)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr(pt), style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13, fontWeight: FontWeight.w600, height: 1.35))),
                  ]),
                ),
              const SizedBox(height: 4),
              Row(children: [
                Text(role.key == 'buyer' ? tr('Hisobsiz kirish') : tr("Ro'yxatdan o'tish"), style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 16, color: p.accent),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color c;
  final double size;
  const _Glow(this.c, this.size);
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 400), width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]))),
      );
}
