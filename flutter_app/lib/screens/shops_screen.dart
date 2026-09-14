import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../l10n.dart';
import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'assistant_screen.dart';
import 'category_screen.dart';
import 'chat_screen.dart';
import 'map_screen.dart';
import 'rating_screen.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return tr('Xayrli tong');
  if (h < 18) return tr('Xayrli kun');
  return tr('Xayrli kech');
}

/// Bosh sahifa: do'konlar
class ShopsScreen extends StatefulWidget {
  final VoidCallback onSeller;
  const ShopsScreen({super.key, required this.onSeller});
  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  List<Shop> shops = [];
  bool loading = true;
  String q = '';
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final path = '/api/shops?q=${Uri.encodeComponent(q)}';
    // Kesh bo'lsa darhol ko'rsatamiz, fonda yangilaymiz
    final cached = Api.instance.cached(path);
    if (cached != null) {
      shops = (cached as List).map((e) => Shop.fromJson(e)).toList();
      loading = false;
    } else {
      loading = true;
    }
    if (mounted) setState(() {});
    try {
      final r = await Api.instance.get(path);
      shops = (r as List).map((e) => Shop.fromJson(e)).toList();
      error = null;
    } catch (e) {
      error = e.toString();
      if (mounted && cached != null) showToast(context, error!, error: true);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final st = AppState.instance;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad), children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 16),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(), style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
                Text(Api.instance.userName == 'Xaridor' ? tr('Xaridor') : Api.instance.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.5)),
              ]),
            ),
            ListenableBuilder(
              listenable: st,
              // 6 ta tugma sig'ishi uchun biroz kichikroq (38) va zichroq
              builder: (_, __) => Row(children: [
                const LangBtn(size: 38),
                const SizedBox(width: 6),
                const ThemeBtn(size: 38),
                const SizedBox(width: 6),
                IconBtn(Icons.workspace_premium_rounded, size: 38, color: const Color(0xFFE0A100), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RatingScreen()))),
                const SizedBox(width: 6),
                IconBtn(Icons.map_outlined, size: 38, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapScreen()))),
                const SizedBox(width: 6),
                IconBtn(Icons.favorite_border, size: 38, badge: st.favs.length, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
                const SizedBox(width: 6),
                IconBtn(Icons.shopping_cart_outlined, size: 38, badge: st.cartCount, onTap: () => openCart(context)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          SearchField(
              hint: tr("Do'kon yoki mahsulot qidiring"),
              onChanged: (v) {
                q = v;
                load();
              }),
          const SizedBox(height: 16),
          DarkBanner(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFC9D3FF)),
                const SizedBox(width: 6),
                Text(tr('SOFIA · AI YORDAMCHI'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: Color(0xFFC9D3FF))),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                  width: 240,
                  child: Text(tr("Nima kerakligini yozing — Sofia do'kon topib beradi"), style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -.3))),
              const SizedBox(height: 12),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const AssistantScreen(inTab: false))),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('Chatni boshlash'), style: const TextStyle(color: Color(0xFF14161A), fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF14161A))
                    ]),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // Kategoriya kartochkalari — Sofia banneri ostida, o'sha qora-sariq dizaynda; surib qidiriladi
          const CategoryStrip(),
          SectionTitle(tr("Do'konlar"), action: tr('Xaritada'), onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapScreen()))),
          if (loading)
            const GridSkeleton(count: 4, aspect: .86)
          else if (error != null && shops.isEmpty)
            EmptyBox(Icons.cloud_off_rounded, "${tr("Serverga ulanib bo'lmadi")}\n$error",
                action: OutlinedButton.icon(onPressed: load, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))))
          else if (shops.isEmpty)
            EmptyBox(Icons.storefront_outlined, tr("Do'kon topilmadi"))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .86),
              itemCount: shops.length,
              itemBuilder: (_, i) => FadeIn(index: i, child: ShopCard(shops[i], onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shops[i].id))))),
            ),
        ]),
      ),
    );
  }
}

