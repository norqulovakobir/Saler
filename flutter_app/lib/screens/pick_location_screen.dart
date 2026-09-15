import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Xaritada tanlangan nuqta va manzil
class PickedLocation {
  final double lat;
  final double lon;
  final String address;
  const PickedLocation(this.lat, this.lon, this.address);
}

/// Xaritada joy belgilash: pin markazda turadi, xarita suriladi, manzil o'zi topiladi (OSM Nominatim),
/// kerak bo'lsa qo'lda tuzatiladi. "Tasdiqlash" PickedLocation qaytaradi, yopilsa null.
class PickLocationScreen extends StatefulWidget {
  final LatLng? initial;
  final String? address;
  final String title;
  const PickLocationScreen({super.key, this.initial, this.address, this.title = 'Joylashuvni belgilang'});
  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  static const _tashkent = LatLng(41.311, 69.240);
  final map = MapController();
  late LatLng center = widget.initial ?? _tashkent;
  late final addr = TextEditingController(text: widget.address ?? '');
  bool locating = false;
  bool resolving = false;
  bool _edited = false; // manzil qo'lda yozilgan bo'lsa, avtomatik manzil ustiga yozilmaydi
  Timer? _debounce;
  String? error;

  @override
  void initState() {
    super.initState();
    _edited = (widget.address ?? '').isNotEmpty;
    // Joy berilmagan bo'lsa, foydalanuvchining hozirgi joyidan boshlanadi (xarita chizilgach)
    if (widget.initial == null) WidgetsBinding.instance.addPostFrameCallback((_) => _locate(silent: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    addr.dispose();
    super.dispose();
  }

  void _moved(MapCamera cam, bool gesture) {
    center = cam.center;
    if (!gesture) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _reverse);
    setState(() {});
  }

  /// Koordinatadan manzil (ko'cha, uy, tuman)
  Future<void> _reverse() async {
    if (_edited) return;
    final c = center;
    setState(() => resolving = true);
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${c.latitude}&lon=${c.longitude}&accept-language=uz,ru');
      final r = await http.get(uri, headers: {'User-Agent': 'SalerAI/1.0 (uz.saler.ai)'}).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final a = j['address'];
        var name = '';
        if (a is Map) {
          final parts = [a['road'], a['house_number'], a['neighbourhood'] ?? a['suburb'], a['city'] ?? a['town'] ?? a['village'] ?? a['county']]
              .where((x) => x != null && '$x'.isNotEmpty)
              .map((x) => '$x')
              .toList();
          name = parts.join(', ');
        }
        if (name.isEmpty) name = j['display_name']?.toString() ?? '';
        if (mounted && !_edited && c == center && name.isNotEmpty) addr.text = name;
      }
    } catch (_) {}
    if (mounted) setState(() => resolving = false);
  }

  Future<void> _locate({bool silent = false}) async {
    setState(() {
      locating = true;
      error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silent) await Geolocator.openLocationSettings();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (!silent && mounted) setState(() => error = tr('Joylashuvga ruxsat berilmadi'));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)).timeout(const Duration(seconds: 15));
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      center = ll;
      try {
        map.move(ll, 16);
      } catch (_) {}
      _reverse();
    } catch (_) {
      if (!silent && mounted) setState(() => error = tr("Joylashuvni aniqlab bo'lmadi"));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void _confirm() {
    final a = addr.text.trim();
    if (a.length < 3) {
      setState(() => error = tr("Manzilni yozing (ko'cha, uy, mo'ljal)"));
      return;
    }
    Navigator.of(context).pop(PickedLocation(center.latitude, center.longitude, a));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: map,
          options: MapOptions(initialCenter: center, initialZoom: widget.initial != null ? 15 : 12, onPositionChanged: _moved),
          children: [TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'uz.saler.ai')],
        ),
        // Pin har doim markazda: uchi xarita markaziga tushadi
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 46),
              child: Icon(Icons.location_on_rounded, size: 46, color: p.accent, shadows: const [Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))]),
            ),
          ),
        ),
        Positioned(top: pad.top + 10, left: 14, child: IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop())),
        Positioned(
          top: pad.top + 10,
          left: 66,
          right: 14,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), boxShadow: softShadow(context)),
            child: Text(tr(widget.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 236 + pad.bottom,
          child: FloatingActionButton.small(
            heroTag: 'pick-loc',
            backgroundColor: p.card,
            foregroundColor: p.text,
            onPressed: locating ? null : () => _locate(),
            child: locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(18, 16, 18, pad.bottom + 16),
            decoration: BoxDecoration(
                color: p.card,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 30, offset: const Offset(0, -6))]),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr("Xaritani surib, pinni kerakli joyga qo'ying"), style: TextStyle(fontSize: 12.5, color: p.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: addr,
                onChanged: (_) {
                  _edited = true;
                  if (error != null) setState(() => error = null);
                },
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Manzil'),
                  hintText: tr("Ko'cha, uy, mo'ljal"),
                  prefixIcon: const Icon(Icons.place_outlined, size: 20),
                  suffixIcon: resolving ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                  errorText: error,
                ),
              ),
              const SizedBox(height: 6),
              Text('${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}', style: TextStyle(fontSize: 11, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _confirm,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.check_rounded),
                label: Text(tr('Tasdiqlash')),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
