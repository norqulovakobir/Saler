import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api.dart';
import '../../state.dart';
import '../../config.dart';
import '../../l10n.dart';
import '../../main.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'seller_home.dart';

/// Analitika — Mini App'dagi bilan bir xil bo'limlar va tartib
class AnalyticsTab extends StatefulWidget {
  final VoidCallback onExit;
  /// "Yangi buyurtmalarni ko'rish" — SellerHome'dagi Buyurtmalar tabiga o'tkazadi
  final VoidCallback? onOpenOrders;
  const AnalyticsTab({super.key, required this.onExit, this.onOpenOrders});
  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  static const _path = '/api/seller/analytics';
  static const _aiPath = '/api/seller/analytics/ai-summary';

  // Keshdagi ma'lumot darhol ko'rsatiladi, fonda yangilanadi
  dynamic data = Api.instance.cached(_path);
  String? error;
  bool loading = false;

  // AI xulosa alohida yuklanadi: xato bo'lsa ham tab ishlayveradi
  dynamic ai = Api.instance.cached(_aiPath);
  bool aiLoading = false;
  bool aiFailed = false;

  int period = 7;
  bool pdfBusy = false;
  bool _ready = false;
  static const week = ['Ya', 'Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh'];
  static const monthsUz = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];

  @override
  void initState() {
    super.initState();
    load();
    loadAi();
    _ready = true;
    AppState.instance.addListener(_onLive);
  }

  // Pul tushsa yoki buyurtma o'zgarsa analitika joyida yangilanadi (ketma-ket hodisalarda bir marta)
  int _seenLive = AppState.instance.liveVersion;
  Timer? _liveDebounce;
  void _onLive() {
    final st = AppState.instance;
    if (st.liveVersion == _seenLive) return;
    _seenLive = st.liveVersion;
    final t = st.lastEvent?.type ?? '';
    if (!(t == 'money' || t.startsWith('order:'))) return;
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    AppState.instance.removeListener(_onLive);
    super.dispose();
  }

  /// initState ichida setState chaqirib bo'lmaydi — u paytda qiymat to'g'ridan-to'g'ri o'zgaradi
  void _update(VoidCallback fn) => _ready ? setState(fn) : fn();

  /// Analitikani yuklash. manual — foydalanuvchi tortib yangiladi (xato bo'lsa xabar chiqadi)
  Future<void> load({bool manual = false}) async {
    if (loading) return;
    _update(() => loading = true);
    try {
      final r = await Api.instance.get(_path);
      if (!mounted) return;
      setState(() {
        data = r;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = sellerErrorText(e);
        loading = false;
      });
      // Eski ma'lumot ekranda qoladi, faqat xabar ko'rsatiladi
      if (manual && data != null) showToast(context, error!, error: true);
    }
  }

  /// AI xulosa. refresh — serverda qayta yaratish (?refresh=1)
  Future<void> loadAi({bool refresh = false}) async {
    if (aiLoading) return;
    _update(() {
      aiLoading = true;
      aiFailed = false;
    });
    try {
      final r = await Api.instance.get(refresh ? '$_aiPath?refresh=1' : _aiPath);
      if (!mounted) return;
      setState(() {
        ai = r;
        aiLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        aiFailed = true;
        aiLoading = false;
      });
    }
  }

  int pct(num a, num b) => b == 0 ? 0 : ((a / b) * 100).round();
  int n(dynamic v) => (v is num) ? v.round() : 0;
  String monthName(String key) {
    // Postgres date_trunc ayrim drayverlarda "2026-09", ayrimlarida esa
    // faqat yilni qaytarishi mumkin. Hisobotning o'zi xatoga tushmasligi
    // uchun qism yetarli bo'lmaganda xavfsiz sarlavha qaytaramiz.
    final match = RegExp(r'^(\\d{4})-(\\d{1,2})').firstMatch(key.trim());
    final month = int.tryParse(match?.group(2) ?? '');
    if (match == null || month == null || month < 1 || month > 12) {
      return key.trim().isEmpty ? tr('Bu oy') : key;
    }
    return '${monthsUz[month - 1]} ${match.group(1)}';
  }

  // ---- kichik komponentlar ----
  Widget card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        padding: padding,
        decoration: BoxDecoration(color: context.p.card, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: context.p.border) : null),
        child: child,
      );

  Widget stat(IconData ic, Color c, Color soft, String v, String l) => card(
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)), child: Icon(ic, size: 20, color: c)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.5, height: 1.1)),
            Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.p.muted, fontWeight: FontWeight.w700)),
          ])),
        ]),
      );

  Widget section(IconData ic, String title, Widget body) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
            child: Row(children: [Icon(ic, size: 16, color: context.p.text), const SizedBox(width: 6), Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))])),
        body,
      ]);

  Widget badge(String text, Color c, {IconData? ic}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ic != null) ...[Icon(ic, size: 12, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11))
        ]),
      );

  /// Gorizontal ustunli ro'yxat (Mini App'dagi hbars)
  Widget hbars(List<({String label, num v, String text, String? sub})> items, {Color? color}) {
    final p = context.p;
    final max = items.fold<num>(1, (m, i) => i.v > m ? i.v : m);
    final c = color ?? p.accent;
    return Column(children: [
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(i.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Text(i.text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))
            ]),
            const SizedBox(height: 5),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                    height: 7,
                    child: Stack(children: [
                      Container(color: p.border),
                      FractionallySizedBox(widthFactor: (i.v / max).clamp(.02, 1).toDouble(), child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))))
                    ]))),
            if (i.sub != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(i.sub!, style: TextStyle(fontSize: 11, color: p.muted))),
          ]),
        ),
    ]);
  }

  Widget listCard(List<Widget> rows) => card(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[rows[i], if (i < rows.length - 1) Divider(height: 1, color: context.p.border)]
      ]));

  Widget listItem({Widget? leading, required Widget title, Widget? subtitle, Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, if (subtitle != null) subtitle])),
          if (trailing != null) ...[const SizedBox(width: 10), trailing],
        ]),
      );

  /// Chiziqli diagramma (7 kun — kun nomlari, 30 kun — har 5-kun)
  Widget chart(List days) {
    final p = context.p;
    final wide = days.length <= 7;
    final today = DateTime.now();
    final values = [for (final x in days) n(x['n'])];
    final todayIdx = days.indexWhere((x) {
      final dt = DateTime.parse(x['date']);
      return dt.year == today.year && dt.month == today.month && dt.day == today.day;
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          height: 140,
          child: CustomPaint(size: Size.infinite, painter: _LinePainter(values: values, todayIdx: todayIdx, line: p.accent, today: p.success, grid: p.border, label: p.text, showValues: wide))),
      const SizedBox(height: 6),
      // X o'qi: har bir katak markazi diagramma nuqtasiga to'g'ri keladi
      Row(children: [
        for (var i = 0; i < days.length; i++)
          Expanded(child: Builder(builder: (_) {
            final dt = DateTime.parse(days[i]['date']);
            final isToday = i == todayIdx;
            // 30 kunda faqat har 5-kun (oxirgi kundan sanab) — yozuvlar ustma-ust tushmaydi
            final show = wide || (days.length - 1 - i) % 5 == 0;
            final boxH = wide ? 28.0 : 14.0;
            if (!show) return SizedBox(height: boxH);
            // Tor katakda sana ikki qatorga bo'linmasin — OverflowBox markazda kengroq joy beradi
            return SizedBox(
              height: boxH,
              child: OverflowBox(
                maxWidth: 40,
                alignment: Alignment.topCenter,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (wide) Text(week[dt.weekday % 7], maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isToday ? p.success : p.muted, height: 1.1)),
                  Text('${dt.day}', maxLines: 1, style: TextStyle(fontSize: 10, color: isToday ? p.success : p.muted.withValues(alpha: .8), height: 1.1))
                ]),
              ),
            );
          })),
      ]),
      const SizedBox(height: 8),
      Row(children: [_legend(p.accent, tr('Buyurtmalar')), const SizedBox(width: 14), _legend(p.success, tr('Bugun'))]),
    ]);
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(t, style: TextStyle(fontSize: 12, color: context.p.muted))
      ]);

  Future<void> downloadPdf() async {
    setState(() => pdfBusy = true);
    await downloadReport(context);
    if (mounted) setState(() => pdfBusy = false);
  }

  String _short(String s) => s.length <= 2 ? s : s.substring(0, 2);

  /// AI xulosa kartasi: 2-3 gaplik xulosa va belgilar (yaxshi / diqqat / g'oya)
  Widget aiCard() {
    final p = context.p;
    const violet = Color(0xFF7C5CFF);
    final amber = context.isDark ? const Color(0xFFFFB547) : const Color(0xFFA86F00);
    final raw = ai;
    final m = raw is Map ? raw : const {};
    final summary = '${m['summary'] ?? ''}'.trim();
    final hl = m['highlights'];
    final highlights = (hl is List ? hl : const []).whereType<Map>().where((h) => '${h['text'] ?? ''}'.trim().isNotEmpty).toList();
    final at = DateTime.tryParse('${m['generatedAt'] ?? ''}');
    final empty = summary.isEmpty && highlights.isEmpty;
    return card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: violet.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome, size: 17, color: violet)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('AI xulosa'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (at != null) Text(fmtTime(at), style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w600)),
          ])),
          // Yangilash tugmasi: so'rov davomida aylanuvchi indikator
          aiLoading
              ? const SizedBox(width: 34, height: 34, child: Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: violet)))
              : IconBtn(Icons.refresh_rounded, size: 34, bg: p.bg, color: p.muted, onTap: () => loadAi(refresh: true)),
        ]),
        const SizedBox(height: 10),
        if (empty && aiLoading) ...[
          const Skeleton(height: 12, radius: 6),
          const SizedBox(height: 6),
          const Skeleton(height: 12, width: 180, radius: 6),
        ] else if (empty)
          Text(aiFailed ? tr("AI xulosani hozir olib bo'lmadi") : tr("Xulosa uchun hozircha ma'lumot yetarli emas"),
              style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))
        else ...[
          if (summary.isNotEmpty) Text(summary, style: TextStyle(fontSize: 13, height: 1.45, color: p.text.withValues(alpha: .88), fontWeight: FontWeight.w500)),
          for (final h in highlights)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(switch ('${h['type']}') { 'good' => Icons.check_circle_rounded, 'warn' => Icons.warning_amber_rounded, _ => Icons.lightbulb_outline_rounded },
                    size: 17, color: switch ('${h['type']}') { 'good' => p.success, 'warn' => amber, _ => violet }),
                const SizedBox(width: 8),
                Expanded(child: Text('${h['text']}'.trim(), style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600))),
              ]),
            ),
          if (aiFailed)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr("Yangilab bo'lmadi, keyinroq urinib ko'ring"), style: TextStyle(fontSize: 11, color: p.muted))),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      body: RefreshIndicator(
        // Tortib yangilash so'rovlar tugaguncha kutadi
        onRefresh: () => Future.wait([load(manual: true), loadAi()]),
        child: Builder(
          builder: (_) {
            if (data == null) {
              // Kesh yo'q: yuklanmoqda (skelet) yoki xato (qayta urinish)
              return ListView(padding: EdgeInsets.zero, physics: const AlwaysScrollableScrollPhysics(), children: [
                SellerHeader(tr('Analitika'), onExit: widget.onExit),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, navPad),
                  child: error != null && !loading
                      ? EmptyBox(Icons.cloud_off_rounded, error!,
                          action: FilledButton.icon(onPressed: load, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))))
                      : const Column(children: [Skeleton(height: 70), SizedBox(height: 10), Skeleton(height: 70), SizedBox(height: 10), Skeleton(height: 240)]),
                ),
              ]);
            }
            final d = data;
            final s = d['stats'];
            final weekN = n(d['week']?['n']), prevN = n(d['prev']?['n']);
            final tm = d['thisMonth'], pm = d['prevMonth'];
            final days = (period == 30 ? d['byDay30'] : d['byDay']) as List;
            final daysN = days.fold<int>(0, (a, x) => a + n(x['n']));
            final daysSum = days.fold<num>(0, (a, x) => a + (x['sum'] ?? 0));
            final best = days.fold<Map?>(null, (b, x) => n(x['n']) > n(b?['n']) ? x : b);
            final topSold = (d['topSold'] as List? ?? const []);
            final customers = (d['customers'] as List? ?? const []);
            final recent = (d['recent'] as List? ?? const []);
            final st = d['status'] ?? {};
            final hourBlocks = (d['hourBlocks'] as List? ?? const []);
            final byWeekday = (d['byWeekday'] as List? ?? const []);
            final wdMax = byWeekday.fold<int>(1, (m, w) => n(w['n']) > m ? n(w['n']) : m);
            final top = (d['top'] as List? ?? const []).map((e) => Product.fromJson(e)).where((e) => e.views > 0).toList();
            final unsold = (d['unsold'] as List? ?? const []).map((e) => Product.fromJson(e)).toList();
            final tips = (d['tips'] as List? ?? const []).map((e) => Tip.fromJson(e)).toList();
            final totalOrders = n(s['totalOrders']);
            const violet = Color(0xFF7C5CFF), violetSoft = Color(0xFFEFEAFF), amber = Color(0xFFA86F00), amberSoft = Color(0xFFFFF1E0);

            return ListView(padding: EdgeInsets.zero, physics: const AlwaysScrollableScrollPhysics(), children: [
              SellerHeader(tr('Analitika'), onExit: widget.onExit),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, navPad),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // ---- Bu oy sotuv (qora banner) ----
                  if (tm != null) ...[
                    DarkBanner(
                      glow: const Color(0xFF1F9D6A),
                      glow2: const Color(0xFF1F9D6A),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${tr('Bu oy sotuv')} · ${monthName('${tm['month']}')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB7C0CC))),
                        const SizedBox(height: 4),
                        PriceText(tm['sumDone'] ?? 0, size: 32, color: Colors.white),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(pm != null && n(pm['total']) > 0 && n(tm['total']) < n(pm['total']) ? Icons.trending_down_rounded : Icons.trending_up_rounded, size: 14, color: const Color(0xFF7EE2B0)),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  "${n(tm['total'])} ta buyurtma${pm != null && n(pm['total']) > 0 ? " · o'tgan oyga nisbatan ${n(tm['total']) >= n(pm['total']) ? '+' : ''}${pct(n(tm['total']) - n(pm['total']), n(pm['total']))}%" : ''}",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7EE2B0)))),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _monthBox(const Color(0xFF7EE2B0), '${n(tm['done'])}', '${tr('Sotildi')} · ${pct(n(tm['done']), n(tm['total']))}%', onDark: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _monthBox(const Color(0xFFFF8A8E), '${n(tm['cancelled'])}', '${tr('Bekor')} · ${pct(n(tm['cancelled']), n(tm['total']))}%', onDark: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _monthBox(const Color(0xFFFFD166), '${n(tm['new'])}', tr('Kutilmoqda'), onDark: true)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // ---- AI xulosa ----
                  aiCard(),
                  const SizedBox(height: 10),
                  // ---- 6 ta ko'rsatkich ----
                  Row(children: [
                    Expanded(child: stat(Icons.receipt_long_outlined, p.accent, p.accentSoft, '${n(s['newOrders'])}', tr('Yangi buyurtma'))),
                    const SizedBox(width: 10),
                    Expanded(child: stat(Icons.account_balance_wallet_outlined, p.success, p.successSoft, fmtPrice(s['revenue'] ?? 0), tr("Sotuv, so'm")))
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: stat(Icons.person_outline_rounded, violet, violetSoft, '${n(s['customers'])}', tr('Xaridorlar'))),
                    const SizedBox(width: 10),
                    Expanded(child: stat(Icons.shopping_bag_outlined, violet, violetSoft, '${n(s['unitsSold'])}', tr('Sotilgan dona')))
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: stat(Icons.account_balance_wallet_outlined, amber, amberSoft, fmtPrice(s['avgCheck'] ?? 0), tr("O'rtacha chek"))),
                    const SizedBox(width: 10),
                    Expanded(child: stat(Icons.visibility_outlined, amber, amberSoft, fmtPrice(s['views'] ?? 0), "${tr("Ko'rish")} · ${s['conversion'] ?? 0}% konv."))
                  ]),

                  // ---- Buyurtmalar dinamikasi ----
                  const SizedBox(height: 10),
                  card(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('Buyurtmalar dinamikasi'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text(
                              "$daysN ta buyurtma · ${fmtPrice(daysSum)} so'm${best != null && n(best['n']) > 0 ? ' · eng yaxshi kun: ${DateTime.parse(best['date']).day}-kun (${n(best['n'])})' : ''}",
                              style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                        ])),
                        if (prevN > 0)
                          badge('${weekN >= prevN ? '+' : ''}${pct(weekN - prevN, prevN)}%', weekN >= prevN ? p.success : p.danger,
                              ic: weekN >= prevN ? Icons.trending_up_rounded : Icons.error_outline_rounded),
                      ]),
                      const SizedBox(height: 12),
                      ChoiceChips(items: [('7', tr('7 kun')), ('30', tr('30 kun'))], value: '$period', onChanged: (v) => setState(() => period = int.parse(v))),
                      const SizedBox(height: 14),
                      if (daysN == 0)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Center(child: Text(tr("Bu davrda buyurtma bo'lmadi — do'kon havolasini ulashing"), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13))))
                      else
                        chart(days),
                    ]),
                  ),

                  // ---- Eng ko'p sotilgan ----
                  if (topSold.isNotEmpty)
                    section(
                        Icons.local_fire_department_outlined,
                        tr("Eng ko'p sotilgan"),
                        card(
                            child: hbars([
                          for (final x in topSold.take(5))
                            (
                              label: '${x['name']}',
                              v: n(x['qty']),
                              text: '${n(x['qty'])} dona',
                              sub: "${n(x['orders'])} ta buyurtma · ${fmtPrice(x['sum'] ?? 0)} so'm · ${pct(n(x['qty']), n(s['unitsSold']))}%"
                            ),
                        ]))),

                  // ---- Eng faol xaridorlar ----
                  if (customers.isNotEmpty)
                    section(
                        Icons.person_outline_rounded,
                        tr('Eng faol xaridorlar'),
                        listCard([
                          for (var i = 0; i < customers.length && i < 5; i++)
                            listItem(
                              leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(10)),
                                  alignment: Alignment.center,
                                  child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: p.accent))),
                              title: Text('${customers[i]['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  "${n(customers[i]['orders'])} ta buyurtma · ${fmtPrice(customers[i]['sum'] ?? 0)} so'm · oxirgi ${fmtTime(DateTime.tryParse('${customers[i]['last']}') ?? DateTime.now())}",
                                  style: TextStyle(fontSize: 12, color: p.muted)),
                              trailing: (customers[i]['phone'] ?? '').toString().isNotEmpty
                                  ? IconBtn(Icons.phone_outlined, size: 36, bg: p.successSoft, color: p.success, onTap: () => launchUrl(Uri.parse('tel:${customers[i]['phone']}')))
                                  : null,
                            ),
                        ])),

                  // ---- Oxirgi sotuvlar ----
                  if (recent.isNotEmpty)
                    section(
                        Icons.bolt_rounded,
                        tr('Oxirgi sotuvlar'),
                        listCard([
                          for (final o in recent.take(3))
                            listItem(
                              title: Text('${o['productName']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${o['customerName']} · ${fmtTime(DateTime.tryParse('${o['createdAt']}') ?? DateTime.now())}', style: TextStyle(fontSize: 12, color: p.muted)),
                              trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(fmtPrice(o['price'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                StatusBadge('${o['status']}', const {'new': 'Yangi', 'done': 'Bajarildi', 'cancelled': 'Bekor'}['${o['status']}'] ?? '${o['status']}')
                              ]),
                            ),
                        ])),

                  // ---- Buyurtmalar holati ----
                  if (totalOrders > 0)
                    section(
                        Icons.check_circle_outline_rounded,
                        tr('Buyurtmalar holati'),
                        card(
                            child: hbars([
                          (label: 'Bajarilgan', v: n(st['done']), text: '${n(st['done'])} · ${pct(n(st['done']), totalOrders)}%', sub: "${fmtPrice(st['sums']?['done'] ?? 0)} so'm"),
                          (label: 'Yangi (kutmoqda)', v: n(st['new']), text: '${n(st['new'])} · ${pct(n(st['new']), totalOrders)}%', sub: null),
                          (label: 'Bekor qilingan', v: n(st['cancelled']), text: '${n(st['cancelled'])} · ${pct(n(st['cancelled']), totalOrders)}%', sub: null),
                        ], color: p.success))),

                  // ---- Faol vaqtlar ----
                  if (totalOrders > 0)
                    section(
                        Icons.auto_awesome_outlined,
                        tr('Faol vaqtlar'),
                        card(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (d['peakHour'] != null || d['bestWeekday'] != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: p.muted), children: [
                                    if (d['peakHour'] != null) ...[
                                      TextSpan(text: '${tr('Eng faol soat')}: '),
                                      TextSpan(
                                          text: '${n(d['peakHour']['h']).toString().padLeft(2, '0')}:00–${(n(d['peakHour']['h']) + 1).toString().padLeft(2, '0')}:00',
                                          style: TextStyle(fontWeight: FontWeight.w800, color: p.text))
                                    ],
                                    if (d['peakHour'] != null && d['bestWeekday'] != null) const TextSpan(text: ' · '),
                                    if (d['bestWeekday'] != null) ...[
                                      TextSpan(text: '${tr('Eng sotuvli kun')}: '),
                                      TextSpan(text: '${d['bestWeekday']['label']}', style: TextStyle(fontWeight: FontWeight.w800, color: p.text))
                                    ],
                                  ]))),
                            hbars([
                              for (final h in ([...hourBlocks]..sort((a, b) => n(b['n']).compareTo(n(a['n'])))).take(3)) (label: '${h['label']}', v: n(h['n']), text: '${n(h['n'])}', sub: null)
                            ], color: violet),
                            const SizedBox(height: 8),
                            // Hafta kunlari ustunlari: balandlik kontentga qarab olinadi (qat'iy 66px toshib ketardi)
                            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              for (final w in byWeekday)
                                Expanded(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 3),
                                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                                          Text(n(w['n']) > 0 ? '${n(w['n'])}' : '', maxLines: 1, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, height: 1.2)),
                                          const SizedBox(height: 2),
                                          Container(
                                              height: 3 + 36 * n(w['n']) / wdMax,
                                              decoration:
                                                  BoxDecoration(color: d['bestWeekday']?['label'] == w['label'] ? p.accent : p.accent.withValues(alpha: .3), borderRadius: BorderRadius.circular(4))),
                                          const SizedBox(height: 4),
                                          Text(_short('${w['label']}'), maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 10, color: p.muted, fontWeight: FontWeight.w700, height: 1.2)),
                                        ]))),
                            ]),
                          ]),
                        )),

                  // ---- Eng ko'p ko'rilgan / sotilmagan ----
                  if (top.isNotEmpty)
                    section(
                        Icons.visibility_outlined,
                        tr("Eng ko'p ko'rilgan"),
                        listCard([
                          for (final t in top.take(3))
                            listItem(
                                title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                trailing: badge('${t.views}', p.accent, ic: Icons.visibility_outlined))
                        ])),
                  if (unsold.isNotEmpty)
                    section(
                        Icons.error_outline_rounded,
                        tr('Hali sotilmagan'),
                        listCard([
                          for (final u in unsold.take(3))
                            listItem(
                                title: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text("${fmtPrice(u.price)} so'm · ${u.views} ko'rish", style: TextStyle(fontSize: 12, color: p.muted)),
                                trailing: badge('0 sotuv', amber))
                        ])),

                  // ---- Tavsiyalar ----
                  if (tips.isNotEmpty)
                    section(
                        Icons.lightbulb_outline_rounded,
                        tr('Tavsiyalar'),
                        Column(children: [
                          for (final t in tips.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: card(
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(color: switch (t.type) { 'warning' => amberSoft, 'success' => p.successSoft, _ => violetSoft }, borderRadius: BorderRadius.circular(12)),
                                    child: Icon(switch (t.type) { 'warning' => Icons.warning_amber_rounded, 'success' => Icons.check_circle_outline_rounded, _ => Icons.lightbulb_outline_rounded },
                                        size: 20, color: switch (t.type) { 'warning' => amber, 'success' => p.success, _ => violet })),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  const SizedBox(height: 3),
                                  Text(t.text, style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: .8), height: 1.45))
                                ])),
                              ])),
                            ),
                        ])),

                  // ---- Hisobot (brauzerda ochiladi, PDF qilib saqlanadi) ----
                  const SizedBox(height: 12),
                  card(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: p.danger.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.picture_as_pdf_outlined, size: 18, color: p.danger)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('Hisobot (PDF)'), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(tr("Barcha ko'rsatkichlar bitta sahifada. Brauzerda ochiladi, PDF qilib saqlash mumkin."), style: TextStyle(fontSize: 12, color: p.muted))
                        ])),
                      ]),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                          onPressed: pdfBusy ? null : downloadPdf,
                          icon: pdfBusy ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent)) : const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(pdfBusy ? tr('Tayyorlanmoqda...') : tr('Hisobotni ochish'))),
                    ]),
                  ),
                  // Ikkinchi OrdersTab ochilmaydi — SellerHome'dagi Buyurtmalar tabiga o'tiladi
                  if (n(s['newOrders']) > 0 && widget.onOpenOrders != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        label: Text("${n(s['newOrders'])} ${tr("ta yangi buyurtmani ko'rish")}"),
                        onPressed: widget.onOpenOrders),
                  ],
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _monthBox(Color c, String v, String l, {bool onDark = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
            color: onDark ? Colors.white.withValues(alpha: .08) : c.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
            border: onDark ? Border.all(color: Colors.white.withValues(alpha: .08)) : null),
        child: Column(children: [
          Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
          Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: onDark ? const Color(0xFFB7C0CC) : context.p.muted))
        ]),
      );
}