/// Do'kon sahifasi
class ShopScreen extends StatefulWidget {
  final String shopId;
  const ShopScreen(this.shopId, {super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  Shop? shop;
  List<Product> products = [];
  String q = '';
  String sort = 'new';

  @override
  void initState() {
    super.initState();
    load();
  }

  void _apply(dynamic r) {
    shop = Shop.fromJson(r['shop']);
    products = (r['products'] as List).map((e) => Product.fromJson(e)).toList();
    AppState.instance.chatShop = shop;
    AppState.instance.refresh();
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    final path = '/api/shops/${widget.shopId}';
    final cached = Api.instance.cached(path);
    if (cached != null) _apply(cached); // darhol keshdan, keyin fonda yangilanadi
    try {
      _apply(await Api.instance.get(path));
    } catch (e) {
      if (mounted && cached == null) showToast(context, e.toString(), error: true);
    }
  }

  List<Product> get visible {
    var list = q.isEmpty ? products : products.where((p) => '${p.name} ${p.description}'.toLowerCase().contains(q.toLowerCase())).toList();
    list = [...list];
    switch (sort) {
      case 'cheap':
        list.sort((a, b) => a.price.compareTo(b.price));
      case 'exp':
        list.sort((a, b) => b.price.compareTo(a.price));
      case 'pop':
        list.sort((a, b) => b.views.compareTo(a.views));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = shop;
    final p = context.p;
    final st = AppState.instance;
    return Scaffold(
      floatingActionButton: s == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 84),
              child: Material(
                color: p.dark,
                borderRadius: BorderRadius.circular(999),
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: .3),
                child: InkWell(
                  onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ChatScreen(shop: s))),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 20, color: p.onDark),
                      const SizedBox(width: 8),
                      Text('${s.sellerName} ${tr('bilan chat')}', style: TextStyle(color: p.onDark, fontWeight: FontWeight.w700, fontSize: 14))
                    ]),
                  ),
                ),
              ),
            ),
      body: s == null
          ? ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad), children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 12),
              Row(children: [IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop())]),
              const SizedBox(height: 18),
              const Row(children: [Skeleton(height: 64, width: 64, radius: 20), SizedBox(width: 14), Expanded(child: Skeleton(height: 44))]),
              const SizedBox(height: 16),
              const Skeleton(height: 50),
              const SizedBox(height: 14),
              const GridSkeleton(count: 4, aspect: .7),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad), children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 12),
              Row(children: [
                IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
                const Spacer(),
                IconBtn(Icons.ios_share, onTap: () => shareShop(s)),
                const SizedBox(width: 8),
                ListenableBuilder(listenable: st, builder: (_, __) => IconBtn(Icons.shopping_cart_outlined, badge: st.cartCount, onTap: () => openCart(context))),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                ShopAvatar(s, size: 64, shadow: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: p.success, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text('${s.sellerName} ${tr('onlayn')} · ${products.length} ${tr('ta mahsulot')}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Stars(s.rating, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text('${s.rating.toStringAsFixed(1)} · ${trLevel(s.level)} · ${s.sales} ${tr('ta sotuv')}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: levelColor(s.level), fontWeight: FontWeight.w700))),
                    ]),
                  ]),
                ),
                if (s.lat != null) ...[
                  IconBtn(Icons.map_outlined, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(focus: [s])))),
                  const SizedBox(width: 8)
                ],
                IconBtn(Icons.phone_outlined, bg: p.successSoft, color: p.success, size: 44, onTap: () => launchUrl(Uri.parse('tel:${s.phone}'))),
              ]),
              if (s.description.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(s.description, style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w500, height: 1.5))),
              const SizedBox(height: 16),
              SearchField(hint: tr('Qidirish'), onChanged: (v) => setState(() => q = v)),
              const SizedBox(height: 12),
              ChoiceChips(items: [('new', tr('Yangi')), ('cheap', tr('Arzon')), ('exp', tr('Qimmat')), ('pop', tr('Mashhur'))], value: sort, onChanged: (v) => setState(() => sort = v)),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                EmptyBox(Icons.search_off, tr('Topilmadi'))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .7),
                  itemCount: visible.length,
                  itemBuilder: (_, i) => FadeIn(index: i, child: ProductCard(visible[i], onTap: () => openProduct(context, visible[i], s), onAdd: () => _addToCart(context, visible[i]))),
                ),
            ]),
    );
  }
}

Future<void> _addToCart(BuildContext context, Product p) async {
  if (!AppState.instance.addToCart(p)) {
    final ok = await confirmDialog(context, tr("Savatchada boshqa do'kon mahsuloti bor"), text: tr("Tozalab, shu do'kondan boshlaymizmi?"), ok: tr('Ha, tozalash'));
    if (!ok) return;
    AppState.instance.addToCart(p, force: true);
  }
  if (context.mounted) showToast(context, tr("Savatchaga qo'shildi"));
}

/// Ulashish: tizimning ulashish oynasi (Telegram, SMS, ...)
void shareProduct(Product p) {
  Share.share("${p.name} — ${fmtPrice(p.price)} so'm\nhttps://t.me/$botUsername?startapp=p_${p.id}", subject: p.name);
}

void shareShop(Shop s) {
  Share.share("${s.name}${s.description.isNotEmpty ? ' — ${s.description}' : ''}\nhttps://t.me/$botUsername?startapp=shop_${s.id}", subject: s.name);
}

/// Mahsulot sahifasi (to'liq ekran)
void openProduct(BuildContext context, Product p, Shop? shop) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductScreen(p, shop)));
}

class ProductScreen extends StatefulWidget {
  final Product p;
  final Shop? shop;
  const ProductScreen(this.p, this.shop, {super.key});
  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  int page = 0;
  int? views;

