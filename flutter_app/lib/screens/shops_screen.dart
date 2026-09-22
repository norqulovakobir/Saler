import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'nearby_section.dart';
import 'auth/auth_ui.dart';
import 'auth/buyer_auth.dart';
import 'category_screen.dart';
import 'chat_screen.dart';
import 'map_screen.dart';
import 'buyer_notifications_screen.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return tr('Xayrli tong');
  if (h < 18) return tr('Xayrli kun');
  return tr('Xayrli kech');
}

/// Bosh sahifadagi salomlashuvda ism-familiya emas, foydalanuvchining faqat
/// ismi ko'rinadi. Eski sessiyalarda firstName bo'lmasa ismni umumiy nomdan
/// xavfsiz ajratib olamiz.
String _buyerFirstName() {
  final first = Api.instance.firstName.trim();
  if (first.isNotEmpty) return first.split(RegExp(r'\s+')).first;
  final name = Api.instance.userName.trim();
  if (name.isEmpty || name == 'Xaridor') return tr('Xaridor');
  return name.split(RegExp(r'\s+')).first;
}

/// Bosh sahifa: do'konlar
class ShopsScreen extends StatefulWidget {
  final VoidCallback onSeller;
  const ShopsScreen({super.key, required this.onSeller});
  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  /// Bir sahifada nechta do'kon yuklanadi
  static const _pageSize = 20;

  /// Tasodifiy tartib kaliti: ilova ochiq turganda bir xil, pastga tortib yangilanganda almashadi
  static String _seed = '${DateTime.now().millisecondsSinceEpoch}';

  final _scroll = ScrollController();
  List<Shop> shops = [];
  // Boshlang'ich katalog telefon xotirasida saqlanadi. Qidirayotganda shu
  // ro'yxatda ishlaymiz — har bir harf uchun serverga so'rov yuborilmaydi.
  List<Shop> _browseShops = [];
  bool _browseHasMore = false;
  final Map<String, List<Shop>> _searchCache = {};
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  String q = '';
  String? error;
  Timer? _debounce;
  int _req = 0; // eskirgan javoblarni tashlab yuborish uchun

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  String _path(int offset, {String query = ''}) =>
      '/api/shops?q=${Uri.encodeComponent(query)}&limit=$_pageSize&offset=$offset&seed=$_seed';

  List<Shop> _items(dynamic r) {
    final rows = (r as Map)['items'] as List? ?? const [];
    return rows
        .map((e) => Shop.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  bool _localMatch(Shop shop, String query) {
    final text = '${shop.name} ${shop.description} ${shop.sellerName} '
            '${shop.ownerName ?? ''} ${shop.address ?? ''} ${shop.login ?? ''}'
        .toLowerCase();
    return text.contains(query);
  }

  List<Shop> _localResults(String query) =>
      _browseShops.where((shop) => _localMatch(shop, query)).toList();

  void _showQueryResults() {
    if (q.isEmpty) {
      shops = _browseShops;
      hasMore = _browseHasMore;
      return;
    }
    // Bir marta tarmoqdan olingan aniq so'rov natijasi qayta yozilganda ham
    // xotiradan chiqadi; shu sabab qidiruvning o'zi bepul va tez ishlaydi.
    shops = _searchCache[q] ?? _localResults(q);
    hasMore = false;
  }

  void _applyBrowse(dynamic r, {bool append = false}) {
    final items = _items(r);
    if (append) {
      final seen = _browseShops.map((s) => s.id).toSet();
      _browseShops = [
        ..._browseShops,
        ...items.where((s) => !seen.contains(s.id))
      ];
    } else {
      _browseShops = items;
    }
    _browseHasMore = r['hasMore'] == true && items.isNotEmpty;
    _showQueryResults();
  }

  void _onSearchChanged(String value) {
    final next = value.trim().toLowerCase();
    if (next == q) {
      return;
    }
    _debounce?.cancel();
    q = next;
    error = null;
    _showQueryResults();
    if (mounted) {
      setState(() {});
    }

    // Katalogda natija topilsa yoki so'rov juda qisqa bo'lsa, hech qanday
    // internet so'rovi kerak emas. Natija yo'q bo'lsa ham bitta so'rov faqat
    // foydalanuvchi 650 ms yozishni to'xtatgandan keyin yuboriladi.
    if (q.length < 3 || shops.isNotEmpty || _searchCache.containsKey(q)) {
      return;
    }
    final search = q;
    _debounce =
        Timer(const Duration(milliseconds: 650), () => _remoteSearch(search));
  }

  Future<void> _remoteSearch(String search) async {
    if (search != q ||
        _searchCache.containsKey(search) ||
        _localResults(search).isNotEmpty) {
      return;
    }
    try {
      final r = await Api.instance.get(_path(0, query: search));
      final found = _items(r);
      _searchCache[search] = found;
      if (!mounted || search != q) {
        return;
      }
      setState(() {
        shops = found;
        hasMore = false;
        error = null;
      });
    } catch (e) {
      if (!mounted || search != q) {
        return;
      }
      setState(() => error = e.toString());
    }
  }

  /// Ro'yxat oxiriga yaqinlashganda (yoki birinchi sahifa ekranni to'ldirmasa) keyingi sahifa yuklanadi
  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 800) loadMore();
  }

