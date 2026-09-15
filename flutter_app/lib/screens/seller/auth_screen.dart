import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../api.dart';
import '../../l10n.dart';
import '../../main.dart' show showToast;
import '../../models.dart';
import '../../regions.dart';
import '../../state.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../account_screen.dart' show AuthMessage, ErrorNote, VerifyCodeBox;
import '../courier/cargo_screen.dart';
import '../courier/couriers_map_screen.dart';
import '../pick_location_screen.dart';

/// "Sotuvchi" tabi: uch rol — Sotuvchi, Kuryer, Yuk tashuvchi, hamda "Kuryer yollash" xaritasi va yuk buyurtmasi.
/// Formalar alohida to'liq ekranda ochiladi (pastki navigatsiya ko'rinmaydi).
class SellerEntry extends StatelessWidget {
  final VoidCallback onEntered;
  final VoidCallback onCourierEntered;
  const SellerEntry({super.key, required this.onEntered, required this.onCourierEntered});

  void _open(BuildContext context, bool register, {bool courier = false, bool cargo = false}) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => AuthScreen(register: register, courier: courier || cargo, cargo: cargo, onEntered: courier || cargo ? onCourierEntered : onEntered)));
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
        _RoleCard(
          icon: Icons.storefront_rounded,
          title: tr("Sotuvchi"),
          subtitle: tr("Do'kon oching — AI sotuvchi mijozlar bilan 24/7 gaplashadi, buyurtmalarni qabul qiladi"),
          glow: const Color(0xFFFFCC00),
          onLogin: () => _open(context, false),
          onRegister: () => _open(context, true),
        ),
        const SizedBox(height: 12),
        _RoleCard(
          icon: Icons.two_wheeler_rounded,
          title: tr('Kuryer'),
          subtitle: tr("Buyurtmalarni yetkazing va daromad qiling. Onlayn bo'lsangiz, xaridorlar sizni xaritada ko'radi"),
          glow: const Color(0xFF1F9D6A),
          onLogin: () => _open(context, false, courier: true),
          onRegister: () => _open(context, true, courier: true),
        ),
        const SizedBox(height: 12),
        _RoleCard(
          icon: Icons.local_shipping_rounded,
          title: tr('Yuk tashuvchi'),
          subtitle: tr("Viloyatlar aro yuk tashiysizmi? Mashinangiz, sig'imi, narxi va yo'nalishlaringizni qo'shing — mijozlar buyurtma beradi"),
          glow: const Color(0xFFFF8A00),
          onLogin: () => _open(context, false, cargo: true),
          onRegister: () => _open(context, true, cargo: true),
        ),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.local_shipping_rounded,
          title: tr('Yuk mashinasi buyurtma qilish'),
          subtitle: tr("Viloyatlar aro: Labo, Damas, Gazel, Isuzu, fura — tashuvchini tanlang"),
          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const CargoScreen())),
        ),
        const SizedBox(height: 12),
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
            Container(
                width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: Colors.white, size: 22)),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
          ]),
          const SizedBox(height: 10),
          Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: onLogin, child: Text(tr('Kirish')))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        backgroundColor: Colors.white.withValues(alpha: .1),
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: .25))),
                    onPressed: onRegister,
                    child: Text(tr("Ro'yxatdan o'tish")))),
          ]),
        ]),
      );
}

/// Ro'yxatdan o'tish qadamlari
enum _Step { personal, shop, location, transport, cargo, creds, code }

/// Kirish / Ro'yxatdan o'tish — to'liq ekran.
/// Ro'yxatdan o'tish qadam-baqadam:
///  - Sotuvchi: shaxsiy → do'kon (nom, AI sotuvchi ismi, logo) → joylashuv (viloyat, xaritada joy) → login/parol → email kodi
///  - Kuryer: shaxsiy → transport (turi, davlat raqami, viloyat, surat) → login/parol → email kodi
///  - Yuk tashuvchi: shaxsiy → mashina (turi, raqami, sig'im, narx, viloyatlar) → login/parol → email kodi
/// "Hisob yaratish" bosilganda server ma'lumotlarni tekshirib emailga 6 xonali kod yuboradi; kod to'g'ri bo'lsa hisob yaratiladi.
class AuthScreen extends StatefulWidget {
  final bool register;

