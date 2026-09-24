import 'dart:async';
import 'dart:ui' show ImageFilter, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../categories.dart';
import '../l10n.dart';
import '../main.dart' show showToast, confirmDialog, rootTab, openRootTab;
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth/buyer_auth.dart';
import 'chat_screen.dart';
import 'shops_screen.dart';

/// Reels bo'limi pastki paneldagi o'rni
const reelsTabIndex = 1;

/// Birinchi ochilishda 5 ta reel olinadi, keyin har safar 2 tadan — serverdan bir vaqtda ko'p ma'lumot tortilmaydi
const _firstPage = 5;
const _nextPage = 2;

/// Oldinda shuncha reel qolganda keyingi bo'lak so'raladi (3-chisiga kelganda)
const _prefetchGap = 3;

/// Reels elementi: mahsulot, do'kon, layk va nega ko'rsatilgani
class _Reel {
  final Product product;
  final Shop shop;
  int likes;
  bool liked;
  bool following;
  int followers;
  final bool isNew;
  final String reason; // following | interest | popular
  _Reel({required this.product, required this.shop, required this.likes, required this.liked, required this.following, required this.followers, required this.isNew, required this.reason});

  factory _Reel.fromJson(Map j) {
    final shop = Shop.fromJson((j['shop'] as Map).cast<String, dynamic>());
    return _Reel(
      product: Product.fromJson((j['product'] as Map).cast<String, dynamic>()),
      shop: shop,
      likes: (j['likes'] as num?)?.toInt() ?? 0,
      liked: j['liked'] == true,
      following: shop.following,
      followers: shop.followers,
      isNew: j['isNew'] == true,
      reason: (j['reason'] ?? 'popular').toString(),
    );
  }
}

String _compact(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}M' : n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

