import 'package:flutter/material.dart';
import '../../api.dart';
import '../../l10n.dart';
import '../../models.dart';
import '../../state.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../courier/couriers_map_screen.dart';
import '../courier/cargo_screen.dart';

/// "Sotuvchi" tabi: ikki rol — Sotuvchi va Kuryer, hamda "Kuryer yollash" xaritasi.
/// Formalar alohida to'liq ekranda ochiladi (pastki navigatsiya ko'rinmaydi).
class SellerEntry extends StatelessWidget {
  final VoidCallback onEntered;
  final VoidCallback onCourierEntered;
  const SellerEntry({super.key, required this.onEntered, required this.onCourierEntered});

  void _open(BuildContext context, bool register, {bool courier = false, bool cargo = false}) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => AuthScreen(register: register, courier: courier || cargo, cargo: cargo, onEntered: courier || cargo ? onCourierEntered : onEntered)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
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
        const SizedBox(height: 12),
        Center(child: Text(tr("Do'kon Telegram botda ham ochilishi mumkin"), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))),
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

/// Kirish / Ro'yxatdan o'tish — to'liq ekran (pastki navigatsiyasiz)
class AuthScreen extends StatefulWidget {
  final bool register;
  /// true — kuryer akkaunti (ism, telefon, email, transport), false — do'kon
  final bool courier;
  /// true — yuk tashuvchi (viloyatlararo): mashina turi, sig'im, narx, viloyatlar
  final bool cargo;
  final VoidCallback onEntered;
  const AuthScreen({super.key, required this.register, required this.onEntered, this.courier = false, this.cargo = false});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final f = <String, TextEditingController>{
    for (final k in ['name', 'ownerName', 'sellerName', 'phone', 'email', 'login', 'password']) k: TextEditingController()
  };
  String vehicle = 'moto';
  String vehicleType = 'labo';
  final regions = <String>[];
  List<String> allRegions = const ['Toshkent sh.', 'Toshkent vil.', 'Andijon', 'Buxoro', "Farg'ona", 'Jizzax', 'Xorazm', 'Namangan', 'Navoiy', 'Qashqadaryo', 'Samarqand', 'Sirdaryo', 'Surxondaryo', "Qoraqalpog'iston"];
  final capacity = TextEditingController();
  final basePrice = TextEditingController();
  final perKm = TextEditingController();
  bool busy = false;
  bool showPass = false;
  String? error;

  bool get register => widget.register;
  bool get courier => widget.courier;
  bool get cargo => widget.cargo;

  @override
  void dispose() {
    for (final c in f.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> go() async {
    FocusScope.of(context).unfocus();
    final need = !register ? ['login', 'password'] : courier ? ['name', 'phone', 'login', 'password'] : ['name', 'sellerName', 'phone', 'login', 'password'];
    final missing = need.where((k) => f[k]!.text.trim().isEmpty);
    if (missing.isNotEmpty) {
      setState(() => error = tr("Barcha maydonlarni to'ldiring"));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register && cargo && regions.isEmpty) {
        setState(() => error = tr('Kamida bitta viloyatni tanlang'));
        return;
      }
      final body = {
        for (final e in f.entries) e.key: e.value.text.trim(),
        if (courier) 'vehicle': vehicle,
        if (cargo) 'type': 'cargo',
        if (cargo) 'vehicleType': vehicleType,
        if (cargo) 'capacityKg': int.tryParse(capacity.text) ?? 0,
        if (cargo) 'basePrice': int.tryParse(basePrice.text) ?? 0,
        if (cargo) 'pricePerKm': int.tryParse(perKm.text) ?? 0,
        if (cargo) 'regions': regions,
      };
      if (courier) {
        final r = await Api.instance.post(register ? '/api/courier/register' : '/api/courier/login', body);
        AppState.instance.courier = Courier.fromJson(r['courier']);
        AppState.instance.refresh();
      } else {
        final r = await Api.instance.post(register ? '/api/seller/register' : '/api/seller/login', body);
        AppState.instance.sellerShop = Shop.fromJson(r['shop']);
        AppState.instance.refreshBadges();
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onEntered();
      return;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  void _switch() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => AuthScreen(register: !register, courier: courier, cargo: cargo, onEntered: widget.onEntered),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 220),
    ));
  }