  Future<void> load({bool reshuffle = false}) async {
    if (reshuffle) {
      _seed = '${DateTime.now().millisecondsSinceEpoch}';
      _searchCache.clear();
    }
    final req = ++_req;
    final path = _path(0);
    // Kesh bo'lsa darhol ko'rsatamiz, fonda yangilaymiz
    final cached = Api.instance.cached(path);
    if (cached != null) {
      _applyBrowse(cached);
      loading = false;
    } else {
      loading = true;
    }
    loadingMore = false;
    if (mounted) setState(() {});
    try {
      final r = await Api.instance.get(path);
      if (req != _req) return;
      _applyBrowse(r);
      error = null;
    } catch (e) {
      if (req != _req) return;
      error = e.toString();
      if (mounted && cached != null) showToast(context, error!, error: true);
    }
    if (!mounted) return;
    setState(() => loading = false);
    if (q.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    }
  }

  Future<void> loadMore() async {
    if (q.isNotEmpty || loading || loadingMore || !_browseHasMore) return;
    final req = _req;
    setState(() => loadingMore = true);
    dynamic r;
    try {
      r = await Api.instance.get(_path(_browseShops.length));
    } catch (_) {
      r = null; // tarmoq xatosi: foydalanuvchi yana pastga surganda qayta urinadi
    }
    if (!mounted || req != _req) return;
    setState(() {
      if (r != null) _applyBrowse(r, append: true);
      loadingMore = false;
    });
    if (r != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final st = AppState.instance;
    return Scaffold(
      body: RefreshIndicator(
        // Pastga tortilsa do'konlar yangi tasodifiy tartibda keladi
        onRefresh: () => load(reshuffle: true),
        child: CustomScrollView(controller: _scroll, slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SizedBox(height: MediaQuery.of(context).padding.top + 16),
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greeting(),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: p.muted,
                                  fontWeight: FontWeight.w600)),
                          Text(_buyerFirstName(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.5)),
                        ]),
                  ),
                  ListenableBuilder(
                    listenable: st,
                    builder: (_, __) => IconBtn(
                      Icons.notifications_none_rounded,
                      size: 42,
                      badge: st.noticeUnread,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const BuyerNotificationsScreen()),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                SearchField(
                    hint: tr("Do'kon yoki mahsulot qidiring"),
                    onChanged: _onSearchChanged,
                    height: 58),
                const SizedBox(height: 12),
                DarkBanner(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SizedBox(
                    height: 64,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.auto_awesome,
                                size: 13, color: Color(0xFFC9D3FF)),
                            const SizedBox(width: 6),
                            Text(tr('SOFIA · AI YORDAMCHI'),
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .55,
                                    color: Color(0xFFC9D3FF))),
                          ]),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Row(children: [
                              Expanded(
                                  child: Text(
                                      tr(
                                          "Nima kerakligini yozing — Sofia do'kon topib beradi"),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          height: 1.18,
                                          letterSpacing: -.25))),
                              const SizedBox(width: 12),
                              Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: () =>
                                      Navigator.of(context, rootNavigator: true)
                                          .push(MaterialPageRoute(
                                              builder: (_) =>
                                                  const AssistantScreen(
                                                      inTab: false))),
                                  borderRadius: BorderRadius.circular(12),
                                  child: const SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Icon(Icons.arrow_forward,
                                          size: 20, color: Color(0xFF14161A))),
                                ),
                              ),
                            ]),
                          ),
                        ]),
                  ),
                ),
                const SizedBox(height: 12),
                // Kategoriya kartochkalari — Sofia banneri ostida, o'sha qora-sariq dizaynda; surib qidiriladi
                const CategoryStrip(),
                // Joylashuvga ruxsat berilgan bo'lsa — yaqin-atrofdagi eng
                // yaxshi takliflar. Ruxsat berilmagan bo'lsa taklif kartochkasi.
                const NearbySection(),
                SectionTitle(tr("Do'konlar"),
                    action: tr('Xaritada'),
                    onAction: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MapScreen()))),
                if (loading)
                  const GridSkeleton(count: 4, aspect: .86)
                else if (error != null && shops.isEmpty)
                  EmptyBox(Icons.cloud_off_rounded,
                      "${tr("Serverga ulanib bo'lmadi")}\n$error",
                      action: OutlinedButton.icon(
                          onPressed: load,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(tr('Qayta urinish'))))
                else if (shops.isEmpty)
                  EmptyBox(Icons.storefront_outlined, tr("Do'kon topilmadi")),
              ]),
            ),
          ),
          // Do'kon kartochkalari faqat ekranga yaqinlashganda quriladi (ro'yxat qancha uzun bo'lsa ham tez)
          if (!loading && shops.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: .86),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final card = ShopCard(shops[i],
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => ShopScreen(shops[i].id))));
                    return i < _pageSize ? FadeIn(index: i, child: card) : card;
                  },
                  childCount: shops.length,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad),
            sliver: SliverToBoxAdapter(
              child: loadingMore
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5))))
                  : const SizedBox.shrink(),
            ),
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
  // Obuna: bosilganda darhol ko'rinadi, server javobi bilan tasdiqlanadi
  bool? _following;
  int? _followers;
  bool followBusy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  void _apply(dynamic r) {
    shop = Shop.fromJson(r['shop']);
    _following = null;
    _followers = null;
    products = (r['products'] as List).map((e) => Product.fromJson(e)).toList();
    AppState.instance.chatShop = shop;
    AppState.instance.refresh();
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    final path = '/api/shops/${widget.shopId}';
    final cached = Api.instance.cached(path);
    if (cached != null) {
      _apply(cached); // darhol keshdan, keyin fonda yangilanadi
    }
    try {
      _apply(await Api.instance.get(path));
    } catch (e) {
      if (mounted && cached == null) {
        showToast(context, e.toString(), error: true);
      }
    }
  }

  Future<void> _toggleFollow() async {
    final s = shop;
    if (s == null || followBusy) return;
    // Obuna bo'lish uchun tasdiqlangan xaridor hisobi kerak
    final was0 = _following ?? s.following;
    if (!was0 &&
        !await ensureBuyer(context,
            title: tr("Obuna bo'lish uchun kiring"),
            subtitle: tr(
                "Obunachilar yangi mahsulotlarni birinchi bo'lib ko'radi"))) {
      return;
    }
    if (!mounted) return;
    final was = _following ?? s.following;
    final count = _followers ?? s.followers;
    setState(() {
      followBusy = true;
      _following = !was;
      _followers = count + (was ? -1 : 1);
    });
    try {
      final r = was
          ? await Api.instance.delete('/api/shops/${s.id}/follow')
          : await Api.instance.post('/api/shops/${s.id}/follow');
      if (mounted && r is Map) {
        setState(() {
          _following = r['following'] == true;
          _followers = (r['followers'] as num?)?.toInt() ?? _followers;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _following = was;
        _followers = count;
      });
      showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  List<Product> get visible {
    var list = q.isEmpty
        ? products
        : products
            .where((p) => '${p.name} ${p.description}'
                .toLowerCase()
                .contains(q.toLowerCase()))
            .toList();
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
      body: s == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad),
              children: [
                  SizedBox(height: MediaQuery.of(context).padding.top + 12),
                  Row(children: [
                    IconBtn(Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.of(context).maybePop())
                  ]),
                  const SizedBox(height: 18),
                  const Row(children: [
                    Skeleton(height: 64, width: 64, radius: 20),
                    SizedBox(width: 14),
                    Expanded(child: Skeleton(height: 44))
                  ]),
                  const SizedBox(height: 16),
                  const Skeleton(height: 50),
                  const SizedBox(height: 14),
                  const GridSkeleton(count: 4, aspect: .7),
                ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, navPad),
              children: [
                  SizedBox(height: MediaQuery.of(context).padding.top + 12),
                  Row(children: [
                    IconBtn(Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.of(context).maybePop()),
                    const Spacer(),
                    if (s.lat != null) ...[
                      IconBtn(Icons.map_outlined,
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => MapScreen(focus: [s])))),
                      const SizedBox(width: 8),
                    ],
                    IconBtn(Icons.ios_share, onTap: () => shareShop(s)),
                    const SizedBox(width: 8),
                    ListenableBuilder(
                        listenable: st,
                        builder: (_, __) => IconBtn(
                            Icons.shopping_cart_outlined,
                            badge: st.cartCount,
                            onTap: () => openCart(context))),
                  ]),
                  const SizedBox(height: 18),
                  // Instagram uslubidagi profil: rasm, ko'rsatkichlar, nom, obuna va xabar
                  Row(children: [
                    ShopAvatar(s, size: 80, shadow: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _ProfileStat(
                                value: '${products.length}',
                                label: tr('Mahsulotlar')),
                            _ProfileStat(
                                value: _compactNum(_followers ?? s.followers),
                                label: tr('Obunachilar')),
                            _ProfileStat(
                                value: '${s.sales}', label: tr('Sotuvlar')),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.4)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Stars(s.rating, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            '${s.rating.toStringAsFixed(1)} · ${trLevel(s.level)} · ${s.sellerName} ${tr('onlayn')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: levelColor(s.level),
                                fontWeight: FontWeight.w700))),
                  ]),
                  if (s.description.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(s.description,
                            style: TextStyle(
                                fontSize: 13.5,
                                color: p.text.withValues(alpha: .8),
                                fontWeight: FontWeight.w500,
                                height: 1.45))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: (_following ?? s.following)
                          ? OutlinedButton.icon(
                              onPressed: followBusy ? null : _toggleFollow,
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 46),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10)),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(tr('Obunadasiz'),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            )
                          : FilledButton.icon(
                              onPressed: followBusy ? null : _toggleFollow,
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 46),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10)),
                              icon: const Icon(Icons.person_add_alt_1_rounded,
                                  size: 18),
                              label: Text(tr("Obuna bo'lish"),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // Xabar do'konning AI sotuvchisi bilan chatni ochadi
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                    builder: (_) => ChatScreen(shop: s))),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10)),
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 18),
                        label: Text(tr('Xabar'),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconBtn(Icons.phone_outlined,
                        bg: p.successSoft,
                        color: p.success,
                        size: 46,
                        onTap: () => launchUrl(Uri.parse('tel:${s.phone}'))),
                  ]),
                  const SizedBox(height: 16),
                  SearchField(
                      hint: tr('Qidirish'),
                      onChanged: (v) => setState(() => q = v)),
                  const SizedBox(height: 12),
                  ChoiceChips(items: [
                    ('new', tr('Yangi')),
                    ('cheap', tr('Arzon')),
                    ('exp', tr('Qimmat')),
                    ('pop', tr('Mashhur'))
                  ], value: sort, onChanged: (v) => setState(() => sort = v)),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    EmptyBox(Icons.search_off, tr('Topilmadi'))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: .7),
                      itemCount: visible.length,
                      itemBuilder: (_, i) => FadeIn(
                          index: i,
                          child: ProductCard(visible[i],
                              onTap: () => openProduct(context, visible[i], s),
                              onAdd: () => _addToCart(context, visible[i]))),
                    ),
                ]),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  const _ProfileStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.3)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: context.p.muted,
                fontWeight: FontWeight.w600)),
      ]);
}

