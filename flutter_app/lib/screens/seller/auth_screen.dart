import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../auth/register_screen.dart';
import '../courier/couriers_map_screen.dart';
import '../courier/cargo_screen.dart';

/// "Sotuvchi" tabi: ikki rol — Sotuvchi va Kuryer, hamda "Kuryer yollash" xaritasi.
/// Formalar alohida to'liq ekranda ochiladi (pastki navigatsiya ko'rinmaydi).
class SellerEntry extends StatelessWidget {
  final VoidCallback onEntered;
  final VoidCallback onCourierEntered;
  const SellerEntry({super.key, required this.onEntered, required this.onCourierEntered});

  void _open(BuildContext context, bool register, {bool courier = false, bool cargo = false}) {
    final role = cargo ? 'cargo' : courier ? 'courier' : 'seller';
    final done = courier || cargo ? onCourierEntered : onEntered;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => register ? RegisterScreen(role: role, onDone: done) : LoginScreen(role: role, onDone: done),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad), children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 16),
        Row(children: [
          Expanded(child: Text(tr('Sotuvchi'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5))),
          const ThemeBtn(),
        ]),
        const SizedBox(height: 16),
        // ---- Sotuvchi ----
        _RoleCard(
          icon: Icons.storefront_rounded,
          title: tr("Sotuvchi"),
          subtitle: tr("Do'kon oching — AI sotuvchi mijozlar bilan 24/7 gaplashadi, buyurtmalarni qabul qiladi"),
          glow: const Color(0xFFFFCC00),
          onLogin: () => _open(context, false),
          onRegister: () => _open(context, true),
        ),
        const SizedBox(height: 12),
        // ---- Kuryer ----
        _RoleCard(
          icon: Icons.two_wheeler_rounded,
          title: tr('Kuryer'),
          subtitle: tr("Buyurtmalarni yetkazing va daromad qiling. Onlayn bo'lsangiz, xaridorlar sizni xaritada ko'radi"),
          glow: const Color(0xFF1F9D6A),
          onLogin: () => _open(context, false, courier: true),
          onRegister: () => _open(context, true, courier: true),
        ),
        const SizedBox(height: 12),
        // ---- Yuk tashuvchi ----
        _RoleCard(
          icon: Icons.local_shipping_rounded,
          title: tr('Yuk tashuvchi'),
          subtitle: tr("Viloyatlar aro yuk tashiysizmi? Mashinangiz, sig'imi, narxi va yo'nalishlaringizni qo'shing — mijozlar buyurtma beradi"),
          glow: const Color(0xFFFF8A00),
          onLogin: () => _open(context, false, cargo: true),
          onRegister: () => _open(context, true, cargo: true),
        ),
        const SizedBox(height: 12),
        // ---- Viloyatlararo yuk buyurtma ----
        _ActionCard(
          icon: Icons.local_shipping_rounded,
          title: tr('Yuk mashinasi buyurtma qilish'),
          subtitle: tr("Viloyatlar aro: Labo, Damas, Gazel, Isuzu, fura — tashuvchini tanlang"),
          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const CargoScreen())),
        ),
        const SizedBox(height: 12),
        // ---- Kuryer yollash ----
        _ActionCard(
          icon: Icons.two_wheeler_rounded,
          title: tr('Kuryer yollash'),
          subtitle: tr("Yaqin atrofdagi kuryerlar xaritada — qaysi biri qayerda, profili va reytingi"),
          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const CouriersMapScreen())),
        ),
      ]),
    );
  }
}

/// Amal kartasi (Kuryer yollash, Yuk buyurtma): oq kartochka, sariq belgi
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
          child: Row(children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: p.onAccent, size: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w500, height: 1.35)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ]),
        ),
      ),
    );
  }
}

/// Rol kartasi: qora banner + Kirish / Ro'yxatdan o'tish
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color glow;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  const _RoleCard({required this.icon, required this.title, required this.subtitle, required this.glow, required this.onLogin, required this.onRegister});
  @override
  Widget build(BuildContext context) => DarkBanner(
        glow: glow,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: Colors.white, size: 22)),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
          ]),
          const SizedBox(height: 10),
          Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: onLogin, child: Text(tr('Kirish')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: Colors.white.withValues(alpha: .1), foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .25))), onPressed: onRegister, child: Text(tr("Ro'yxatdan o'tish")))),
          ]),
        ]),
      );
}