  @override
  void initState() {
    super.initState();
    // Ko'rish hisobga olinadi (har foydalanuvchi uchun bir marta) va aniq soni qaytadi
    Api.instance.post('/api/products/${widget.p.id}/view').then((r) {
      if (mounted && r is Map && r['views'] != null) setState(() => views = (r['views'] as num).toInt());
    }).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final shop = widget.shop;
    final pal = context.p;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(children: [
        ListView(padding: EdgeInsets.zero, children: [
          SizedBox(
            height: 440,
            child: Stack(fit: StackFit.expand, children: [
              Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pal.imageA, pal.imageB]))),
              if (p.photos.isNotEmpty)
                Hero(
                  tag: 'p-${p.id}',
                  child: PageView(
                    onPageChanged: (i) => setState(() => page = i),
                    children: [
                      for (var i = 0; i < p.photos.length; i++)
                        GestureDetector(
                          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => _Lightbox(p.photos, i))),
                          child: Padding(padding: EdgeInsets.fromLTRB(16, top + 64, 16, 40), child: Image.network(Api.instance.photoUrl(p.photos[i]), fit: BoxFit.contain)),
                        ),
                    ],
                  ),
                )
              else
                Icon(Icons.shopping_bag_outlined, size: 72, color: pal.muted),
              if (p.photos.length > 1)
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < p.photos.length; i++)
                      AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == page ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(color: i == page ? pal.dark : pal.dark.withValues(alpha: .25), borderRadius: BorderRadius.circular(3))),
                  ]),
                ),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Container(
              decoration: BoxDecoration(color: pal.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (shop != null) Text(shop.name.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.accentText, letterSpacing: .4)),
                      const SizedBox(height: 6),
                      Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4, height: 1.15)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.visibility_outlined, size: 14, color: pal.muted),
                      const SizedBox(width: 4),
                      Text('${views ?? p.views}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.muted))
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                PriceText(p.price, size: 28),
                if (p.description.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(p.description, style: TextStyle(fontSize: 14, color: pal.text.withValues(alpha: .8), height: 1.55, fontWeight: FontWeight.w500))),
                if (shop != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(16), border: context.isDark ? Border.all(color: pal.border) : null),
                    child: Row(children: [
                      ShopAvatar(shop, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(shop.sellerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(tr("Sotuvchi · savolingiz bo'lsa yozing"), style: TextStyle(fontSize: 12, color: pal.muted, fontWeight: FontWeight.w500))
                      ])),
                      IconBtn(Icons.chat_bubble_outline_rounded,
                          bg: pal.bg, size: 40, onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ChatScreen(shop: shop, prefill: '${p.name} ${tr('haqida batafsil aytib bering')}')))),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        ]),
        Positioned(
          top: top + 10,
          left: 16,
          right: 16,
          child: Row(children: [
            IconBtn(Icons.arrow_back_ios_new_rounded, bg: pal.card.withValues(alpha: .85), onTap: () => Navigator.of(context).maybePop()),
            const Spacer(),
            IconBtn(Icons.ios_share, bg: pal.card.withValues(alpha: .85), onTap: () => shareProduct(p)),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: AppState.instance,
              builder: (_, __) {
                final fav = AppState.instance.isFav(p.id);
                return IconBtn(fav ? Icons.favorite : Icons.favorite_border,
                    bg: pal.card.withValues(alpha: .85), color: fav ? const Color(0xFFD63384) : null, onTap: () => AppState.instance.toggleFav(p));
              },
            ),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(color: pal.bg, boxShadow: [BoxShadow(color: pal.bg, blurRadius: 20, spreadRadius: 10)]),
            child: Row(children: [
              IconBtn(Icons.phone_outlined, size: 54, color: pal.success, onTap: shop == null ? null : () => launchUrl(Uri.parse('tel:${shop.phone}'))),
              const SizedBox(width: 10),
              IconBtn(Icons.shopping_cart_outlined, size: 54, onTap: () => _addToCart(context, p)),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.icon(icon: const Icon(Icons.bolt_rounded, size: 18), label: Text(tr('Sotib olish')), onPressed: () => openOrderForm(context, [CartItem(p, 1)]))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Lightbox extends StatelessWidget {
  final List<String> photos;
  final int index;
  const _Lightbox(this.photos, this.index);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: PageView(controller: PageController(initialPage: index), children: [for (final r in photos) InteractiveViewer(child: Center(child: Image.network(Api.instance.photoUrl(r))))]),
      );
}

/// Savatcha
void openCart(BuildContext context) {
  showModalBottomSheet(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => ListenableBuilder(
      listenable: AppState.instance,
      builder: (c, _) {
        final st = AppState.instance;
        final p = c.p;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(tr('Savatcha'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4))),
              if (st.cart.isNotEmpty) TextButton.icon(onPressed: st.clearCart, icon: Icon(Icons.delete_outline, size: 18, color: p.danger), label: Text(tr('Tozalash'), style: TextStyle(color: p.danger))),
            ]),
            if (st.cart.isEmpty)
              EmptyBox(Icons.shopping_cart_outlined, tr("Savatcha bo'sh"))
            else ...[
              const SizedBox(height: 8),
              for (final it in st.cart)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: c.isDark ? Border.all(color: p.border) : null),
                  child: Row(children: [
                    ProductImage(it.product, size: 56, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      PriceText(it.product.price, size: 13)
                    ])),
                    IconBtn(Icons.remove, size: 30, bg: p.bg, onTap: () => st.changeQty(it, -1)),
                    SizedBox(width: 28, child: Text('${it.qty}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
                    IconBtn(Icons.add, size: 30, bg: p.bg, onTap: () => st.changeQty(it, 1)),
                  ]),
                ),
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [Expanded(child: Text(tr('Jami'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))), PriceText(st.cartTotal, size: 18)])),
              FilledButton.icon(icon: const Icon(Icons.check_rounded), label: Text(tr('Buyurtma berish')), onPressed: () => openOrderForm(c, List.of(st.cart), fromCart: true)),
            ],
          ]),
        );
      },
    ),
  );
}

