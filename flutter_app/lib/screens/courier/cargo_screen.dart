import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api.dart';
import '../auth/buyer_auth.dart';
import '../../l10n.dart';
import '../../main.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'courier_home.dart' show cargoVehicleName, cargoVehicleIcon, fmtKm;

/// Viloyatlararo yuk: tashuvchilar ro'yxati (viloyat filtri bilan) va mashina buyurtma qilish
class CargoScreen extends StatefulWidget {
  const CargoScreen({super.key});
  @override
  State<CargoScreen> createState() => _CargoScreenState();
}

class _CargoScreenState extends State<CargoScreen> {
  List<String> regions = [];
  List<Courier> carriers = [];
  List<CargoOrder> mine = [];
  String? from;
  String? to;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      regions = ((await Api.instance.get('/api/cargo/regions')) as List).cast<String>();
    } catch (_) {}
    await load();
  }

  Future<void> load() async {
    try {
      final q = [if (from != null) 'from=${Uri.encodeComponent(from!)}', if (to != null) 'to=${Uri.encodeComponent(to!)}'].join('&');
      final r = await Api.instance.get('/api/cargo/carriers${q.isEmpty ? '' : '?$q'}');
      carriers = (r as List).map((e) => Courier.fromJson(e)).toList();
      mine = ((await Api.instance.get('/api/cargo/my')) as List).map((e) => CargoOrder.fromJson(e)).toList();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pickRegion(bool isFrom) async {
    final v = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (c) => ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), shrinkWrap: true, children: [
        Text(isFrom ? tr('Qayerdan') : tr('Qayerga'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
        const SizedBox(height: 8),
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.clear_rounded, color: c.p.muted), title: Text(tr('Barchasi')), onTap: () => Navigator.pop(c, '')),
        for (final r in regions) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.place_outlined, color: c.p.accentText), title: Text(r, style: const TextStyle(fontWeight: FontWeight.w700)), onTap: () => Navigator.pop(c, r)),
      ]),
    );
    if (v == null) return;
    setState(() {
      if (isFrom) {
        from = v.isEmpty ? null : v;
      } else {
        to = v.isEmpty ? null : v;
      }
      loading = true;
    });
    load();
  }

  /// Buyurtma formasi: yuk tavsifi, og'irligi, sana, telefon
  Future<void> order(Courier c) async {
    final ok = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CargoOrderSheet(carrier: c, from: from, to: to, allRegions: regions),
    );
    if (ok == true && mounted) {
      load();
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (d) => AlertDialog(
          icon: Container(width: 56, height: 56, decoration: BoxDecoration(color: d.p.successSoft, borderRadius: BorderRadius.circular(18)), child: Icon(Icons.check_rounded, color: d.p.success, size: 30)),
          title: Text(tr('Buyurtma yuborildi!'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          content: Text('${c.name} ${tr("tez orada siz bilan bog'lanadi.")}', textAlign: TextAlign.center, style: TextStyle(color: d.p.muted)),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: Text(tr('Yopish')))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: Padding(padding: const EdgeInsets.only(left: 12), child: IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop())), leadingWidth: 60, title: Text(tr('Viloyatlararo yuk'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
          DarkBanner(
            glow: const Color(0xFFFF8A00),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Yuk mashinasi buyurtma qiling'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
              const SizedBox(height: 6),
              Text(tr("Labo, Damas, Gazel, Isuzu yoki fura — viloyatlar aro. Tashuvchini tanlang, u siz bilan bog'lanadi."), style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _FilterBtn(Icons.trip_origin_rounded, from ?? tr('Qayerdan'), from != null, () => _pickRegion(true))),
            const SizedBox(width: 8),
            Expanded(child: _FilterBtn(Icons.place_rounded, to ?? tr('Qayerga'), to != null, () => _pickRegion(false))),
          ]),
          if (mine.isNotEmpty) ...[
            SectionTitle(tr('Mening yuk buyurtmalarim')),
            for (final o in mine.take(5)) _MyCargo(o),
          ],
          SectionTitle(tr('Tashuvchilar')),
          if (loading)
            const Column(children: [Skeleton(height: 130, radius: 20), SizedBox(height: 10), Skeleton(height: 130, radius: 20)])
          else if (carriers.isEmpty)
            EmptyBox(Icons.local_shipping_outlined, tr("Bu yo'nalishda hozircha tashuvchi yo'q"))
          else
            for (var i = 0; i < carriers.length; i++) FadeIn(index: i, child: _CarrierCard(carriers[i], onOrder: () => order(carriers[i]))),
        ]),
      ),
    );
  }
}