String _compactNum(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)}M'
    : n >= 10000
        ? '${(n / 1000).toStringAsFixed(1)}K'
        : '$n';

Future<void> _addToCart(BuildContext context, Product p) async {
  if (!AppState.instance.addToCart(p)) {
    final ok = await confirmDialog(
        context, tr("Savatchada boshqa do'kon mahsuloti bor"),
        text: tr("Tozalab, shu do'kondan boshlaymizmi?"),
        ok: tr('Ha, tozalash'));
    if (!ok) return;
    AppState.instance.addToCart(p, force: true);
  }
  if (context.mounted) showToast(context, tr("Savatchaga qo'shildi"));
}

/// Ulashish: tizimning ulashish oynasi (Telegram, SMS, ...).
/// Havola web sahifaga olib boradi — qabul qilgan odam ilovani o'rnatmasdan
/// mahsulotni ko'radi va o'sha yerdan buyurtma bera oladi.
void shareProduct(Product p) {
  Share.share("${p.name} — ${fmtPrice(p.price)} so'm\n${productLink(p.id)}", subject: p.name);
}

void shareShop(Shop s) {
  Share.share("${s.name}${s.description.isNotEmpty ? ' — ${s.description}' : ''}\n${shopLink(s.id)}", subject: s.name);
}