  /// true — kuryer yoki yuk tashuvchi hisobi, false — do'kon
  final bool courier;

  /// true — yuk tashuvchi (viloyatlararo)
  final bool cargo;
  final VoidCallback onEntered;
  const AuthScreen({super.key, required this.register, required this.onEntered, this.courier = false, this.cargo = false});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  bool get register => widget.register;
  bool get courier => widget.courier;
  bool get cargo => widget.cargo;
  bool get seller => !widget.courier;

  late final List<_Step> steps = !register
      ? const []
      : seller
          ? const [_Step.personal, _Step.shop, _Step.location, _Step.creds, _Step.code]
          : cargo
              ? const [_Step.personal, _Step.cargo, _Step.creds, _Step.code]
              : const [_Step.personal, _Step.transport, _Step.creds, _Step.code];
  int step = 0;
  _Step get kind => steps[step];

  final f = <String, TextEditingController>{
    for (final k in ['firstName', 'lastName', 'phone', 'email', 'shopName', 'aiName', 'login', 'password', 'plate', 'capacityKg', 'basePrice', 'pricePerKm']) k: TextEditingController()
  };
  String? region;
  PickedLocation? location;
  Uint8List? logoBytes; // do'kon logosi
  Uint8List? photoBytes; // kuryer surati
  String vehicle = 'moto';
  String vehicleType = 'labo';
  final regions = <String>{};
  bool showPass = false;
  bool busy = false;
  String? error;
  String? errorField;
  Map<String, dynamic>? sent; // kod yuborilgach server javobi: email, resendIn, devCode

  /// Qadamdagi maydon kalitlari: xato shu maydon ostida ko'rsatiladi, umumiy quti chiqmaydi
  static const _fieldsOf = <_Step, List<String>>{
    _Step.personal: ['firstName', 'lastName', 'phone', 'email'],
    _Step.shop: ['shopName', 'aiName'],
    _Step.location: ['region', 'location', 'address'],
    _Step.transport: ['plate', 'region'],
    _Step.cargo: ['plate', 'capacityKg', 'basePrice', 'pricePerKm', 'regions'],
    _Step.creds: ['login', 'password'],
    _Step.code: [],
  };

  @override
  void dispose() {
    for (final c in f.values) {
      c.dispose();
    }
    super.dispose();
  }

  String t(String k) => f[k]!.text.trim();
  String get _phone => '+998${f['phone']!.text.replaceAll(RegExp(r'\D'), '')}';
  String? _uri(Uint8List? b) => b == null ? null : 'data:image/jpeg;base64,${base64Encode(b)}';

  /// Serverga yuboriladigan ma'lumotlar (kod yuborishda ham, tasdiqlashda ham bir xil)
  Map<String, dynamic> _body({String? code}) => {
        'firstName': t('firstName'),
        'lastName': t('lastName'),
        'phone': _phone,
        'email': t('email'),
        'login': t('login').toLowerCase(),
        'password': f['password']!.text,
        if (seller) ...{
          'shopName': t('shopName'),
          'aiName': t('aiName'),
          // Eski server versiyasi bilan moslik: u `name` va `sellerName` maydonlarini kutadi
          'name': t('shopName'),
          'sellerName': t('aiName'),
          'region': region ?? '',
          if (logoBytes != null) 'logo': _uri(logoBytes),
          if (location != null) 'location': {'lat': location!.lat, 'lon': location!.lon, 'address': location!.address},
        },
        if (courier && !cargo) ...{
          'type': 'courier',
          'vehicle': vehicle,
          'plate': t('plate'),
          'region': region ?? '',
          if (photoBytes != null) 'photo': _uri(photoBytes),
        },
        if (cargo) ...{
          'type': 'cargo',
          'vehicleType': vehicleType,
          'plate': t('plate'),
          'capacityKg': int.tryParse(t('capacityKg')) ?? 0,
          'basePrice': int.tryParse(t('basePrice')) ?? 0,
          'pricePerKm': int.tryParse(t('pricePerKm')) ?? 0,
          'regions': regions.toList(),
          'region': regions.isEmpty ? '' : regions.first,
          if (photoBytes != null) 'photo': _uri(photoBytes),
        },
        if (code != null) 'code': code,
      };

