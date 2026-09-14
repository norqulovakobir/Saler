import 'package:flutter/material.dart';
import '../api.dart';
import '../categories.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shops_screen.dart';

/// Bosh sahifadagi kategoriya kartochkalari (Sofia banneri ostida, gorizontal surib qidiriladi)
class CategoryStrip extends StatelessWidget {
  const CategoryStrip({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 116,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final c = categories[i];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryScreen(c))),
                child: Container(
                  width: 110,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context, y: 6, blur: 16, a: .08)),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(c.asset, fit: BoxFit.cover),
                ),
              ),
            );
          },
        ),
      );
}

/// Kategoriya sahifasi: barcha do'konlarning shu kategoriyadagi mahsulotlari
class CategoryScreen extends StatefulWidget {
  final Category category;
  const CategoryScreen(this.category, {super.key});
  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<(Product, Shop?)> items = [];
  bool loading = true;
  String? error;
  String q = '';
  String sort = 'new';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final path = '/api/categories/${widget.category.slug}/products';
    void apply(dynamic r) => items = (r as List).map((e) => (Product.fromJson(e), e['shop'] == null ? null : Shop.fromJson(e['shop']))).toList();
    final cached = Api.instance.cached(path);
    if (cached != null) {
      apply(cached);
      loading = false;
      if (mounted) setState(() {});
    }
    try {
      apply(await Api.instance.get(path));
      error = null;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  List<(Product, Shop?)> get visible {
    var list = q.isEmpty ? items : items.where((x) => '${x.$1.name} ${x.$1.description}'.toLowerCase().contains(q.toLowerCase())).toList();
    list = [...list];
    switch (sort) {
      case 'cheap':
        list.sort((a, b) => a.$1.price.compareTo(b.$1.price));
      case 'exp':
        list.sort((a, b) => b.$1.price.compareTo(a.$1.price));
      case 'pop':
        list.sort((a, b) => b.$1.views.compareTo(a.$1.views));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = widget.category;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad), children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 12),
          Row(children: [
            IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
            const SizedBox(width: 12),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(c.asset, width: 44, height: 44, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                Text('${items.length} ${tr('ta mahsulot')}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          SearchField(hint: tr('Qidirish'), onChanged: (v) => setState(() => q = v)),
          const SizedBox(height: 12),
          ChoiceChips(items: [('new', tr('Yangi')), ('cheap', tr('Arzon')), ('exp', tr('Qimmat')), ('pop', tr('Mashhur'))], value: sort, onChanged: (v) => setState(() => sort = v)),
          const SizedBox(height: 14),
          if (loading)
            const GridSkeleton(count: 4, aspect: .7)
          else if (error != null && items.isEmpty)
            EmptyBox(Icons.cloud_off_rounded, "${tr("Serverga ulanib bo'lmadi")}\n$error", action: OutlinedButton.icon(onPressed: load, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))))
          else if (visible.isEmpty)
            EmptyBox(Icons.category_outlined, tr("Bu kategoriyada hozircha mahsulot yo'q"))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .7),
              itemCount: visible.length,
              itemBuilder: (_, i) {
                final (pr, shop) = visible[i];
                return FadeIn(index: i, child: ProductCard(pr, onTap: () => openProduct(context, pr, shop)));
              },
            ),
        ]),
      ),
    );
  }
}