/// Havolani buferga nusxalash (web'da ulashish oynasi bo'lmasligi mumkin)
Future<void> copyLink(BuildContext context, String link) async {
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) showToast(context, tr('Havola nusxalandi'));
}

/// Ulashish varaqasi: ulashish yoki havolani nusxalash
void showShareSheet(BuildContext context, {required String title, required String link, required VoidCallback onShare}) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Ulashish'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 4),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.p.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: c.p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.p.border)),
            child: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.p.muted, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(c);
              onShare();
            },
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(tr('Ulashish')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(c);
              copyLink(context, link);
            },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: Text(tr('Havolani nusxalash')),
          ),
        ]),
      ),
    ),
  );
}

/// Mahsulot sahifasi (to'liq ekran)
void openProduct(BuildContext context, Product p, Shop? shop) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ProductScreen(p, shop)));
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
      if (mounted && r is Map && r['views'] != null) {
        setState(() => views = (r['views'] as num).toInt());
      }
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
              Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [pal.imageA, pal.imageB]))),
              if (p.photos.isNotEmpty)
                Hero(
                  tag: 'p-${p.id}',
                  child: PageView(
                    onPageChanged: (i) => setState(() => page = i),
                    children: [
                      for (var i = 0; i < p.photos.length; i++)
                        GestureDetector(
                          onTap: () =>
                              Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                      builder: (_) => _Lightbox(p.photos, i))),
                          child: Padding(
                              padding:
                                  EdgeInsets.fromLTRB(16, top + 64, 16, 40),
                              child: Image.network(
                                  Api.instance.photoUrl(p.photos[i]),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported_outlined,
                                      color: context.p.muted, size: 42))),
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
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < p.photos.length; i++)
                          AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == page ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: i == page
                                      ? pal.dark
                                      : pal.dark.withValues(alpha: .25),
                                  borderRadius: BorderRadius.circular(3))),
                      ]),
                ),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Container(
              decoration: BoxDecoration(
                  color: pal.bg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28))),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (shop != null)
                                    Text(shop.name.toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: pal.accentText,
                                            letterSpacing: .4)),
                                  const SizedBox(height: 6),
                                  Text(p.name,
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -.4,
                                          height: 1.15)),
                                ]),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: pal.card,
                                borderRadius: BorderRadius.circular(999)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.visibility_outlined,
                                  size: 14, color: pal.muted),
                              const SizedBox(width: 4),
                              Text('${views ?? p.views}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: pal.muted))
                            ]),
                          ),
                        ]),
                    const SizedBox(height: 14),
                    PriceText(p.price, size: 28),
                    if (p.description.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(p.description,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: pal.text.withValues(alpha: .8),
                                  height: 1.55,
                                  fontWeight: FontWeight.w500))),
                    if (shop != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: pal.card,
                            borderRadius: BorderRadius.circular(16),
                            border: context.isDark
                                ? Border.all(color: pal.border)
                                : null),
                        child: Row(children: [
                          ShopAvatar(shop, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(shop.sellerName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                Text(tr("Sotuvchi · savolingiz bo'lsa yozing"),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: pal.muted,
                                        fontWeight: FontWeight.w500))
                              ])),
                          IconBtn(Icons.chat_bubble_outline_rounded,
                              bg: pal.bg,
                              size: 40,
                              onTap: () => Navigator.of(context,
                                      rootNavigator: true)
                                  .push(MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                          shop: shop,
                                          prefill:
                                              '${p.name} ${tr('haqida batafsil aytib bering')}')))),
                        ]),
                      ),
                    ],
                    // Shu mahsulotga o'xshash mahsulotlar
                    RelatedProducts(p),
                  ]),
            ),
          ),
        ]),
        Positioned(
          top: top + 10,
          left: 16,
          right: 16,
          child: Row(children: [
            IconBtn(Icons.arrow_back_ios_new_rounded,
                bg: pal.card.withValues(alpha: .85),
                onTap: () => Navigator.of(context).maybePop()),
            const Spacer(),
            IconBtn(Icons.ios_share,
                bg: pal.card.withValues(alpha: .85),
                onTap: () => shareProduct(p)),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: AppState.instance,
              builder: (_, __) {
                final fav = AppState.instance.isFav(p.id);
                return IconBtn(fav ? Icons.favorite : Icons.favorite_border,
                    bg: pal.card.withValues(alpha: .85),
                    color: fav ? const Color(0xFFD63384) : null,
                    onTap: () => AppState.instance.toggleFav(p));
              },
            ),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(color: pal.bg, boxShadow: [
              BoxShadow(color: pal.bg, blurRadius: 20, spreadRadius: 10)
            ]),
            child: Row(children: [
              IconBtn(Icons.phone_outlined,
                  size: 54,
                  color: pal.success,
                  onTap: shop == null
                      ? null
                      : () => launchUrl(Uri.parse('tel:${shop.phone}'))),
              const SizedBox(width: 10),
              IconBtn(Icons.shopping_cart_outlined,
                  size: 54, onTap: () => _addToCart(context, p)),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton.icon(
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(tr('Sotib olish')),
                      onPressed: () =>
                          openOrderForm(context, [CartItem(p, 1)]))),
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
        appBar: AppBar(
            backgroundColor: Colors.black, foregroundColor: Colors.white),
        body:
            PageView(controller: PageController(initialPage: index), children: [
          for (final r in photos)
            InteractiveViewer(
                child: Center(
                    child: Image.network(Api.instance.photoUrl(r),
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.image_not_supported_outlined, color: context.p.muted, size: 42))))
        ]),
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
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(tr('Savatcha'),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.4))),
                  if (st.cart.isNotEmpty)
                    TextButton.icon(
                        onPressed: st.clearCart,
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: p.danger),
                        label: Text(tr('Tozalash'),
                            style: TextStyle(color: p.danger))),
                ]),
                if (st.cart.isEmpty)
                  EmptyBox(Icons.shopping_cart_outlined, tr("Savatcha bo'sh"))
                else ...[
                  const SizedBox(height: 8),
                  for (final it in st.cart)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              c.isDark ? Border.all(color: p.border) : null),
                      child: Row(children: [
                        ProductImage(it.product, size: 56, radius: 12),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(it.product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              PriceText(it.product.price, size: 13)
                            ])),
                        IconBtn(Icons.remove,
                            size: 30,
                            bg: p.bg,
                            onTap: () => st.changeQty(it, -1)),
                        SizedBox(
                            width: 28,
                            child: Text('${it.qty}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))),
                        IconBtn(Icons.add,
                            size: 30,
                            bg: p.bg,
                            onTap: () => st.changeQty(it, 1)),
                      ]),
                    ),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        Expanded(
                            child: Text(tr('Jami'),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600))),
                        PriceText(st.cartTotal, size: 18)
                      ])),
                  FilledButton.icon(
                      icon: const Icon(Icons.check_rounded),
                      label: Text(tr('Buyurtma berish')),
                      onPressed: () =>
                          openOrderForm(c, List.of(st.cart), fromCart: true)),
                ],
              ]),
        );
      },
    ),
  );
}