  Widget field(String key, String label, IconData icon, {bool pass = false, TextInputType? type, String? hint, TextInputAction action = TextInputAction.next}) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: f[key],
        obscureText: pass && !showPass,
        keyboardType: type,
        textInputAction: action,
        onSubmitted: action == TextInputAction.done ? (_) => go() : null,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20, color: p.muted),
          suffixIcon: pass
              ? IconButton(onPressed: () => setState(() => showPass = !showPass), icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: p.muted))
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(children: [IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop())]),
            const SizedBox(height: 22),
            Text(cargo ? (register ? tr('Yuk tashuvchi bo\'ling') : tr('Yuk tashuvchi kirishi')) : courier ? (register ? tr('Kuryer bo\'ling') : tr('Kuryer kirishi')) : register ? tr("Do'kon oching") : tr('Xush kelibsiz!'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.1)),
            const SizedBox(height: 6),
            Text(
              courier
                  ? (register ? tr("Ma'lumotlaringizni kiriting — onlayn bo'lgach, xaridorlar sizni xaritada ko'radi.") : tr('Kuryer paneliga kirish uchun login va parolingizni kiriting.'))
                  : register
                      ? tr("Bir daqiqada do'kon yarating — AI sotuvchi darhol ishga tushadi.")
                      : tr('Sotuvchi paneliga kirish uchun login va parolingizni kiriting.'),
              style: TextStyle(fontSize: 14, color: p.muted, fontWeight: FontWeight.w500, height: 1.45),
            ),
            const SizedBox(height: 24),
            if (register && cargo) ...[
              _Label(tr('YUK TASHUVCHI')),
              field('name', tr('Ism-sharif'), Icons.person_outline_rounded),
              field('phone', tr('Telefon'), Icons.phone_outlined, type: TextInputType.phone, hint: '+998 90 123 45 67'),
              field('email', 'Email', Icons.alternate_email_rounded, type: TextInputType.emailAddress, hint: 'ixtiyoriy'),
              _Label(tr('MASHINA')),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final v in [('labo', 'Labo'), ('damas', 'Damas'), ('gazel', 'Gazel'), ('isuzu', 'Isuzu'), ('fura', 'Fura')])
                    ChoiceChip(selected: vehicleType == v.$1, avatar: Icon(Icons.local_shipping_rounded, size: 16, color: vehicleType == v.$1 ? p.onDark : p.text), label: Text(v.$2), onSelected: (_) => setState(() => vehicleType = v.$1)),
                ]),
              ),
              Row(children: [
                Expanded(child: TextField(controller: capacity, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Sig'im, kg"), prefixIcon: const Icon(Icons.scale_outlined, size: 20)))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: basePrice, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Boshlang'ich narx")))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: perKm, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Narx, so\'m/km (ixtiyoriy)'), prefixIcon: const Icon(Icons.payments_outlined, size: 20))),
              const SizedBox(height: 12),
              _Label(tr('XIZMAT VILOYATLARI')),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in allRegions) FilterChip(selected: regions.contains(r), label: Text(r, style: const TextStyle(fontSize: 12)), onSelected: (v) => setState(() => v ? regions.add(r) : regions.remove(r))),
                ]),
              ),
              _Label(tr("KIRISH MA'LUMOTLARI")),
            ] else if (register && courier) ...[
              _Label(tr('KURYER')),
              field('name', tr('Ism-sharif'), Icons.person_outline_rounded),
              field('phone', tr('Telefon'), Icons.phone_outlined, type: TextInputType.phone, hint: '+998 90 123 45 67'),
              field('email', 'Email', Icons.alternate_email_rounded, type: TextInputType.emailAddress, hint: 'ixtiyoriy'),
              _Label(tr('TRANSPORT')),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final v in [('foot', Icons.directions_walk_rounded, tr('Piyoda')), ('bike', Icons.pedal_bike_rounded, tr('Velosiped')), ('moto', Icons.two_wheeler_rounded, tr('Mototsikl')), ('car', Icons.directions_car_rounded, tr('Mashina'))])
                    ChoiceChip(selected: vehicle == v.$1, avatar: Icon(v.$2, size: 16, color: vehicle == v.$1 ? p.onDark : p.text), label: Text(v.$3), onSelected: (_) => setState(() => vehicle = v.$1)),
                ]),
              ),
              _Label(tr("KIRISH MA'LUMOTLARI")),
            ] else if (register) ...[
              _Label(tr("DO'KON")),
              field('name', tr("Do'kon nomi"), Icons.storefront_outlined, hint: 'Masalan: Alidev'),
              field('ownerName', tr('Egasining ism-sharifi'), Icons.person_outline_rounded),
              field('sellerName', tr('Sotuvchi ismi'), Icons.smart_toy_outlined, hint: tr('AI shu nomdan gaplashadi')),
              field('phone', tr('Telefon'), Icons.phone_outlined, type: TextInputType.phone, hint: '+998 90 123 45 67'),
              const SizedBox(height: 8),
              _Label(tr("KIRISH MA'LUMOTLARI")),
            ],
            field('login', tr('Login'), Icons.alternate_email_rounded, type: TextInputType.emailAddress),
            field('password', tr('Parol'), Icons.lock_outline_rounded, pass: true, action: TextInputAction.done),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: p.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error!, style: TextStyle(fontSize: 13, color: p.danger, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: busy ? null : go,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [Text(register ? (courier ? tr("Ro'yxatdan o'tish") : tr("Do'kon yaratish")) : tr('Kirish')), const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 18)]),
            ),
            const SizedBox(height: 18),
            Center(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(register ? tr('Akkauntingiz bormi? ') : tr("Akkauntingiz yo'qmi? "), style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
                GestureDetector(onTap: busy ? null : _switch, child: Text(register ? tr('Kirish') : tr("Ro'yxatdan o'tish"), style: TextStyle(fontSize: 13, color: p.accentText, fontWeight: FontWeight.w800))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: context.p.muted)),
      );
}
