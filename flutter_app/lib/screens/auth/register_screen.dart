import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../api.dart';
import '../../photo.dart';
import '../../l10n.dart';
import '../../models.dart';
import '../../realtime.dart';
import '../../state.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'auth_ui.dart';

/// Rol bo'yicha ro'yxatdan o'tish: sotuvchi (do'kon), kuryer va yuk tashuvchi.
/// Oxirgi qadamda emailga 6 xonali kod yuboriladi — kod tasdiqlangandan keyin hisob yaratiladi.
class RegisterScreen extends StatefulWidget {
  final String role; // seller | courier | cargo
  final VoidCallback onDone;
  const RegisterScreen({super.key, required this.role, required this.onDone});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

const _vehicles = [
  ('foot', Icons.directions_walk_rounded, 'Piyoda'),
  ('bike', Icons.pedal_bike_rounded, 'Velosiped'),
  ('moto', Icons.two_wheeler_rounded, 'Mototsikl'),
  ('car', Icons.directions_car_rounded, 'Mashina'),
];
const _truckTypes = [
  ('labo', 'Labo', '0.5 t'),
  ('damas', 'Damas', '0.7 t'),
  ('gazel', 'Gazel', '1.5 t'),
  ('isuzu', 'Isuzu', '5 t'),
  ('fura', 'Fura', '20 t'),
];

class _RegisterScreenState extends State<RegisterScreen> {
  // umumiy
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final login = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  // do'kon
  final shopName = TextEditingController();
  final aiName = TextEditingController();
  final address = TextEditingController();
  String? logo;
  String? region;
  LatLng? pos;
  final mapCtrl = MapController();
  bool addrBusy = false;
  // kuryer / yuk
  String vehicle = 'moto';
  String truck = 'labo';
  final plate = TextEditingController();
  final capacity = TextEditingController();
  final basePrice = TextEditingController();
  final perKm = TextEditingController();
  final regions = <String>[];
  String? photo;

  int step = 0;
  bool busy = false;
  bool hidePass = true;
  String? error;
  String? devCode;

  bool get seller => widget.role == 'seller';
  bool get cargo => widget.role == 'cargo';
  bool get courier => widget.role == 'courier';
  String get digits => phone.text.replaceAll(RegExp(r'\D'), '');
  int get lastStep => seller ? 4 : cargo ? 4 : 3;

  @override
  void dispose() {
    for (final c in [firstName, lastName, phone, email, login, pass, pass2, shopName, aiName, address, plate, capacity, basePrice, perKm]) {
      c.dispose();
    }
    super.dispose();
  }

  String get title => switch (widget.role) {
        'seller' => tr("Do'kon oching"),
        'courier' => tr('Kuryer bo\'ling'),
        _ => tr('Yuk tashuvchi bo\'ling'),
      };

  String get subtitle => switch (step) {
        0 => tr('Avval o\'zingiz haqingizda qisqacha'),
        _ => '',
      };

  // ---------- qadamlarni tekshirish ----------
  String? _checkStep() {
    if (step == 0) {
      if (firstName.text.trim().length < 2) return tr('Ismingizni kiriting');
      if (lastName.text.trim().length < 2) return tr('Familiyangizni kiriting');
      if (digits.length != 9) return tr("Telefon raqamini to'liq kiriting");
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email.text.trim())) return tr("Email manzilini to'g'ri kiriting");
      return null;
    }
    if (seller && step == 1) {
      if (shopName.text.trim().length < 2) return tr("Do'kon nomini kiriting");
      return null;
    }
    if (seller && step == 2) {
      if (region == null) return tr('Viloyatni tanlang');
      if (pos == null) return tr("Do'kon joyini xaritada belgilang");
      if (address.text.trim().isEmpty) return tr('Manzilni kiriting');
      return null;
    }
    if (courier && step == 1) {
      if (region == null) return tr('Ishlaydigan viloyatingizni tanlang');
      return null;
    }
    if (cargo && step == 1) {
      if (plate.text.trim().replaceAll(' ', '').length < 5) return tr('Mashina davlat raqamini kiriting');
      if ((int.tryParse(capacity.text.replaceAll(RegExp(r'\D'), '')) ?? 0) < 50) return tr("Yuk sig'imini kiriting (kg)");
      return null;
    }
    if (cargo && step == 2) {
      final b = int.tryParse(basePrice.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final k = int.tryParse(perKm.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
      if (b <= 0 && k <= 0) return tr("Narxni kiriting: boshlang'ich narx yoki 1 km narxi");
      if (regions.isEmpty) return tr('Kamida bitta viloyatni tanlang');
      return null;
    }
    if (step == lastStep - 1) {
      if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(login.text.trim().toLowerCase())) return tr('Login 3–30 belgi: lotin harflari, raqam, _ yoki .');
      if (pass.text.length < 6) return tr('Parol kamida 6 belgi');
      if (pass.text != pass2.text) return tr('Parollar mos kelmadi');
      return null;
    }
    return null;
  }