/// Buyurtma oynasi. Mehmon bo'lsa: ism, familiya, telefon, Telegram va email yoziladi,
/// emailga 6 xonali kod yuboriladi va kod tasdiqlangandan keyin buyurtma qabul qilinadi.
void openOrderForm(BuildContext context, List<CartItem> items,
    {bool fromCart = false}) {
  showModalBottomSheet(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => OrderSheet(items: items, fromCart: fromCart),
  );
}

class OrderSheet extends StatefulWidget {
  final List<CartItem> items;
  final bool fromCart;
  const OrderSheet({super.key, required this.items, this.fromCart = false});
  @override
  State<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<OrderSheet> {
  final form = BuyerForm();
  final address = TextEditingController();
  bool busy = false;
  bool codeStep = false;
  String? devCode;
  String? error;

  int get total => widget.items.fold(0, (s, i) => s + i.product.price * i.qty);
  bool get registered => Api.instance.registered;

  @override
  void dispose() {
    form.dispose();
    address.dispose();
    super.dispose();
  }

  /// Buyurtmani serverga yuboradi (hisob tasdiqlangandan keyin)
  Future<void> _place() async {
    final root = Navigator.of(context, rootNavigator: true);
    await Api.instance.post('/api/orders', {
      'items': widget.items
          .map((i) => {'productId': i.product.id, 'qty': i.qty})
          .toList(),
      'customerName':
          '${form.firstName.text.trim()} ${form.lastName.text.trim()}'.trim(),
      'phone': '+998${form.digits}',
      if (address.text.trim().isNotEmpty) 'address': address.text.trim(),
    });
    if (widget.fromCart) AppState.instance.clearCart();
    if (!mounted) return;
    root.pop();
    showDialog(
      context: root.context,
      builder: (d) => AlertDialog(
        icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: d.p.successSoft,
                borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.check_rounded, color: d.p.success, size: 30)),
        title: Text(tr('Buyurtma qabul qilindi!'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text(tr("Sotuvchi tez orada siz bilan bog'lanadi."),
            textAlign: TextAlign.center, style: TextStyle(color: d.p.muted)),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(d), child: Text(tr('Yopish')))
        ],
      ),
    );
  }

  Future<void> _submit() async {
    String? problem = form.validate();
    // Kirgan xaridorga Telegram va email qayta so'ralmaydi
    if (registered) {
      problem = form.firstName.text.trim().isEmpty
          ? tr('Ismingizni kiriting')
          : form.digits.length != 9
              ? tr("Telefon raqamini to'liq kiriting")
              : null;
    }
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (registered) {
        await _place();
        return;
      }
      final d = await buyerSendCode(form);
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
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(codeStep ? tr('Emailni tasdiqlang') : tr('Buyurtma berish'),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        context.isDark ? Border.all(color: p.border) : null),
                child: Column(children: [
                  for (final i in widget.items)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  i.qty > 1
                                      ? '${i.product.name} × ${i.qty}'
                                      : i.product.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                          Text(fmtPrice(i.product.price * i.qty),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700))
                        ])),
                  Divider(color: p.border),
                  Row(children: [
                    Expanded(
                        child: Text(tr('Jami'),
                            style: TextStyle(
                                color: p.muted, fontWeight: FontWeight.w600))),
                    PriceText(total, size: 16)
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              if (codeStep)
                CodeStep(
                  email: form.email.text.trim(),
                  devCode: devCode,
                  buttonLabel: tr('Buyurtma berish'),
                  onResend: () => buyerSendCode(form),
                  onSubmit: (code) async {
                    await buyerVerify(form, code);
                    await _place();
                  },
                )
              else ...[
                if (registered) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: AuthField(
                            controller: form.firstName,
                            label: tr('Ism'),
                            icon: Icons.person_outline_rounded,
                            caps: TextCapitalization.words)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: AuthField(
                            controller: form.lastName,
                            label: tr('Familiya'),
                            caps: TextCapitalization.words)),
                  ]),
                  AuthField(
                    controller: form.phone,
                    label: tr('Telefon raqami'),
                    icon: Icons.phone_outlined,
                    keyboard: TextInputType.phone,
                    prefixText: '+998 ',
                    hint: '90 123 45 67',
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9)
                    ],
                  ),
                ] else ...[
                  Text(tr("Buyurtma berish uchun ma'lumotlaringizni kiriting"),
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  BuyerFields(form: form, onSubmit: _submit),
                ],
                AuthField(
                    controller: address,
                    label: tr('Yetkazish manzili'),
                    icon: Icons.location_on_outlined,
                    hint: tr('Ixtiyoriy'),
                    maxLines: 2),
                AuthErrorText(error),
                AuthButton("${tr('Buyurtma berish')} · ${fmtPrice(total)} so'm",
                    busy: busy, onTap: _submit, icon: Icons.check_rounded),
                const SizedBox(height: 8),
                Center(
                    child: Text(tr("Sotuvchi tez orada siz bilan bog'lanadi"),
                        style: TextStyle(fontSize: 12, color: p.muted))),
              ],
            ]),
      ),
    );
  }
}