/// Reels: yuqoriga surib mahsulotlar, yonga surib shu mahsulotning boshqa rasmlari.
/// Tartibni server belgilaydi: obuna bo'lingan do'konlarning yangi mahsulotlari, qiziqishga mos va mashhur mahsulotlar.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});
  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> with WidgetsBindingObserver {
  final _pager = PageController();
  final List<_Reel> items = [];
  String? seed;
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;
  String? error;
  int current = 0;
  DateTime? _shownAt; // joriy reel ekranga chiqqan vaqt (ko'rish davomiyligi uchun)
  int _seenLive = AppState.instance.liveVersion;
  bool freshFromFollowed = false; // obuna bo'lingan do'kondan yangi mahsulot keldi
  int _feedVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.instance.addListener(_onLive);
    rootTab.addListener(_onTab);
    load();
  }

  @override
  void dispose() {
    _sendView();
    WidgetsBinding.instance.removeObserver(this);
    AppState.instance.removeListener(_onLive);
    rootTab.removeListener(_onTab);
    _pager.dispose();
    super.dispose();
  }

  bool get _visible => rootTab.value == reelsTabIndex;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTiming();
    } else {
      _sendView();
    }
  }

  // Boshqa bo'limga o'tilganda ko'rish vaqti hisoblanmaydi
  void _onTab() => _visible ? _startTiming() : _sendView();

  void _onLive() {
    final st = AppState.instance;
    // Foydalanuvchi endigina tizimga kirdi: Reels yuklanadi
    if (Api.instance.registered && items.isEmpty && !loading && mounted) {
      load();
      return;
    }
    if (st.liveVersion == _seenLive) return;
    _seenLive = st.liveVersion;
    if (st.lastEvent?.type == 'product:new' && mounted) setState(() => freshFromFollowed = true);
  }

  void _startTiming() => _shownAt = _visible && items.isNotEmpty ? DateTime.now() : null;

  /// Reel ekrandan ketganda qancha ko'rilgani yuboriladi (qiziqishlarni aniqlash uchun)
  void _sendView() {
    final at = _shownAt;
    _shownAt = null;
    if (at == null || current >= items.length) return;
    final ms = DateTime.now().difference(at).inMilliseconds;
    if (ms < 300) return;
    Api.instance.post('/api/reels/${items[current].product.id}/view', {'ms': ms}).catchError((_) => null);
  }

  List<_Reel> _parse(dynamic r) => ((r['items'] as List?) ?? const []).map((e) => _Reel.fromJson(e as Map)).toList();

  Future<void> load({bool refresh = false}) async {
    if (!Api.instance.registered) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (refresh) {
      _sendView();
      seed = null;
      freshFromFollowed = false;
    }
    // Bir vaqtning o'zida kelgan eski javob yangi tasmani ustiga yozmasin.
    final version = ++_feedVersion;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Api.instance.get('/api/reels?limit=$_firstPage&offset=0${seed != null ? '&seed=$seed' : ''}');
      final list = _parse(r);
      if (!mounted || version != _feedVersion) return;
      // Tasmani almashtirishdan avval PageView'ni boshiga qaytaramiz.
      // Aks holda eski 2-reel ochiq turgan paytda yangi ro'yxat 1 ta bo'lsa
      // Flutter vaqtincha 1-indeksni o'qishga urinib RangeError berishi mumkin.
      if (_pager.hasClients) _pager.jumpToPage(0);
      setState(() {
        items
          ..clear()
          ..addAll(list);
        seed = r['seed']?.toString();
        hasMore = r['hasMore'] == true;
        loading = false;
        current = 0;
      });
      _startTiming();
      _precache(0);
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e is ApiException ? e.message : tr("Serverga ulanib bo'lmadi");
        });
      }
    }
  }

  Future<void> loadMore() async {
    if (loadingMore || !hasMore || seed == null) return;
    loadingMore = true;
    try {
      final r = await Api.instance.get('/api/reels?limit=$_nextPage&offset=${items.length}&seed=$seed');
      final list = _parse(r);
      if (!mounted) return;
      final have = items.map((x) => x.product.id).toSet();
      setState(() {
        items.addAll(list.where((x) => !have.contains(x.product.id)));
        hasMore = r['hasMore'] == true && list.isNotEmpty;
      });
      _precache(current);
      // Tez surilganda zaxira tugab qolmasin: hali oldinda 3 tadan kam bo'lsa, yana bir bo'lak
      if (hasMore && current >= items.length - _prefetchGap) {
        loadingMore = false;
        unawaited(loadMore());
        return;
      }
    } catch (_) {
      // Keyingi surishda qayta urinadi
    } finally {
      loadingMore = false;
    }
  }

  void _onPage(int i) {
    // PageView eski kadrni bir frame ushlab turishi mumkin; yangi kichik
    // bo'lak kelganida ro'yxatdan tashqari indeksga hech qachon murojaat qilmaymiz.
    if (i < 0 || i >= items.length) return;
    _sendView();
    setState(() => current = i);
    _startTiming();
    _precache(i);
    // 3-, 6-, 9-... reelga kelganda navbatdagi 2 ta element fonda so'raladi.
    // Juda tez surilganda oxirgi elementga kelish ham zaxira so'rovini ishga
    // tushiradi, shuning uchun bo'sh ekran chiqmaydi.
    if ((i + 1) % _prefetchGap == 0 || i >= items.length - 1) loadMore();
  }

  /// Keyingi ikki reelning birinchi rasmi oldindan yuklanadi, surilganda darhol chiqadi
  void _precache(int i) {
    for (final j in [i + 1, i + 2]) {
      if (j < items.length && items[j].product.photos.isNotEmpty) {
        precacheImage(NetworkImage(Api.instance.photoUrl(items[j].product.photos.first)), context).catchError((_) {});
      }
    }
  }

  Future<void> _toggleLike(_Reel r, {bool onlyLike = false}) async {
    if (onlyLike && r.liked) return;
    final was = r.liked;
    setState(() {
      r.liked = !was;
      r.likes += was ? -1 : 1;
    });
    try {
      final res = was ? await Api.instance.delete('/api/products/${r.product.id}/like') : await Api.instance.post('/api/products/${r.product.id}/like');
      if (mounted && res is Map) {
        setState(() {
          r.likes = (res['likes'] as num?)?.toInt() ?? r.likes;
          r.liked = res['liked'] == true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        r.liked = was;
        r.likes += was ? 1 : -1;
      });
      showToast(context, e.toString(), error: true);
    }
  }

  /// Obuna holati shu do'konning barcha reellarida bir xil yangilanadi
  Future<void> _toggleFollow(_Reel r) async {
    final was = r.following;
    void apply(bool f, int? count) {
      for (final x in items.where((x) => x.shop.id == r.shop.id)) {
        x.following = f;
        x.followers = count ?? (x.followers + (f ? 1 : -1));
      }
    }

    setState(() => apply(!was, null));
    try {
      final res = was ? await Api.instance.delete('/api/shops/${r.shop.id}/follow') : await Api.instance.post('/api/shops/${r.shop.id}/follow');
      if (mounted && res is Map) setState(() => apply(res['following'] == true, (res['followers'] as num?)?.toInt()));
    } catch (e) {
      if (!mounted) return;
      setState(() => apply(was, null));
      showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _addToCart(Product p) async {
    if (!AppState.instance.addToCart(p)) {
      final ok = await confirmDialog(context, tr("Savatchada boshqa do'kon mahsuloti bor"), text: tr("Tozalab, shu do'kondan boshlaymizmi?"), ok: tr('Ha, tozalash'));
      if (!ok) return;
      AppState.instance.addToCart(p, force: true);
    }
    if (mounted) showToast(context, tr("Savatchaga qo'shildi"));
  }

  Future<void> _showInterests() async {
    Map? data;
    try {
      final r = await Api.instance.get('/api/me/interests');
      if (r is Map) data = r;
    } catch (_) {}
    if (!mounted) return;
    final p = context.p;
    final cats = ((data?['categories'] as List?) ?? const []).map((e) => categoryOf(e.toString())?.name ?? e.toString()).toList();
    final kws = ((data?['keywords'] as List?) ?? const []).map((e) => e.toString()).toList();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome, color: p.accent),
              const SizedBox(width: 8),
              Text(tr('Siz uchun'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ]),
            const SizedBox(height: 8),
            Text(data?['summary']?.toString() ?? tr("Qiziqishlaringiz ko'rish va layklaringiz asosida aniqlanadi"), style: TextStyle(color: p.muted, height: 1.45, fontWeight: FontWeight.w500)),
            if (cats.isNotEmpty || kws.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in cats) _SheetChip(c, bg: p.accentSoft, fg: p.accentText),
                for (final k in kws) _SheetChip(k, bg: p.bg, fg: p.text),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          Positioned.fill(child: _body()),
          // Yuqori soya: joylashuvi aniq berilgan, aks holda Stack uning balandligiga siqilib qoladi
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: top + 90,
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xAA000000), Color(0x00000000)])),
              ),
            ),
          ),
          Positioned(
            top: top + 6,
            left: 16,
            right: 8,
            child: Row(children: [
              // Reels'da pastki panel yo'q, shuning uchun chiqish yo'li shu
              // tugma: bosh sahifaga (Do'konlar) qaytaradi.
              IconButton(
                tooltip: tr('Ortga'),
                onPressed: () => openRootTab?.call(0),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: 6),
              const Text('Reels', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5)),
              const SizedBox(width: 10),
              _GlassChip(icon: Icons.auto_awesome, label: tr('Siz uchun'), onTap: _showInterests),
              const Spacer(),
              if (freshFromFollowed) _GlassChip(icon: Icons.fiber_new_rounded, label: tr('Yangi'), highlight: true, onTap: () => load(refresh: true)),
              IconButton(
                tooltip: tr('Yangilash'),
                onPressed: loading ? null : () => load(refresh: true),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Reels faqat tasdiqlangan xaridorga ko'rinadi (qiziqishlar shu hisobga bog'lanadi)
  Future<void> _signIn() async {
    final ok = await ensureBuyer(context,
        title: tr("Reels uchun tizimga kiring"), subtitle: tr("Qiziqishlaringizga mos mahsulotlarni ko'rsatamiz"));
    if (ok && mounted) load(refresh: true);
  }

  Widget _body() {
    if (!Api.instance.registered) {
      return _Message(
        icon: Icons.play_circle_outline_rounded,
        text: tr("Reels'ni ko'rish uchun tizimga kiring"),
        action: FilledButton.icon(onPressed: _signIn, icon: const Icon(Icons.login_rounded, size: 18), label: Text(tr('Kirish'))),
      );
    }
    if (loading && items.isEmpty) return const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5));
    if (error != null && items.isEmpty) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        text: error!,
        action: FilledButton.icon(onPressed: () => load(refresh: true), icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))),
      );
    }
    if (items.isEmpty) return _Message(icon: Icons.play_circle_outline_rounded, text: tr("Hozircha mahsulot yo'q"));
    return ScrollConfiguration(
      behavior: const _DragAll(),
      child: PageView.builder(
      controller: _pager,
      scrollDirection: Axis.vertical,
      onPageChanged: _onPage,
      itemCount: items.length,
      itemBuilder: (_, i) {
        // Async refresh bilan PageView orasidagi bitta frame uchun himoya.
        if (i < 0 || i >= items.length) return const SizedBox.expand();
        final r = items[i];
        return _ReelPage(
          key: ValueKey(r.product.id),
          reel: r,
          onLike: () => _toggleLike(r),
          onDoubleTapLike: () => _toggleLike(r, onlyLike: true),
          onFollow: () => _toggleFollow(r),
          onMessage: () => Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute(builder: (_) => ChatScreen(shop: r.shop, prefill: '${r.product.name} ${tr('haqida batafsil aytib bering')}'))),
          onShare: () => shareProduct(r.product),
          onCart: () => _addToCart(r.product),
          onBuy: () => openOrderForm(context, [CartItem(r.product, 1)]),
          onShop: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(r.shop.id))),
        );
      },
      ),
    );
  }
}