  void _next() {
    final problem = _checkStep();
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    if (step == lastStep - 1) {
      _submit();
      return;
    }
    setState(() {
      step++;
      error = null;
    });
  }

  void _back() {
    if (step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      step--;
      error = null;
    });
  }

  Map<String, dynamic> _body({String? code}) {
    final common = {
      'firstName': firstName.text.trim(),
      'lastName': lastName.text.trim(),
      'phone': '+998$digits',
      'email': email.text.trim(),
      'login': login.text.trim().toLowerCase(),
      'password': pass.text,
      if (code != null) 'code': code,
    };
    if (seller) {
      return {
        ...common,
        'shopName': shopName.text.trim(),
        'aiName': aiName.text.trim(),
        'region': region,
        'location': {'lat': pos!.latitude, 'lon': pos!.longitude, 'address': address.text.trim()},
        if (logo != null) 'logo': logo,
      };
    }
    if (courier) {
      return {
        ...common,
        'type': 'courier',
        'vehicle': vehicle,
        'region': region,
        'plate': plate.text.trim(),
        if (photo != null) 'photo': photo,
      };
    }
    return {
      ...common,
      'type': 'cargo',
      'vehicleType': truck,
      'plate': plate.text.trim(),
      'capacityKg': int.tryParse(capacity.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
      'basePrice': int.tryParse(basePrice.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
      'pricePerKm': int.tryParse(perKm.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
      'regions': regions,
      'region': regions.isNotEmpty ? regions.first : null,
      if (photo != null) 'photo': photo,
    };
  }

  String get _path => seller ? '/api/seller/register' : '/api/courier/register';

  /// 1-qadam: server ma'lumotlarni tekshiradi va emailga kod yuboradi
  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await Api.instance.post(_path, _body());
      if (!mounted) return;
      setState(() {
        devCode = r['devCode']?.toString();
        step = lastStep;
      });
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  /// 2-qadam: kod tasdiqlanadi va hisob yaratiladi
  Future<void> _verify(String code) async {
    final r = await Api.instance.post(_path, _body(code: code));
    final st = AppState.instance;
    if (seller) {
      st.sellerShop = Shop.fromJson(r['shop']);
      st.courier = null;
    } else {
      st.courier = Courier.fromJson(r['courier']);
      st.sellerShop = null;
    }
    await Api.instance.get('/api/me').catchError((_) => {});
    st.refresh();
    Realtime.instance.restart();
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onDone();
  }

  // ---------- rasm ----------
  Future<void> _pickImage({required bool isLogo}) async {
    final src = await askImageSource(context);
    if (src == null) return;
    try {
      final f = await PhotoPick.logo(src);
      if (f == null) return;
      final data = await Api.instance.uploadImage(
        await f.readAsBytes(),
        mime: Api.imageMimeForPath(f.path),
      );
      if (!mounted) return;
      setState(() => isLogo ? logo = data : photo = data);
    } catch (e) {
      if (mounted) setState(() => error = tr("Rasmni yuklab bo'lmadi"));
    }
  }

  // ---------- xarita ----------
  Future<void> _setPos(LatLng p, {bool move = false}) async {
    setState(() {
      pos = p;
      addrBusy = true;
    });
    if (move) mapCtrl.move(p, 16);
    final a = await _reverseGeocode(p);
    if (!mounted) return;
    setState(() {
      addrBusy = false;
      if (a != null && a.isNotEmpty) address.text = a;
    });
  }

  Future<void> _myLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception(tr('Joylashuvga ruxsat berilmadi'));
      }
      final p = await Geolocator.getCurrentPosition();
      await _setPos(LatLng(p.latitude, p.longitude), move: true);
    } catch (e) {
      if (mounted) setState(() => error = tr('Joylashuvni aniqlab bo\'lmadi. Xaritada qo\'lda belgilang'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: step == lastStep ? tr('Emailni tasdiqlang') : title,
      subtitle: step == lastStep ? tr('Hisob kod tasdiqlangandan keyin yaratiladi') : (subtitle.isEmpty ? null : subtitle),
      onBack: busy ? null : _back,
      step: step + 1,
      steps: lastStep + 1,
      children: [
        if (step == lastStep)
          CodeStep(
            email: email.text.trim(),
            devCode: devCode,
            buttonLabel: seller ? tr("Do'kon yaratish") : tr('Hisob yaratish'),
            onResend: () async => (await Api.instance.post(_path, _body()))['devCode']?.toString(),
            onSubmit: _verify,
          )
        else ...[
          AuthCard(children: [..._stepFields(), AuthErrorText(error), AuthButton(step == lastStep - 1 ? tr('Hisob yaratish') : tr('Keyingisi'), busy: busy, onTap: _next, icon: Icons.arrow_forward_rounded)]),
          const SizedBox(height: 14),
          Center(
            child: Text(
              step == lastStep - 1 ? tr('Tugmani bosgach, emailingizga 6 xonali kod yuboriladi') : tr("Ma'lumotlar xavfsiz saqlanadi"),
              textAlign: TextAlign.center,
              style: TextStyle(color: authFgSoft(context, .45), fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _stepFields() {
    if (step == 0) return _personal();
    if (seller) return step == 1 ? _shop() : step == 2 ? _shopLocation() : _credentials();
    if (courier) return step == 1 ? _courierStep() : _credentials();
    return step == 1 ? _truckStep() : step == 2 ? _cargoTariff() : _credentials();
  }

  List<Widget> _personal() => [
        AuthLabel(tr("Shaxsiy ma'lumotlar")),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: AuthField(controller: firstName, label: tr('Ism'), icon: Icons.person_outline_rounded, caps: TextCapitalization.words)),
          const SizedBox(width: 10),
          Expanded(child: AuthField(controller: lastName, label: tr('Familiya'), caps: TextCapitalization.words)),
        ]),
        AuthField(
          controller: phone,
          label: tr('Telefon raqami'),
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          prefixText: '+998 ',
          hint: '90 123 45 67',
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
        ),
        AuthField(
          controller: email,
          label: 'Email',
          icon: Icons.alternate_email_rounded,
          keyboard: TextInputType.emailAddress,
          hint: 'siz@email.com',
          action: TextInputAction.done,
          onSubmit: _next,
        ),
        Text(tr('Tasdiqlash kodi shu emailga yuboriladi'), style: TextStyle(fontSize: 12, color: context.p.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
      ];

  List<Widget> _shop() => [
        AuthLabel(tr("Do'kon")),
        AuthField(controller: shopName, label: tr("Do'kon nomi"), icon: Icons.storefront_outlined, hint: tr('Masalan: Alidev Market'), caps: TextCapitalization.words),
        AuthField(controller: aiName, label: tr('AI sotuvchi ismi'), icon: Icons.smart_toy_outlined, hint: tr('Bo\'sh qoldirsangiz — Madina')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(tr('Mijozlar bilan shu ismdan gaplashadi'), style: TextStyle(fontSize: 12, color: context.p.muted, fontWeight: FontWeight.w600)),
        ),
        AuthLabel(tr('Logo')),
        Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: context.p.bg, borderRadius: BorderRadius.circular(20), image: logo == null ? null : DecorationImage(image: MemoryImage(base64Decode(logo!.split(',').last)), fit: BoxFit.cover)),
            child: logo == null ? Icon(Icons.image_outlined, color: context.p.muted) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(isLogo: true),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(logo == null ? tr("Rasm qo'shish") : tr("O'zgartirish")),
              ),
              Text(tr('Ixtiyoriy — keyin ham qo\'shsa bo\'ladi'), style: TextStyle(fontSize: 11.5, color: context.p.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
      ];

  List<Widget> _shopLocation() => [
        AuthLabel(tr('Qayerda yashaysiz')),
        RegionPicker(
          value: region,
          label: tr('Viloyat'),
          onPick: (r) {
            setState(() => region = r);
            final c = kRegionCenter[r];
            if (c != null && pos == null) mapCtrl.move(LatLng(c[0], c[1]), 11);
          },
        ),
        AuthLabel(tr("Do'kon joylashuvi")),
        Text(tr("Xaritada do'koningiz turgan joyni bosing"), style: TextStyle(fontSize: 12.5, color: context.p.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 240,
            child: Stack(children: [
              FlutterMap(
                mapController: mapCtrl,
                options: MapOptions(
                  initialCenter: pos ?? LatLng(kRegionCenter[region]?[0] ?? 41.311, kRegionCenter[region]?[1] ?? 69.240),
                  initialZoom: pos == null ? 11 : 16,
                  onTap: (_, p) => _setPos(p),
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'uz.saler.ai'),
                  if (pos != null) MarkerLayer(markers: [Marker(point: pos!, width: 44, height: 52, child: Icon(Icons.location_on, color: context.p.danger, size: 44))]),
                ],
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: FloatingActionButton.small(heroTag: 'myloc', onPressed: _myLocation, child: const Icon(Icons.my_location_rounded, size: 18)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: address,
          label: tr('Manzil'),
          icon: Icons.location_on_outlined,
          hint: tr('Masalan: Chorsu bozori, 2-qator'),
          maxLines: 2,
          suffix: addrBusy ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
        ),
        if (pos != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('${pos!.latitude.toStringAsFixed(5)}, ${pos!.longitude.toStringAsFixed(5)}', style: TextStyle(fontSize: 12, color: context.p.muted, fontWeight: FontWeight.w600)),
          ),
      ];

  List<Widget> _courierStep() => [
        AuthLabel(tr('Transport')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in _vehicles)
              ChoiceChip(
                selected: vehicle == v.$1,
                avatar: Icon(v.$2, size: 16, color: vehicle == v.$1 ? context.p.onDark : context.p.text),
                label: Text(tr(v.$3)),
                onSelected: (_) => setState(() => vehicle = v.$1),
              ),
          ]),
        ),
        if (vehicle == 'moto' || vehicle == 'car')
          AuthField(controller: plate, label: tr('Davlat raqami'), icon: Icons.pin_outlined, hint: '01 A 123 BC', caps: TextCapitalization.characters),
        AuthLabel(tr('Ish viloyati')),
        RegionPicker(value: region, label: tr('Viloyat'), onPick: (r) => setState(() => region = r)),
        AuthLabel(tr('Rasm')),
        Row(children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: context.p.bg,
            backgroundImage: photo == null ? null : MemoryImage(base64Decode(photo!.split(',').last)),
            child: photo == null ? Icon(Icons.person_outline_rounded, color: context.p.muted) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton.icon(onPressed: () => _pickImage(isLogo: false), icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: Text(photo == null ? tr("Rasm qo'shish") : tr("O'zgartirish"))),
              Text(tr('Ixtiyoriy — xaridorlar sizni tanishi uchun'), style: TextStyle(fontSize: 11.5, color: context.p.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
      ];

  List<Widget> _truckStep() => [
        AuthLabel(tr('Mashina')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _truckTypes)
              ChoiceChip(
                selected: truck == t.$1,
                avatar: Icon(Icons.local_shipping_rounded, size: 16, color: truck == t.$1 ? context.p.onDark : context.p.text),
                label: Text('${t.$2} · ${t.$3}'),
                onSelected: (_) => setState(() => truck = t.$1),
              ),
          ]),
        ),
        AuthField(controller: plate, label: tr('Davlat raqami'), icon: Icons.pin_outlined, hint: '60 B 777 AA', caps: TextCapitalization.characters),
        AuthField(
          controller: capacity,
          label: tr("Sig'im, kg"),
          icon: Icons.scale_outlined,
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          action: TextInputAction.done,
          onSubmit: _next,
        ),
      ];

  List<Widget> _cargoTariff() => [
        AuthLabel(tr('Tarif')),
        AuthField(
          controller: basePrice,
          label: tr("Boshlang'ich narx, so'm"),
          icon: Icons.payments_outlined,
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        AuthField(
          controller: perKm,
          label: tr("1 km narxi, so'm"),
          icon: Icons.route_outlined,
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(tr('Mijozga narx shu tarif bo\'yicha taxminan hisoblanadi'), style: TextStyle(fontSize: 12, color: context.p.muted, fontWeight: FontWeight.w600)),
        ),
        AuthLabel(tr('Xizmat viloyatlari')),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in kRegions)
            FilterChip(
              selected: regions.contains(r),
              label: Text(r, style: const TextStyle(fontSize: 12)),
              onSelected: (v) => setState(() => v ? regions.add(r) : regions.remove(r)),
            ),
        ]),
        const SizedBox(height: 16),
      ];

  List<Widget> _credentials() => [
        AuthLabel(tr("Kirish ma'lumotlari")),
        AuthField(
          controller: login,
          label: tr('Login'),
          icon: Icons.person_pin_outlined,
          hint: tr('lotin harflari va raqamlar'),
          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]'))],
        ),
        AuthField(
          controller: pass,
          label: tr('Parol'),
          icon: Icons.lock_outline_rounded,
          obscure: hidePass,
          suffix: IconButton(
            icon: Icon(hidePass ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
            onPressed: () => setState(() => hidePass = !hidePass),
          ),
        ),
        AuthField(controller: pass2, label: tr('Parolni takrorlang'), icon: Icons.lock_reset_rounded, obscure: hidePass, action: TextInputAction.done, onSubmit: _next),
      ];
}

/// Manzilni koordinata bo'yicha aniqlash (OpenStreetMap Nominatim)
Future<String?> _reverseGeocode(LatLng p) async {
  try {
    final u = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${p.latitude}&lon=${p.longitude}&accept-language=uz&zoom=18');
    final r = await http.get(u, headers: {'User-Agent': 'SalerAI/1.0 (uz.saler.ai)'}).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    final name = (j['display_name'] ?? '').toString();
    if (name.isEmpty) return null;
    return name.split(',').take(3).join(',').trim();
  } catch (_) {
    return null;
  }
}

/// Sotuvchi, kuryer va yuk tashuvchi hisobiga kirish
class LoginScreen extends StatefulWidget {
  final String role; // seller | courier | cargo
  final VoidCallback onDone;
  const LoginScreen({super.key, required this.role, required this.onDone});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final login = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  bool hide = true;
  String? error;

  bool get seller => widget.role == 'seller';

  @override
  void dispose() {
    login.dispose();
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> go() async {
    if (login.text.trim().isEmpty || email.text.trim().isEmpty || pass.text.isEmpty) {
      setState(() => error = tr('Login, email va parolni kiriting'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final st = AppState.instance;
      if (seller) {
        final r = await Api.instance.post('/api/seller/login', {'login': login.text.trim(), 'email': email.text.trim(), 'password': pass.text});
        st.sellerShop = Shop.fromJson(r['shop']);
        st.courier = null;
        st.refreshBadges();
      } else {
        final r = await Api.instance.post('/api/courier/login', {'login': login.text.trim(), 'email': email.text.trim(), 'password': pass.text, 'type': widget.role});
        st.courier = Courier.fromJson(r['courier']);
        st.sellerShop = null;
      }
      st.refresh();
      Realtime.instance.restart();
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDone();
      return;
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  void _reset() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => ResetPasswordSheet(role: widget.role),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = switch (widget.role) {
      'seller' => tr('Sotuvchi kirishi'),
      'courier' => tr('Kuryer kirishi'),
      _ => tr('Yuk tashuvchi kirishi'),
    };
    return AuthShell(
      title: t,
      subtitle: tr('Hisobingizga tegishli login, email va parolni kiriting'),
      onBack: busy ? null : () => Navigator.of(context).maybePop(),
      children: [
        AuthCard(children: [
          AuthField(controller: login, label: tr('Login'), icon: Icons.person_pin_outlined),
          AuthField(controller: email, label: 'Email', icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress),
          AuthField(
            controller: pass,
            label: tr('Parol'),
            icon: Icons.lock_outline_rounded,
            obscure: hide,
            action: TextInputAction.done,
            onSubmit: go,
            suffix: IconButton(icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20), onPressed: () => setState(() => hide = !hide)),
          ),
          AuthErrorText(error),
          AuthButton(tr('Kirish'), busy: busy, onTap: go, icon: Icons.arrow_forward_rounded),
          const SizedBox(height: 4),
          Center(child: TextButton(onPressed: busy ? null : _reset, child: Text(tr('Parolni unutdingizmi?'), style: TextStyle(fontWeight: FontWeight.w700, color: context.p.accentText)))),
        ]),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: busy
                ? null
                : () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => RegisterScreen(role: widget.role, onDone: widget.onDone))),
            child: Text(tr("Hisobingiz yo'qmi? Ro'yxatdan o'tish"), style: TextStyle(color: authFgSoft(context, .7), fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

/// Parolni email orqali tiklash
class ResetPasswordSheet extends StatefulWidget {
  final String role; // seller | courier | cargo
  const ResetPasswordSheet({super.key, required this.role});
  @override
  State<ResetPasswordSheet> createState() => _ResetPasswordSheetState();
}

class _ResetPasswordSheetState extends State<ResetPasswordSheet> {
  final login = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  bool codeStep = false;
  String? devCode;
  String? error;

  @override
  void dispose() {
    login.dispose();
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body({String? code}) => {
        'role': widget.role,
        'login': login.text.trim(),
        'email': email.text.trim(),
        if (code != null) ...{'code': code, 'password': pass.text},
      };

  Future<String?> _send() async => (await Api.instance.post('/api/auth/reset', _body()))['devCode']?.toString();

  Future<void> _start() async {
    if (login.text.trim().length < 3 || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email.text.trim())) {
      setState(() => error = tr("Login va hisobingizga bog'langan emailni to'g'ri kiriting"));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final d = await _send();
      if (!mounted) return;
      setState(() {
        devCode = d;
        codeStep = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Parolni tiklash'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 4),
          Text(codeStep ? tr('Emailga kelgan kodni kiriting va yangi parol qo\'ying') : tr("Hisobingizga biriktirilgan login va emailni kiriting"),
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          if (!codeStep) ...[
            AuthField(controller: login, label: tr('Login'), icon: Icons.person_pin_outlined),
            AuthField(controller: email, label: 'Email', icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress, action: TextInputAction.done, onSubmit: _start),
            AuthErrorText(error),
            AuthButton(tr('Kodni olish'), busy: busy, onTap: _start, icon: Icons.arrow_forward_rounded),
          ] else ...[
            AuthField(
              controller: pass,
              label: tr('Yangi parol'),
              icon: Icons.lock_reset_rounded,
              obscure: true,
            ),
            CodeStep(
              email: email.text.trim(),
              devCode: devCode,
              buttonLabel: tr('Parolni yangilash'),
              onResend: _send,
              onSubmit: (code) async {
                if (pass.text.length < 6) throw ApiException(tr('Parol kamida 6 belgi'), 400);
                final nav = Navigator.of(context);
                final msg = ScaffoldMessenger.of(context);
                await Api.instance.post('/api/auth/reset', _body(code: code));
                nav.pop();
                msg.showSnackBar(SnackBar(content: Text(tr('Parol yangilandi. Endi yangi parol bilan kiring'))));
              },
            ),
          ],
        ]),
      ),
    );
  }
}