/// Sevimlilar
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: IconBtn(Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.of(context).maybePop())),
            leadingWidth: 60,
            title: Text(tr('Sevimlilar'))),
        body: ListenableBuilder(
          listenable: AppState.instance,
          builder: (_, __) {
            final favs = AppState.instance.favs.values.toList();
            if (favs.isEmpty) {
              return EmptyBox(Icons.favorite_border,
                  tr("Sevimlilar bo'sh\nMahsulot ustidagi yurakchani bosing"));
            }
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, navPad),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .7),
              itemCount: favs.length,
              itemBuilder: (_, i) => ProductCard(favs[i], onTap: () async {
                try {
                  final r =
                      await Api.instance.get('/api/products/${favs[i].id}');
                  if (context.mounted) {
                    openProduct(context, Product.fromJson(r['product']),
                        r['shop'] == null ? null : Shop.fromJson(r['shop']));
                  }
                } catch (e) {
                  if (context.mounted) {
                    showToast(context, e.toString(), error: true);
                  }
                }
              }),
            );
          },
        ),
      );
}

/// Mahsulot sahifasi ostidagi o'xshash mahsulotlar (gorizontal suriladigan ro'yxat)
class RelatedProducts extends StatefulWidget {
  final Product p;
  const RelatedProducts(this.p, {super.key});
  @override
  State<RelatedProducts> createState() => _RelatedProductsState();
}