  /// Qadam maydonlarini telefonda tekshirish (server ham qayta tekshiradi)
  String? _check(_Step s) {
    String? bad(String field, String msg) {
      errorField = field;
      return msg;
    }
    switch (s) {
      case _Step.personal:
        if (t('firstName').length < 2) return bad('firstName', tr('Ismingizni kiriting'));
        if (t('lastName').length < 2) return bad('lastName', tr('Familiyangizni kiriting'));
        if (f['phone']!.text.replaceAll(RegExp(r'\D'), '').length != 9) return bad('phone', tr("Telefon raqamini to'liq kiriting"));
        if (!_emailRe.hasMatch(t('email'))) return bad('email', tr("Email manzilini to'g'ri kiriting"));
      case _Step.shop:
        if (t('shopName').length < 2) return bad('shopName', tr("Do'kon nomini kiriting"));
      case _Step.location:
        if (region == null) return bad('region', tr('Viloyatni tanlang'));
        if (location == null) return bad('location', tr("Do'kon joylashuvini xaritada belgilang"));
      case _Step.transport:
        if ((vehicle == 'moto' || vehicle == 'car') && t('plate').replaceAll(' ', '').length < 5) return bad('plate', tr('Davlat raqamini kiriting'));
        if (region == null) return bad('region', tr('Ishlaydigan viloyatingizni tanlang'));
      case _Step.cargo:
        if (t('plate').replaceAll(' ', '').length < 5) return bad('plate', tr('Davlat raqamini kiriting'));
        if ((int.tryParse(t('capacityKg')) ?? 0) < 50) return bad('capacityKg', tr("Yuk sig'imini kiriting (kg)"));
        if ((int.tryParse(t('basePrice')) ?? 0) <= 0 && (int.tryParse(t('pricePerKm')) ?? 0) <= 0) return bad('basePrice', tr("Narxni kiriting: boshlang'ich narx yoki 1 km narxi"));
        if (regions.isEmpty) return bad('regions', tr('Kamida bitta viloyatni tanlang'));
      case _Step.creds:
        if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(t('login').toLowerCase())) return bad('login', tr('Login 3–30 belgi: lotin harflari, raqam, _ yoki .'));
        if (f['password']!.text.length < 6) return bad('password', tr('Parol kamida 6 belgi'));
      case _Step.code:
        break;
    }
    return null;
  }

  void _clearError() {
    if (error != null || errorField != null) {
      setState(() {
        error = null;
        errorField = null;
      });
    }
  }

  void _back() {
    if (register && step > 0) {
      setState(() {
        step = kind == _Step.code ? steps.indexOf(_Step.creds) : step - 1;
        error = null;
        errorField = null;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// Keyingi qadam; "Kirish ma'lumotlari" qadamida — emailga kod yuboriladi
  Future<void> next() async {
    FocusScope.of(context).unfocus();
    final problem = _check(kind);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    if (kind == _Step.creds) return _sendCode();
    setState(() {
      step++;
      error = null;
      errorField = null;
    });
  }

  String get _path => courier ? '/api/courier/register' : '/api/seller/register';

  Future<void> _sendCode() async {
    setState(() {
      busy = true;
      error = null;
      errorField = null;
    });
    try {
      final r = await Api.instance.post(_path, _body());
      if (!mounted) return;
      setState(() {
        sent = Map<String, dynamic>.from(r as Map);
        step = steps.indexOf(_Step.code);
      });
    } on ApiException catch (e) {
      _fail(e);
    } catch (_) {
      if (mounted) setState(() => error = tr("Serverga ulanib bo'lmadi. Internetni tekshiring"));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Server xatosi: qaysi maydon noto'g'ri bo'lsa, o'sha qadamga qaytadi
  void _fail(ApiException e) {
    if (!mounted) return;
    final s = _stepOf(e.field);
    setState(() {
      error = e.message;
      errorField = e.field;
      if (s != null) step = steps.indexOf(s);
    });
  }

  _Step? _stepOf(String? field) {
    if (field == null) return null;
    for (final e in _fieldsOf.entries) {
      if (e.value.contains(field) && steps.contains(e.key)) return e.key;
    }
    if (field == 'logo' && steps.contains(_Step.shop)) return _Step.shop;
    if (['vehicle', 'vehicleType', 'photo'].contains(field)) return cargo ? _Step.cargo : _Step.transport;
    return null;
  }

  Future<Map<String, dynamic>> _resend() async => Map<String, dynamic>.from(await Api.instance.post(_path, _body()) as Map);

  /// Kod to'g'ri bo'lsa hisob yaratiladi va sessiya shu hisobga bog'lanadi
  Future<void> _verify(String code) async {
    final r = await Api.instance.post(_path, _body(code: code));
    _enter(r);
  }

  void _enter(dynamic r) {
    final st = AppState.instance;
    if (courier) {
      st.courier = Courier.fromJson(r['courier']);
      st.sellerShop = null;
    } else {
      st.sellerShop = Shop.fromJson(r['shop']);
      st.courier = null;
      st.refreshBadges();
    }
    st.refresh();
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onEntered();
  }

  Future<void> login() async {
    FocusScope.of(context).unfocus();
    if (t('login').isEmpty || f['password']!.text.isEmpty) {
      setState(() => error = tr('Login va parolni kiriting'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await Api.instance.post(courier ? '/api/courier/login' : '/api/seller/login', {
        'login': t('login'),
        'password': f['password']!.text,
        if (courier) 'type': cargo ? 'cargo' : 'courier',
      });
      _enter(r);
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = tr("Serverga ulanib bo'lmadi. Internetni tekshiring"));
    }
    if (mounted) setState(() => busy = false);
  }

  /// Parolni tiklash: email → kod + yangi parol
  Future<void> _forgot() async {
    final login = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResetSheet(role: courier ? 'courier' : 'seller', email: t('login').contains('@') ? t('login') : ''),
    );
    if (login == null || !mounted) return;
    f['login']!.text = login;
    f['password']!.clear();
    setState(() => error = null);
    showToast(context, tr('Parol yangilandi. Yangi parol bilan kiring'));
  }

  void _switch() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => AuthScreen(register: !register, courier: courier, cargo: cargo, onEntered: widget.onEntered),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 220),
    ));
  }

  Future<void> _pickImage({required bool logo}) async {
    final src = await askImageSource(context);
    if (src == null || !mounted) return;
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        if (logo) {
          logoBytes = bytes;
        } else {
          photoBytes = bytes;
        }
      });
    } catch (_) {
      if (mounted) setState(() => error = tr("Rasmni olib bo'lmadi"));
    }
  }

  Future<void> _pickLocation() async {
    final rc = region != null ? kRegionCoords[region!] : null;
    final r = await Navigator.of(context, rootNavigator: true).push<PickedLocation>(MaterialPageRoute(
      builder: (_) => PickLocationScreen(
        initial: location != null ? LatLng(location!.lat, location!.lon) : rc != null ? LatLng(rc[0], rc[1]) : null,
        address: location?.address,
        title: "Do'kon joylashuvi",
      ),
    ));
    if (r != null && mounted) {
      setState(() {
        location = r;
        if (errorField == 'location' || errorField == 'address') {
          error = null;
          errorField = null;
        }
      });
    }
  }

  // ---------- UI ----------

  Widget field(String key, String label, IconData icon,
      {bool pass = false,
      TextInputType? type,
      String? hint,
      String? prefix,
      List<TextInputFormatter>? fmt,
      TextCapitalization cap = TextCapitalization.none,
      TextInputAction action = TextInputAction.next}) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: f[key],
        obscureText: pass && !showPass,
        keyboardType: type,
        textInputAction: action,
        inputFormatters: fmt,
        textCapitalization: cap,
        autocorrect: false,
        enabled: !busy,
        onChanged: errorField == key ? (_) => _clearError() : null,
        onSubmitted: action == TextInputAction.done ? (_) => register ? next() : login() : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefix,
          prefixIcon: Icon(icon, size: 20, color: p.muted),
          errorText: errorField == key ? error : null,
          suffixIcon: pass
              ? IconButton(onPressed: () => setState(() => showPass = !showPass), icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: p.muted))
              : null,
        ),
      ),
    );
  }

  Widget _regionDropdown({String? label}) => DropdownButtonFormField<String>(
        initialValue: region,
        isExpanded: true,
        items: [for (final r in kRegions) DropdownMenuItem(value: r, child: Text(r))],
        onChanged: busy
            ? null
            : (v) => setState(() {
                  region = v;
                  if (errorField == 'region') {
                    error = null;
                    errorField = null;
                  }
                }),
        decoration: InputDecoration(labelText: label ?? tr('Viloyat'), prefixIcon: const Icon(Icons.map_outlined, size: 20), errorText: errorField == 'region' ? error : null),
      );

  (String, String) get _titles {
    if (!register) {
      return (
        cargo ? tr('Yuk tashuvchi kirishi') : courier ? tr('Kuryer kirishi') : tr('Xush kelibsiz!'),
        courier ? tr('Kuryer paneliga kirish uchun login va parolingizni kiriting.') : tr('Sotuvchi paneliga kirish uchun login va parolingizni kiriting.'),
      );
    }
    switch (kind) {
      case _Step.personal:
        return (tr("Shaxsiy ma'lumotlar"), tr('Ism, familiya, telefon va email. Tasdiqlash kodi shu emailga keladi'));
      case _Step.shop:
        return (tr("Do'kon"), tr("Do'kon nomi, AI sotuvchi ismi va logo"));
      case _Step.location:
        return (tr('Joylashuv'), tr("Qayerda yashaysiz va do'kon xaritada qayerda"));
      case _Step.transport:
        return (tr('Transport'), tr('Nimada yetkazasiz va qaysi viloyatda ishlaysiz'));
      case _Step.cargo:
        return (tr('Mashina'), tr("Mashina turi, sig'imi, narxi va yo'nalishlar"));
      case _Step.creds:
        return (tr("Kirish ma'lumotlari"), tr('Login va parol. Keyin hisobga shu bilan kirasiz'));
      case _Step.code:
        return (tr('Emailni tasdiqlang'), '');
    }
  }

  bool get _showGeneralError => error != null && !(register && (_fieldsOf[kind] ?? const []).contains(errorField));

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isCode = register && kind == _Step.code;
    final (title, sub) = _titles;
    return PopScope(
      canPop: !(register && step > 0),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            // Sarlavha: orqaga va qadamlar chizig'i
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                IconBtn(Icons.arrow_back_ios_new_rounded, onTap: busy ? null : _back),
                if (register) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Row(children: [
                      for (var i = 0; i < steps.length; i++)
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(color: i <= step ? p.accent : p.border, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Text('${step + 1}/${steps.length}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w800, fontSize: 13)),
                ],
              ]),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                children: [
                  if (!isCode) ...[
                    Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.1)),
                    const SizedBox(height: 6),
                    Text(sub, style: TextStyle(fontSize: 14, color: p.muted, fontWeight: FontWeight.w500, height: 1.45)),
                    const SizedBox(height: 22),
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(register ? step : -1),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: register ? _stepBody(context) : _loginBody(context)),
                    ),
                  ),
                  if (_showGeneralError && !isCode) ...[const SizedBox(height: 4), ErrorNote(error!)],
                ],
              ),
            ),
            if (!isCode) _bottom(context),
          ]),
        ),
      ),
    );
  }

  Widget _bottom(BuildContext context) {
    final p = context.p;
    final isCreds = register && kind == _Step.creds;
    final label = !register
        ? tr('Kirish')
        : isCreds
            ? tr('Hisob yaratish')
            : tr('Keyingisi');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton(
          onPressed: busy ? null : (register ? next : login),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [Text(label), const SizedBox(width: 8), Icon(isCreds ? Icons.mark_email_read_outlined : Icons.arrow_forward_rounded, size: 18)]),
        ),
        if (!register || step == 0) ...[
          const SizedBox(height: 10),
          Center(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(register ? tr('Akkauntingiz bormi? ') : tr("Akkauntingiz yo'qmi? "), style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
              GestureDetector(
                  onTap: busy ? null : _switch,
                  child: Text(register ? tr('Kirish') : tr("Ro'yxatdan o'tish"), style: TextStyle(fontSize: 13, color: p.accentText, fontWeight: FontWeight.w800))),
            ]),
          ),
        ],
      ]),
    );
  }

  List<Widget> _stepBody(BuildContext context) {
    switch (kind) {
      case _Step.personal:
        return _personal();
      case _Step.shop:
        return _shop();
      case _Step.location:
        return _location(context);
      case _Step.transport:
        return _transport(context);
      case _Step.cargo:
        return _cargoVehicle(context);
      case _Step.creds:
        return _creds();
      case _Step.code:
        return [_codeBox()];
    }
  }

  List<Widget> _personal() => [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: field('firstName', tr('Ism'), Icons.person_outline_rounded, cap: TextCapitalization.words)),
          const SizedBox(width: 8),
          Expanded(child: field('lastName', tr('Familiya'), Icons.badge_outlined, cap: TextCapitalization.words)),
        ]),
        field('phone', tr('Telefon raqami'), Icons.phone_outlined,
            type: TextInputType.phone, prefix: '+998 ', hint: '90 123 45 67', fmt: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)]),
        field('email', 'Email', Icons.alternate_email_rounded, type: TextInputType.emailAddress, hint: 'siz@gmail.com', action: TextInputAction.done),
        _Hint(Icons.mark_email_read_outlined, tr('Hisob yaratishda shu emailga 6 xonali tasdiqlash kodi yuboriladi')),
      ];

  List<Widget> _shop() => [
        Center(
          child: _ImagePick(
            bytes: logoBytes,
            icon: Icons.storefront_outlined,
            label: logoBytes == null ? tr("Do'kon logosini yuklang") : tr("Logoni o'zgartirish"),
            onTap: () => _pickImage(logo: true),
            onClear: logoBytes == null ? null : () => setState(() => logoBytes = null),
          ),
        ),
        const SizedBox(height: 18),
        field('shopName', tr("Do'kon nomi"), Icons.storefront_outlined, hint: 'Masalan: Alidev', cap: TextCapitalization.words),
        field('aiName', tr('AI sotuvchi ismi'), Icons.smart_toy_outlined, hint: 'Madina', cap: TextCapitalization.words, action: TextInputAction.done),
        _Hint(Icons.auto_awesome_outlined, tr("Ixtiyoriy. Bo'sh qolsa AI sotuvchi Madina nomidan mijozlar bilan gaplashadi")),
      ];

  List<Widget> _location(BuildContext context) {
    final p = context.p;
    final loc = location;
    final locError = (errorField == 'location' || errorField == 'address') && error != null;
    return [
      _Label(tr('QAYERDA YASHAYSIZ')),
      _regionDropdown(),
      const SizedBox(height: 18),
      _Label(tr("DO'KON XARITADA")),
      Material(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: busy ? null : _pickLocation,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: locError ? p.danger : p.border)),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: loc == null ? p.accentSoft : p.successSoft, borderRadius: BorderRadius.circular(14)),
                child: Icon(loc == null ? Icons.add_location_alt_outlined : Icons.where_to_vote_outlined, color: loc == null ? p.accentText : p.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(loc == null ? tr('Xaritada belgilash') : loc.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(loc == null ? tr("Do'kon turgan joyga pin qo'ying") : '${loc.lat.toStringAsFixed(5)}, ${loc.lon.toStringAsFixed(5)} · ${tr("O'zgartirish")}',
                      style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          ),
        ),
      ),
      if (locError) Padding(padding: const EdgeInsets.only(top: 8, left: 4), child: Text(error!, style: TextStyle(color: p.danger, fontSize: 12.5, fontWeight: FontWeight.w600))),
      const SizedBox(height: 12),
      _Hint(Icons.info_outline_rounded, tr("Xaridorlar do'koningizni xaritada ko'radi, kuryer buyurtmani shu manzildan oladi")),
    ];
  }

  IconData _vehicleIcon(String v) => switch (v) {
        'foot' => Icons.directions_walk_rounded,
        'bike' => Icons.pedal_bike_rounded,
        'moto' => Icons.two_wheeler_rounded,
        _ => Icons.directions_car_rounded,
      };

  Widget _photoPick() => Center(
        child: _ImagePick(
          bytes: photoBytes,
          icon: Icons.person_outline_rounded,
          circle: true,
          label: photoBytes == null ? tr('Suratingizni yuklang') : tr("Suratni o'zgartirish"),
          onTap: () => _pickImage(logo: false),
          onClear: photoBytes == null ? null : () => setState(() => photoBytes = null),
        ),
      );

  List<Widget> _transport(BuildContext context) {
    final p = context.p;
    final needsPlate = vehicle == 'moto' || vehicle == 'car';
    return [
      _Label(tr('TRANSPORT')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in kVehicles)
          ChoiceChip(
            selected: vehicle == v.$1,
            avatar: Icon(_vehicleIcon(v.$1), size: 16, color: vehicle == v.$1 ? p.onDark : p.text),
            label: Text(tr(v.$2)),
            onSelected: busy ? null : (_) => setState(() => vehicle = v.$1),
          ),
      ]),
      const SizedBox(height: 14),
      if (needsPlate) field('plate', tr('Davlat raqami'), Icons.pin_outlined, hint: '01 A 123 BC', cap: TextCapitalization.characters, action: TextInputAction.done),
      _Label(tr('ISH VILOYATI')),
      _regionDropdown(label: tr('Qaysi viloyatda yetkazasiz')),
      const SizedBox(height: 18),
      _Label(tr('SURAT (IXTIYORIY)')),
      _photoPick(),
      const SizedBox(height: 10),
      _Hint(Icons.info_outline_rounded, tr("Onlayn bo'lganingizda xaridorlar va do'konlar sizni xaritada ko'radi, buyurtma o'zi keladi")),
    ];
  }

  List<Widget> _cargoVehicle(BuildContext context) {
    final p = context.p;
    return [
      _Label(tr('MASHINA TURI')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in kVehicleTypes)
          ChoiceChip(
            selected: vehicleType == v.$1,
            avatar: Icon(Icons.local_shipping_rounded, size: 16, color: vehicleType == v.$1 ? p.onDark : p.text),
            label: Text(v.$2),
            onSelected: busy ? null : (_) => setState(() => vehicleType = v.$1),
          ),
      ]),
      const SizedBox(height: 14),
      field('plate', tr('Davlat raqami'), Icons.pin_outlined, hint: '01 A 123 BC', cap: TextCapitalization.characters),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: field('capacityKg', tr("Sig'im, kg"), Icons.scale_outlined, type: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly], hint: '1500')),
        const SizedBox(width: 8),
        Expanded(child: field('basePrice', tr("Boshlang'ich narx"), Icons.payments_outlined, type: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly], hint: '300000')),
      ]),
      field('pricePerKm', tr("1 km narxi, so'm (ixtiyoriy)"), Icons.route_outlined, type: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly], hint: '3000', action: TextInputAction.done),
      _Label(tr('XIZMAT VILOYATLARI')),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in kRegions)
          FilterChip(
            selected: regions.contains(r),
            label: Text(r, style: const TextStyle(fontSize: 12)),
            onSelected: busy
                ? null
                : (v) => setState(() {
                      if (v) {
                        regions.add(r);
                      } else {
                        regions.remove(r);
                      }
                      if (errorField == 'regions') {
                        error = null;
                        errorField = null;
                      }
                    }),
          ),
      ]),
      if (errorField == 'regions' && error != null)
        Padding(padding: const EdgeInsets.only(top: 8, left: 4), child: Text(error!, style: TextStyle(color: p.danger, fontSize: 12.5, fontWeight: FontWeight.w600))),
      const SizedBox(height: 18),
      _Label(tr('SURAT (IXTIYORIY)')),
      _photoPick(),
    ];
  }

  List<Widget> _creds() => [
        field('login', tr('Login'), Icons.alternate_email_rounded,
            hint: 'masalan: alidev', fmt: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')), LengthLimitingTextInputFormatter(30)]),
        field('password', tr('Parol'), Icons.lock_outline_rounded, pass: true, action: TextInputAction.done),
        _Hint(Icons.mark_email_read_outlined, tr('"Hisob yaratish" bosilganda emailingizga kod yuboriladi. Kod tasdiqlangach hisob yaratiladi')),
      ];

  Widget _codeBox() {
    final s = sent ?? const <String, dynamic>{};
    return VerifyCodeBox(
      email: s['email']?.toString() ?? t('email'),
      resendIn: (s['resendIn'] as num?)?.toInt() ?? 60,
      devCode: s['devCode']?.toString(),
      onVerify: _verify,
      onResend: _resend,
      onBack: _back,
    );
  }

  List<Widget> _loginBody(BuildContext context) {
    final p = context.p;
    return [
      field('login', tr('Login yoki email'), Icons.alternate_email_rounded, type: TextInputType.emailAddress),
      field('password', tr('Parol'), Icons.lock_outline_rounded, pass: true, action: TextInputAction.done),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: busy ? null : _forgot, child: Text(tr('Parolni unutdingizmi?'), style: TextStyle(color: p.accentText, fontWeight: FontWeight.w800, fontSize: 13))),
      ),
    ];
  }
}

