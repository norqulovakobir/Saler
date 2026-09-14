import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shops_screen.dart';

/// Do'konlar reytingi: sotuvlar bo'yicha kim birinchi turibdi
class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  List<Shop> shops = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    const path = '/api/shops-rating';
    final cached = Api.instance.cached(path);
    if (cached != null) {
      shops = (cached as List).map((e) => Shop.fromJson(e)).toList();
      loading = false;
      if (mounted) setState(() {});
    }
    try {
      final r = await Api.instance.get(path);
      shops = (r as List).map((e) => Shop.fromJson(e)).toList();
      error = null;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop())),
        leadingWidth: 60,
        title: Text(tr("Do'konlar reytingi")),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, navPad),
                children: [for (var i = 0; i < 5; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: Skeleton(height: 96, radius: 20))])
            : error != null && shops.isEmpty
                ? EmptyBox(Icons.cloud_off_rounded, "${tr("Serverga ulanib bo'lmadi")}\n$error",
                    action: OutlinedButton.icon(onPressed: load, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))))
                : shops.isEmpty
                    ? EmptyBox(Icons.workspace_premium_outlined, tr("Hozircha do'kon yo'q"))
                    : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, navPad), children: [
                        DarkBanner(
                          glow: const Color(0xFFE0A100),
                          glow2: const Color(0xFF7C5CFF),
                          child: Row(children: [
                            Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)),
                                child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFC53D), size: 26)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tr("Eng yaxshi do'konlar"), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                                const SizedBox(height: 3),
                                Text(tr("Reyting bajarilgan sotuvlar soniga qarab o'sadi"), style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 12, fontWeight: FontWeight.w500)),
                              ]),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        for (var i = 0; i < shops.length; i++) FadeIn(index: i, child: _RatingRow(shops[i], i + 1)),
                        const SizedBox(height: 6),
                        Center(
                            child: Text(tr('Darajalar: Yangi · Bronza (1+) · Kumush (5+) · Oltin (15+) · Platina (30+ sotuv)'),
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w600))),
                      ]),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final Shop s;
  final int rank;
  const _RatingRow(this.s, this.rank);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final top = rank <= 3;
    final medal = switch (rank) { 1 => const Color(0xFFFFC53D), 2 => const Color(0xFFB0B8C4), 3 => const Color(0xFFC98A4B), _ => p.muted };
    final lc = levelColor(s.level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(s.id))),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: softShadow(context),
              border: rank == 1 ? Border.all(color: const Color(0xFFFFC53D).withValues(alpha: .6), width: 1.5) : (context.isDark ? Border.all(color: p.border) : null),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // O'rin
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: top ? medal.withValues(alpha: .18) : p.bg, borderRadius: BorderRadius.circular(11)),
                child: top
                    ? Icon(rank == 1 ? Icons.workspace_premium_rounded : Icons.military_tech_rounded, size: 20, color: medal)
                    : Text('$rank', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.muted)),
              ),
              const SizedBox(width: 10),
              ShopAvatar(s, size: 56, shadow: rank == 1),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: lc.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
                      child: Text(trLevel(s.level), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: lc)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Stars(s.rating, size: 15),
                    const SizedBox(width: 6),
                    Text(s.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text('${s.sales} ${tr('ta sotuv')}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    s.description.isNotEmpty ? s.description : "${s.sellerName} · ${s.productCount} ${tr('ta mahsulot')}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w500, height: 1.35),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