/// Yuk mashinasi buyurtma oynasi. Yuborilsa true qaytadi.
class _CargoOrderSheet extends StatefulWidget {
  final Courier carrier;
  final String? from;
  final String? to;
  final List<String> allRegions;
  const _CargoOrderSheet({required this.carrier, this.from, this.to, required this.allRegions});
  @override
  State<_CargoOrderSheet> createState() => _CargoOrderSheetState();
}

class _CargoOrderSheetState extends State<_CargoOrderSheet> {
  final f = {for (final k in ['cargo', 'weight', 'date', 'name', 'phone', 'address']) k: TextEditingController()};
  late final List<String> options = widget.carrier.regions.isNotEmpty ? widget.carrier.regions : widget.allRegions;
  // Viloyat faqat foydalanuvchi filtrda o'zi tanlagan bo'lsa oldindan qo'yiladi — aks holda aniq tanlash shart
  late String? fromR = options.contains(widget.from) ? widget.from : null;
  late String? toR = options.contains(widget.to) ? widget.to : null;
  bool sending = false;
  String? err;

  @override
  void initState() {
    super.initState();
    f['name']!.text = Api.instance.userName == 'Xaridor' ? '' : Api.instance.userName;
  }

  @override
  void dispose() {
    for (final x in f.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (sending) return;
    // Buyurtma berish uchun tasdiqlangan xaridor hisobi kerak
    if (!await ensureBuyer(context, title: tr('Buyurtma berish uchun kiring'))) return;
    if (!mounted) return;
    if (fromR == null || toR == null) {
      setState(() => err = tr('Viloyatlarni tanlang'));
      return;
    }
    setState(() {
      sending = true;
      err = null;
    });
    try {
      await Api.instance.post('/api/cargo/orders', {
        'carrierId': widget.carrier.id,
        'fromRegion': fromR,
        'toRegion': toR,
        'cargo': f['cargo']!.text,
        'weightKg': int.tryParse(f['weight']!.text) ?? 0,
        'date': f['date']!.text,
        'address': f['address']!.text,
        'name': f['name']!.text,
        'phone': f['phone']!.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Xato oyna ichida ko'rsatiladi (bottom sheet ustida snackbar ko'rinmaydi)
      if (mounted) {
        setState(() {
          sending = false;
          err = e is ApiException ? e.message : tr("Serverga ulanib bo'lmadi. Internetni tekshiring.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = widget.carrier;
    // Taxminiy narx faqat filtrdagi yo'nalish uchun hisoblangan
    final showEstimate = c.estimatedPrice != null && fromR == widget.from && toR == widget.to;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Yuk mashinasi buyurtma qilish'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 4),
          Text('${c.name} · ${cargoVehicleName(c.vehicleType)}${c.capacityKg > 0 ? ' · ${c.capacityKg} kg' : ''}', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _RegionBtn(tr('Qayerdan'), fromR, options, (v) => setState(() => fromR = v))),
            const SizedBox(width: 8),
            Expanded(child: _RegionBtn(tr('Qayerga'), toR, options, (v) => setState(() => toR = v))),
          ]),
          if (showEstimate) ...[
            const SizedBox(height: 8),
            Text("${tr('Taxminiy narx')}: ~ ${fmtPrice(c.estimatedPrice!)} so'm${c.routeKm != null ? ' · ${fmtKm(c.routeKm!)}' : ''}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.accentText)),
          ],
          const SizedBox(height: 10),
          TextField(controller: f['cargo'], decoration: InputDecoration(labelText: tr('Yuk (nima tashiladi)'), prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: f['weight'], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Og'irligi, kg"), prefixIcon: const Icon(Icons.scale_outlined, size: 20)))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: f['date'], decoration: InputDecoration(labelText: tr('Sana'), hintText: '20.09', prefixIcon: const Icon(Icons.event_outlined, size: 20)))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: f['address'], decoration: InputDecoration(labelText: tr('Yuklash manzili'), prefixIcon: const Icon(Icons.place_outlined, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: f['name'], decoration: InputDecoration(labelText: tr('Ismingiz'), prefixIcon: const Icon(Icons.person_outline_rounded, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: f['phone'], keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon raqam'), hintText: '+998 90 123 45 67', prefixIcon: const Icon(Icons.phone_outlined, size: 20))),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: TextStyle(fontSize: 13, color: p.danger, fontWeight: FontWeight.w700))),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: sending ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.muted)) : const Icon(Icons.local_shipping_rounded, size: 18),
            label: Text(tr('Buyurtma berish')),
            onPressed: sending ? null : submit,
          ),
          const SizedBox(height: 8),
          Center(child: Text(tr("Tashuvchi siz bilan bog'lanib, narxni kelishib oladi"), style: TextStyle(fontSize: 12, color: p.muted))),
        ]),
      ),
    );
  }
}