/// Veb va kompyuterda ham sichqoncha yoki trekpad bilan surish mumkin bo'lsin (telefonda barmoq bilan)
class _DragAll extends MaterialScrollBehavior {
  const _DragAll();
  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};
}

class _ReelPage extends StatefulWidget {
  final _Reel reel;
  final VoidCallback onLike, onDoubleTapLike, onFollow, onMessage, onShare, onCart, onBuy, onShop;
  const _ReelPage({
    super.key,
    required this.reel,
    required this.onLike,
    required this.onDoubleTapLike,
    required this.onFollow,
    required this.onMessage,
    required this.onShare,
    required this.onCart,
    required this.onBuy,
    required this.onShop,
  });
  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with SingleTickerProviderStateMixin {
  int photo = 0;
  bool expanded = false;
  late final AnimationController _heart = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel;
    final pr = r.product;
    final p = context.p;
    final photos = pr.photos;
    final top = MediaQuery.of(context).padding.top;
    // Reels'da pastki navigatsiya paneli yo'q (yuqoridagi "Ortga" tugmasi
    // chiqish yo'li), shuning uchun nom, narx va amallar ekran pastiga
    // yaqin turadi — avvalgi 104px ularni keraksiz yuqoriga ko'tarardi.
    final bottom = MediaQuery.of(context).padding.bottom + 24;
    final cat = categoryOf(pr.category);
    return GestureDetector(
      onDoubleTap: () {
        widget.onDoubleTapLike();
        _heart.forward(from: 0);
      },
      child: Stack(fit: StackFit.expand, children: [
        // Rasmlar: yonga surib ko'riladi
        ScrollConfiguration(
          behavior: const _DragAll(),
          child: PageView.builder(
            itemCount: photos.isEmpty ? 1 : photos.length,
            onPageChanged: (i) => setState(() => photo = i),
            itemBuilder: (_, i) => photos.isEmpty
                ? const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 64))
                : _ReelImage(url: Api.instance.photoUrl(photos[i])),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .45, 1],
                colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
              ),
            ),
          ),
        ),
        if (photos.length > 1)
          Positioned(
            top: top + 58,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Row(children: [
                for (var i = 0; i < photos.length; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == photo ? .95 : .35), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
            ),
          ),
        // Ikki marta bosilganda yurak
        Center(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _heart,
              builder: (_, __) {
                final t = _heart.value;
                if (t == 0 || t == 1) return const SizedBox.shrink();
                final scale = t < .3 ? Curves.easeOutBack.transform(t / .3) : 1.0;
                final opacity = t < .7 ? 1.0 : 1 - (t - .7) / .3;
                return Opacity(opacity: opacity, child: Transform.scale(scale: scale, child: const Icon(Icons.favorite, color: Colors.white, size: 110)));
              },
            ),
          ),
        ),
        // O'ng tomondagi amallar
        Positioned(
          right: 10,
          bottom: bottom,
          child: Column(children: [
            GestureDetector(
              onTap: widget.onShop,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: ClipOval(child: SizedBox(width: 46, height: 46, child: ShopAvatar(r.shop, size: 46))),
                ),
                if (!r.following)
                  Positioned(
                    bottom: -9,
                    child: GestureDetector(
                      onTap: widget.onFollow,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.add_rounded, size: 17, color: Color(0xFF14161A)),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 22),
            _Action(icon: r.liked ? Icons.favorite : Icons.favorite_border_rounded, color: r.liked ? const Color(0xFFFF3B5C) : Colors.white, label: _compact(r.likes), onTap: widget.onLike),
            _Action(icon: Icons.chat_bubble_outline_rounded, label: tr('Xabar'), onTap: widget.onMessage),
            _Action(icon: Icons.shopping_bag_outlined, label: tr('Savat'), onTap: widget.onCart),
            _Action(icon: Icons.ios_share_rounded, label: tr('Ulashish'), onTap: widget.onShare),
          ]),
        ),
        // Pastki ma'lumot
        Positioned(
          left: 16,
          right: 86,
          bottom: bottom,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _ReasonBadge(reel: r),
            const SizedBox(height: 10),
            Row(children: [
              Flexible(
                child: GestureDetector(
                  onTap: widget.onShop,
                  child: Text(r.shop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
              if (!r.following) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onFollow,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: .8)), borderRadius: BorderRadius.circular(8)),
                    child: Text(tr("Obuna bo'lish"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Text(pr.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.3, height: 1.2)),
            const SizedBox(height: 4),
            Row(children: [
              Text("${fmtPrice(pr.price)} so'm", style: TextStyle(color: p.accent, fontSize: 18, fontWeight: FontWeight.w800)),
              if (cat != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
                    child: Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ]),
            if (pr.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => expanded = !expanded),
                child: Text(pr.description,
                    maxLines: expanded ? 8 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500)),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.onBuy,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 18)),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: Text(tr('Sotib olish')),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Rasm: orqa fonda xiralashtirilgan nusxa, oldinda to'liq ko'rinadigan asl rasm
class _ReelImage extends StatelessWidget {
  final String url;
  const _ReelImage({required this.url});
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black)),
        ),
        const ColoredBox(color: Color(0x66000000)),
        Image.network(
          url,
          fit: BoxFit.contain,
          // Rasm butun ekranga cho'zilganda ham tiniq qolsin
          filterQuality: FilterQuality.medium,
          loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 56)),
        ),
      ]);
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _Action({required this.icon, required this.label, required this.onTap, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Icon(icon, color: color, size: 31, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)]),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(color: Color(0x88000000), blurRadius: 6)])),
          ]),
        ),
      );
}

class _ReasonBadge extends StatelessWidget {
  final _Reel reel;
  const _ReasonBadge({required this.reel});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (String text, Color bg, Color fg, IconData icon) = switch (reel.reason) {
      'following' => (reel.isNew ? '${tr('Obunangiz')} · ${tr('Yangi')}' : tr('Obunangiz'), p.accent, const Color(0xFF14161A), Icons.notifications_active_rounded),
      'interest' => (tr('Siz uchun'), const Color(0xFF7C5CFF), Colors.white, Icons.auto_awesome),
      _ => (tr('Top'), Colors.white.withValues(alpha: .18), Colors.white, Icons.local_fire_department_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;
  const _GlassChip({required this.icon, required this.label, required this.onTap, this.highlight = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: highlight ? p.accent : Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: highlight ? const Color(0xFF14161A) : Colors.white),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: highlight ? const Color(0xFF14161A) : Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _SheetChip(this.text, {required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white54, size: 56),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}