/// Silliq chiziqli diagramma: gradient soha, nuqtalar, bugungi kun yashil
class _LinePainter extends CustomPainter {
  final List<int> values;
  final int todayIdx;
  final Color line, today, grid, label;
  final bool showValues;
  _LinePainter({required this.values, required this.todayIdx, required this.line, required this.today, required this.grid, required this.label, required this.showValues});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    // Tepada qiymat yozuvi uchun joy qoldiriladi — eng baland nuqta yozuvi kesilmaydi
    const top = 26.0, bottom = 8.0;
    final h = size.height - top - bottom;
    final max = values.fold<int>(1, (m, v) => v > m ? v : m);
    // Nuqtalar katak markazida: pastdagi kun yozuvlari bilan bir chiziqda, chetlarda kesilmaydi
    final slot = size.width / values.length;
    final pts = [for (var i = 0; i < values.length; i++) Offset(slot * (i + .5), top + h - h * values[i] / max)];

    // setka
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + h * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }

    // silliq chiziq
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final cx = (a.dx + b.dx) / 2;
      path.cubicTo(cx, a.dy, cx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(path)
      ..lineTo(pts.last.dx, top + h)
      ..lineTo(pts.first.dx, top + h)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [line.withValues(alpha: .28), line.withValues(alpha: 0)])
              .createShader(Rect.fromLTWH(0, top, size.width, h)));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    // nuqtalar va qiymatlar
    for (var i = 0; i < pts.length; i++) {
      final isToday = i == todayIdx;
      final c = isToday ? today : line;
      if (showValues || isToday || values[i] == max) {
        canvas.drawCircle(pts[i], isToday ? 6 : 4, Paint()..color = Colors.white);
        canvas.drawCircle(
            pts[i],
            isToday ? 6 : 4,
            Paint()
              ..color = c
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      }
      if (showValues && values[i] > 0) {
        final tp = TextPainter(text: TextSpan(text: '${values[i]}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isToday ? today : label)), textDirection: TextDirection.ltr)
          ..layout();
        // Yozuv nuqta ustida, lekin diagramma chegarasidan chiqmaydi
        final maxX = size.width - tp.width;
        final dx = maxX <= 0 ? 0.0 : (pts[i].dx - tp.width / 2).clamp(0.0, maxX).toDouble();
        final dy = (pts[i].dy - tp.height - 7).clamp(0.0, size.height).toDouble();
        tp.paint(canvas, Offset(dx, dy));
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.values != values || o.todayIdx != todayIdx || o.line != line;
}

/// Hisobot: server HTML sahifa havolasini qaytaradi, u brauzerda ochiladi ("PDF qilib saqlash" tugmasi bor)
Future<bool> downloadReport(BuildContext context) async {
  try {
    final r = await Api.instance.post('/api/seller/report');
    final url = '${r is Map ? r['url'] ?? '' : ''}';
    if (url.isEmpty) throw ApiException(tr("Hisobotni ochib bo'lmadi"), 500);
    // Server nisbiy yo'l ("/report/...") yoki to'liq manzil qaytarishi mumkin
    final uri = Uri.parse(url.startsWith('http') ? url : '$apiBase$url');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showToast(context, tr("Brauzerni ochib bo'lmadi"), error: true);
    return ok;
  } catch (e) {
    if (context.mounted) showToast(context, sellerErrorText(e), error: true);
    return false;
  }
}