class _FilterBtn extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool active;
  final VoidCallback onTap;
  const _FilterBtn(this.icon, this.text, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: active ? p.dark : p.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: active ? null : softShadow(context, y: 4, blur: 14)),
          child: Row(children: [
            Icon(icon, size: 18, color: active ? p.accent : p.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: active ? p.onDark : p.text))),
            Icon(Icons.expand_more_rounded, size: 18, color: active ? p.onDark : p.muted),
          ]),
        ),
      ),
    );
  }
}

class _RegionBtn extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _RegionBtn(this.label, this.value, this.options, this.onChanged);
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: options.contains(value) ? value : null,
        isExpanded: true,
        hint: Text(tr('Tanlang'), overflow: TextOverflow.ellipsis),
        decoration: InputDecoration(labelText: label),
        items: [for (final r in options) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => v == null ? null : onChanged(v),
      );
}

class _CarrierCard extends StatelessWidget {
  final Courier c;
  final VoidCallback onOrder;
  const _CarrierCard(this.c, {required this.onOrder});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProviderAvatar(photo: c.photo, icon: cargoVehicleIcon(c.vehicleType), role: 'cargo', size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.online ? p.successSoft : p.bg, borderRadius: BorderRadius.circular(99)), child: Text(c.online ? tr('Onlayn') : tr('Oflayn'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c.online ? p.success : p.muted))),
              ]),
              Text('${cargoVehicleName(c.vehicleType)}${c.capacityKg > 0 ? ' · ${c.capacityKg} kg' : ''}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              // Reyting o'rniga haqiqiy bajarilgan reyslar soni
              Row(children: [
                Icon(Icons.local_shipping_outlined, size: 13, color: p.muted),
                const SizedBox(width: 4),
                Text(c.deliveries > 0 ? '${c.deliveries} ${tr('reys')}' : tr('Yangi'), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ]),
        if (c.regions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final r in c.regions) Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(99)), child: Text(r, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))]),
        ],
        if (c.basePrice > 0 || c.pricePerKm > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.payments_outlined, size: 16, color: p.accentText),
            const SizedBox(width: 6),
            Text([if (c.basePrice > 0) '${tr('dan')} ${fmtPrice(c.basePrice)} so\'m', if (c.pricePerKm > 0) '${fmtPrice(c.pricePerKm)} so\'m/km'].join(' · '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accentText)),
          ]),
        ],
        // Tanlangan yo'nalish uchun taxminiy narx va masofa
        if (c.estimatedPrice != null || c.routeKm != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.route_rounded, size: 16, color: p.accentText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  [if (c.estimatedPrice != null) "~ ${fmtPrice(c.estimatedPrice!)} so'm", if (c.routeKm != null) fmtKm(c.routeKm!)].join(' · '),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.text),
                ),
              ),
            ]),
          ),
        ],
        if (c.about.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.about, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: .8)))),
        const SizedBox(height: 12),
        Row(children: [
          IconBtn(Icons.phone_outlined, size: 44, bg: p.successSoft, color: p.success, onTap: () => launchUrl(Uri.parse('tel:${c.phone}'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)), icon: const Icon(Icons.local_shipping_rounded, size: 18), label: Text(tr('Mashina buyurtma qilish')), onPressed: onOrder)),
        ]),
      ]),
    );
  }
}

class _MyCargo extends StatelessWidget {
  final CargoOrder o;
  const _MyCargo(this.o);
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (label, color) = switch (o.status) { 'accepted' => (tr('Qabul qilindi'), p.success), 'done' => (tr('Yetkazildi'), p.success), 'rejected' => (tr('Rad etildi'), p.danger), _ => (tr('Kutilmoqda'), p.accentText) };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.local_shipping_outlined, color: p.accentText, size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o.fromRegion} → ${o.toRegion}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            Text('${o.carrierName}${o.cargo.isNotEmpty ? ' · ${o.cargo}' : ''}${o.date.isNotEmpty ? ' · ${o.date}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
          ]),
        ),
        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11))),
        if (o.carrierPhone.isNotEmpty) ...[const SizedBox(width: 6), IconBtn(Icons.phone_outlined, size: 34, bg: p.bg, color: p.success, onTap: () => launchUrl(Uri.parse('tel:${o.carrierPhone}')))],
      ]),
    );
  }
}