class _RelatedProductsState extends State<RelatedProducts> {
  List<(Product, Shop?)> items = [];
  bool loading = true;

  String get _path => '/api/products/${widget.p.id}/related?limit=12';

  List<(Product, Shop?)> _parse(dynamic r) => ((r as Map)['items'] as List)
      .map((e) => (
            Product.fromJson(e),
            e['shop'] == null ? null : Shop.fromJson(e['shop'])
          ))
      .toList();

  @override
  void initState() {
    super.initState();
    final cached = Api.instance.cached(_path);
    if (cached != null) {
      items = _parse(cached);
      loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get(_path);
      items = _parse(r);
    } catch (_) {
      // O'xshash mahsulotlar qo'shimcha blok: xato bo'lsa shunchaki ko'rsatilmaydi
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!loading && items.isEmpty) return const SizedBox.shrink();
    const cardW = 162.0,
        cardH = 232.0; // do'kon sahifasidagi mahsulot kartochkasi nisbati (0.7)
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr("O'xshash mahsulotlar"),
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3)),
        const SizedBox(height: 12),
        SizedBox(
          height: cardH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: loading ? 3 : items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: cardW,
              child: loading
                  ? const Skeleton(height: cardH, radius: 20)
                  : FadeIn(
                      index: i,
                      child: ProductCard(items[i].$1,
                          onTap: () =>
                              openProduct(context, items[i].$1, items[i].$2),
                          onAdd: () => _addToCart(context, items[i].$1))),
            ),
          ),
        ),
      ]),
    );
  }
}