/// Parolni tiklash: email → emailga kod → kod + yangi parol. Muvaffaqiyatda login qaytaradi.
class _ResetSheet extends StatefulWidget {
  final String role; // seller | courier (yuk tashuvchi ham courier)
  final String email;
  const _ResetSheet({required this.role, required this.email});
  @override
  State<_ResetSheet> createState() => _ResetSheetState();
}

class _ResetSheetState extends State<_ResetSheet> {
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  late final email = TextEditingController(text: widget.email);
  final pass = TextEditingController();
  bool busy = false;
  bool showPass = false;
  String? error;
  Map<String, dynamic>? sent;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _base => {'role': widget.role, 'email': email.text.trim()};

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!_emailRe.hasMatch(email.text.trim())) {
      setState(() => error = tr("Email manzilini to'g'ri kiriting"));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await Api.instance.post('/api/auth/reset', _base);
      if (mounted) setState(() => sent = Map<String, dynamic>.from(r as Map));
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = tr("Serverga ulanib bo'lmadi. Internetni tekshiring"));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verify(String code) async {
    if (pass.text.length < 6) throw AuthMessage(tr('Yangi parol kamida 6 belgi'));
    final r = await Api.instance.post('/api/auth/reset', {..._base, 'code': code, 'password': pass.text});
    if (mounted) Navigator.of(context).pop(r['login']?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final s = sent;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: s != null
          ? VerifyCodeBox(
              email: s['email']?.toString() ?? email.text.trim(),
              resendIn: (s['resendIn'] as num?)?.toInt() ?? 60,
              devCode: s['devCode']?.toString(),
              onVerify: _verify,
              onResend: () async => Map<String, dynamic>.from(await Api.instance.post('/api/auth/reset', _base) as Map),
              onBack: () => setState(() => sent = null),
              extra: [
                const SizedBox(height: 16),
                TextField(
                  controller: pass,
                  obscureText: !showPass,
                  decoration: InputDecoration(
                    labelText: tr('Yangi parol'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(onPressed: () => setState(() => showPass = !showPass), icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20)),
                  ),
                ),
              ],
            )
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Parolni tiklash'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              const SizedBox(height: 6),
              Text(tr("Ro'yxatdan o'tgan emailingizni kiriting — tasdiqlash kodi yuboramiz"), style: TextStyle(fontSize: 13.5, color: p.muted, fontWeight: FontWeight.w500, height: 1.4)),
              const SizedBox(height: 16),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !busy,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(labelText: 'Email', prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20), errorText: error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : _send,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(tr('Kod yuborish')),
              ),
            ]),
    );
  }
}

/// Logo yoki surat tanlash: kvadrat (do'kon) yoki doira (kuryer)
class _ImagePick extends StatelessWidget {
  final Uint8List? bytes;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool circle;
  const _ImagePick({required this.bytes, required this.icon, required this.label, required this.onTap, this.onClear, this.circle = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final b = bytes;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 104,
            height: 104,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.accentSoft,
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle ? null : BorderRadius.circular(30),
              border: Border.all(color: p.accent.withValues(alpha: .5), width: 1.5),
            ),
            child: b != null ? Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true) : Icon(icon, size: 40, color: p.accentText),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: p.dark, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2)),
              child: Icon(b == null ? Icons.add_rounded : Icons.edit_rounded, size: 16, color: p.onDark),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
        if (onClear != null) ...[
          const SizedBox(width: 10),
          GestureDetector(onTap: onClear, child: Text(tr("O'chirish"), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700, fontSize: 12.5))),
        ],
      ]),
    ]);
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: p.accentText),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: p.text, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
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