/// Buyurtma formasi
void openOrderForm(BuildContext context, List<CartItem> items, {bool fromCart = false}) {
  final name = TextEditingController(text: Api.instance.userName == 'Xaridor' ? '' : Api.instance.userName);
  final phone = TextEditingController();
  final total = items.fold(0, (s, i) => s + i.product.price * i.qty);
  showModalBottomSheet(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      final p = c.p;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Buyurtma berish'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: c.isDark ? Border.all(color: p.border) : null),
            child: Column(children: [
              for (final i in items)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(child: Text(i.qty > 1 ? '${i.product.name} × ${i.qty}' : i.product.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(fmtPrice(i.product.price * i.qty), style: const TextStyle(fontWeight: FontWeight.w700))
                    ])),
              Divider(color: p.border),
              Row(children: [Expanded(child: Text(tr('Jami'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))), PriceText(total, size: 16)]),
            ]),
          ),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Ismingiz'))),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon raqam'), hintText: '+998 90 123 45 67')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              try {
                await Api.instance.post('/api/orders', {
                  'items': items.map((i) => {'productId': i.product.id, 'qty': i.qty}).toList(),
                  'customerName': name.text,
                  'phone': phone.text
                });
                if (fromCart) AppState.instance.clearCart();
                if (c.mounted) Navigator.pop(c);
                if (context.mounted) {
                  showDialog(
                    context: context,
                    useRootNavigator: true,
                    builder: (d) => AlertDialog(
                      icon: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(color: d.p.successSoft, borderRadius: BorderRadius.circular(18)),
                          child: Icon(Icons.check_rounded, color: d.p.success, size: 30)),
                      title: Text(tr('Buyurtma qabul qilindi!'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      content: Text(tr("Sotuvchi tez orada siz bilan bog'lanadi."), textAlign: TextAlign.center, style: TextStyle(color: d.p.muted)),
                      actions: [FilledButton(onPressed: () => Navigator.pop(d), child: Text(tr('Yopish')))],
                    ),
                  );
                }
              } catch (e) {
                if (c.mounted) showToast(c, e.toString(), error: true);
              }
            },
            child: Text("${tr('Buyurtma berish')} · ${fmtPrice(total)} so'm"),
          ),
          const SizedBox(height: 8),
          Center(child: Text(tr("Sotuvchi tez orada siz bilan bog'lanadi"), style: TextStyle(fontSize: 12, color: p.muted))),
        ]),
      );
    },
  );
}

/// Sevimlilar
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: Padding(padding: const EdgeInsets.only(left: 12), child: IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop())),
            leadingWidth: 60,
            title: Text(tr('Sevimlilar'))),
        body: ListenableBuilder(
          listenable: AppState.instance,
          builder: (_, __) {
            final favs = AppState.instance.favs.values.toList();
            if (favs.isEmpty) return EmptyBox(Icons.favorite_border, tr("Sevimlilar bo'sh\nMahsulot ustidagi yurakchani bosing"));
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, navPad),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .7),
              itemCount: favs.length,
              itemBuilder: (_, i) => ProductCard(favs[i], onTap: () async {
                try {
                  final r = await Api.instance.get('/api/products/${favs[i].id}');
                  if (context.mounted) openProduct(context, Product.fromJson(r['product']), r['shop'] == null ? null : Shop.fromJson(r['shop']));
                } catch (e) {
                  if (context.mounted) showToast(context, e.toString(), error: true);
                }
              }),
            );
          },
        ),
      );
}
