import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'anim.dart';
import 'api.dart';
import 'deeplink.dart';
import 'l10n.dart';
import 'notify.dart';
import 'realtime.dart';
import 'screens/auth/role_screen.dart';
import 'screens/onboarding_screen.dart';
import 'state.dart';
import 'theme.dart';
import 'screens/shops_screen.dart';
import 'screens/reels_screen.dart';
import 'screens/buyer_profile_screen.dart';
import 'screens/map_screen.dart';
import 'screens/seller/seller_home.dart';
import 'screens/seller/auth_screen.dart';
import 'screens/courier/courier_home.dart';
import 'widgets.dart';

/// Hozir ochiq pastki bo'lim (Reels ko'rish vaqtini faqat u ochiq bo'lganda hisoblaydi). -1: sotuvchi yoki kuryer rejimi
final rootTab = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Web'da manzil `#` siz bo'ladi: ulashilgan havola `/p/<id>` ko'rinishida
  // ochiladi va brauzerda chiroyli ko'rinadi (render.yaml `/*` ni index.html
  // ga yo'naltiradi, shuning uchun bunday manzil 404 bermaydi).
  usePathUrlStrategy();
  // Kontent status bar va pastki tizim paneli ostiga ham cho'ziladi (edge-to-edge)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const RydexApp());
}

/// Status bar ikonkalari mavzuga qarab qora/oq bo'ladi, panellar shaffof
SystemUiOverlayStyle overlayFor(Brightness b) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          b == Brightness.dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: b,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          b == Brightness.dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

/// Ilova yuklanayotgandagi brend splash (Android splash bilan bir xil fon)
class BootSplash extends StatelessWidget {
  final String? error;
  final VoidCallback? onRetry;
  const BootSplash({super.key, this.error, this.onRetry});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = context.isDark;
    // Splash butun kirish oqimi bilan bir xil: kunduzi oq-sariq, tunda qora
    return Scaffold(
      backgroundColor: brandBg(context),
      body: Stack(children: [
        Positioned(
            top: -140,
            left: -100,
            child: _Glow(p.accent.withValues(alpha: dark ? .18 : .45), 420)),
        Positioned(
            bottom: -160,
            right: -120,
            child: _Glow(const Color(0xFFFF8A00).withValues(alpha: dark ? .14 : .16), 400)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Opacity(
                    opacity: v.clamp(0, 1),
                    child: Transform.scale(scale: .7 + .3 * v, child: child)),
                child: Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                    BoxShadow(
                        color: p.accent.withValues(alpha: .35),
                        offset: const Offset(0, 16),
                        blurRadius: 44)
                  ]),
                  // Logo atrofida aylanuvchi sariq yoy — yuklash belgisi
                  child: RydexLoader(size: 148, showLogo: true, color: p.accent),
                ),
              ),
              const SizedBox(height: 22),
              AppearIn(
                delay: const Duration(milliseconds: 160),
                child: Text('Rydex',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
                        color: brandFg(context))),
              ),
              const SizedBox(height: 4),
              AppearIn(
                delay: const Duration(milliseconds: 260),
                child: Text("Do'kon va AI sotuvchi",
                    style: TextStyle(
                        fontSize: 14,
                        color: brandFgSoft(context, .6),
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 30),
              if (error == null)
                ShimmerText(tr('Yuklanmoqda'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: brandFgSoft(context, .45)))
              else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: p.danger.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Icon(Icons.cloud_off_rounded, color: p.danger),
                    const SizedBox(width: 10),
                    // Serverning o'z xabari ko'rsatiladi: "Server uyg'onmoqda",
                    // "Internet aloqasi yo'q" yoki sozlama xatosi — nima
                    // qilish kerakligi darhol ma'lum bo'lsin.
                    Expanded(
                        child: Text(
                            error!.replaceFirst('ApiException: ', '').trim(),
                            style: TextStyle(
                                fontSize: 13,
                                color: brandFg(context),
                                fontWeight: FontWeight.w600,
                                height: 1.4))),
                  ]),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(tr('Qayta urinish'))),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color c;
  final double size;
  const _Glow(this.c, this.size);
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]))),
      );
}

class RydexApp extends StatefulWidget {
  const RydexApp({super.key});
  @override
  State<RydexApp> createState() => _RydexAppState();
}

class _RydexAppState extends State<RydexApp> {
  late Future<void> _init = _boot();

  @override
  void initState() {
    super.initState();
    // Server hisob talab qilsa (masalan sessiya o'chirilgan), kirish ekraniga qaytamiz
    Api.instance.onNeedAuth = () {
      Realtime.instance.stop();
      if (mounted) setState(() {});
    };
  }

  Future<void> _boot() async {
    await Api.instance.init();
    await AppState.instance.load();
    await Notify.instance.init();
    // Jonli yangilanishlar mehmon uchun ham ishlaydi (buyurtma, pul, bildirishnoma)
    AppState.instance.startLive();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => MaterialApp(
        title: 'Rydex',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppState.instance.themeMode,
        builder: (ctx, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayFor(Theme.of(ctx).brightness), child: child!),
        home: FutureBuilder(
          future: _init,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const BootSplash();
            }
            if (snap.hasError) {
              debugPrint('Boot xatosi: ${snap.error}');
              return BootSplash(
                  error: '${snap.error}',
                  onRetry: () => setState(() => _init = _boot()));
            }
            // Ulashilgan havola bilan kirilgan bo'lsa (/p/<id> yoki /s/<id>) —
            // tanishtiruvsiz to'g'ridan to'g'ri mahsulot yoki do'kon ochiladi.
            // Odam havolani bosganida darhol kerakli narsani ko'rishi shart.
            final shared = DeepLink.pending;
            if (shared != null) {
              return SharedEntry(link: shared, onClose: () => setState(() => DeepLink.pending = null));
            }
            // Birinchi kirishda tanishtiruv: til tanlash va bannerlar, oxirida hisob ekrani
            if (!AppState.instance.onboarded) {
              return OnboardingScreen(onDone: () => setState(() {}));
            }
            // Kim bo'lib davom etish: xaridor to'g'ridan to'g'ri ilovaga kiradi,
            // sotuvchi/kuryer/yuk tashuvchi ro'yxatdan o'tadi yoki hisobiga kiradi
            if (!AppState.instance.rolePicked) {
              return RoleScreen(onDone: () => setState(() {}));
            }
            return const RootShell();
          },
        ),
      ),
    );
  }
}

/// Har bir tab o'z navigatsiyasiga ega — ichki sahifalar ochilganda pastki panel yo'qolmaydi
class TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navKey;
  final Widget root;
  const TabNavigator({super.key, required this.navKey, required this.root});
  @override
  Widget build(BuildContext context) => Navigator(
      key: navKey,
      onGenerateRoute: (s) =>
          MaterialPageRoute(builder: (_) => root, settings: s));
}

class NavItem {
  final IconData icon;
  final IconData active;
  final String label;
  const NavItem(this.icon, this.active, this.label);
}

/// Oddiy oq pastki navigatsiya: blur, gradient va glow yo'q — faqat oq fon,
/// ingichka yuqori chiziq va bo'limlar teng kenglikda. Har rejim bir xil
/// komponentdan foydalangani uchun xaridor, sotuvchi va kuryer
/// interfeyslarining hissi yagona bo'lib qoladi.
class FloatingNav extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final Map<int, int> badges;
  const FloatingNav(
      {super.key,
      required this.items,
      required this.index,
      required this.onTap,
      this.badges = const {}});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6E8EC))),
      ),
      // Telefon pastidagi tizim chizig'i ustiga tushib qolmasligi uchun.
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _PlainNavItem(
                    item: items[i],
                    selected: i == index,
                    badge: badges[i] ?? 0,
                    badgeColor: p.danger,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlainNavItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final int badge;
  final Color badgeColor;
  final VoidCallback onTap;
  const _PlainNavItem(
      {required this.item,
      required this.selected,
      required this.badge,
      required this.badgeColor,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Oq fonda tanlangan bo'lim qora, qolganlari kulrang. Boshqa ajratuvchi
    // belgi yo'q — nom har doim ko'rinib turgani uchun kifoya.
    const activeColor = Color(0xFF101722);
    const idleColor = Color(0xFF8A9099);
    final color = selected ? activeColor : idleColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? item.active : item.icon,
                    size: 24, color: color),
                if (badge > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.white, width: 1.5)),
                      alignment: Alignment.center,
                      child: Text('$badge',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -.1)),
          ],
        ),
      ),
    );
  }
}

/// Xaridor rejimi (4 tab) yoki sotuvchi rejimi
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int index = 0;
  bool sellerMode = false;
  bool courierMode = false;
  final keys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final messenger = GlobalKey<ScaffoldMessengerState>();
  // Bo'limlar orasida yonga surib o'tish uchun
  final pager = PageController();

  @override
  void initState() {
    super.initState();
    sellerMode = AppState.instance.sellerShop != null;
    courierMode = !sellerMode && AppState.instance.courier != null;
    // Ilova ochiq bo'lsa, yangi buyurtma banner sifatida ham ko'rinadi
    Notify.instance.onInApp = (title, body) {
      final m = messenger.currentState;
      if (m == null) return;
      m.hideCurrentMaterialBanner();
      m.showMaterialBanner(MaterialBanner(
        leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: context.p.accentSoft,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.shopping_bag_rounded, color: context.p.accent)),
        content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: context.p.muted))
            ]),
        backgroundColor: context.p.card,
        actions: [
          TextButton(
              onPressed: () => m.hideCurrentMaterialBanner(),
              child: Text(tr('Yopish')))
        ],
      ));
      Future.delayed(const Duration(seconds: 6),
          () => messenger.currentState?.hideCurrentMaterialBanner());
    };
    if (sellerMode) AppState.instance.startPolling();
  }

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  void switchMode(bool seller) {
    setState(() {
      sellerMode = seller;
      courierMode = false;
      index = 0;
    });
    if (pager.hasClients) pager.jumpToPage(0);
    // Sotuvchi kirgan bo'lsa, buyurtmalarni kuzatishni har doim davom ettiramiz
    AppState.instance.sellerShop != null
        ? AppState.instance.startPolling()
        : AppState.instance.stopPolling();
    // Sessiya kanallari o'zgardi (do'kon), jonli aloqa qayta ulanadi
    Realtime.instance.restart();
  }

  void onTab(int i) {
    if (i < 0 || i >= keys.length) return;
    if (i == index) {
      keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    final from = index;
    setState(() => index = i);
    // Yonma-yon bo'lsa suriladi, uzoq bo'lsa darhol o'tadi
    if (!pager.hasClients) return;
    if ((i - from).abs() <= 1) {
      pager.animateToPage(i,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    } else {
      pager.jumpToPage(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Til/mavzu o'zgarganda pastki navigatsiya ham yangilanadi
    return ScaffoldMessenger(
        key: messenger,
        child: ListenableBuilder(
            listenable: AppState.instance,
            builder: (context, _) => _build(context)));
  }

  Widget _build(BuildContext context) {
    final visibleTab = sellerMode || courierMode ? -1 : index;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => rootTab.value = visibleTab);
    if (sellerMode && AppState.instance.sellerShop != null) {
      return SellerHome(onExit: () => switchMode(false));
    }
    if (courierMode && AppState.instance.courier != null) {
      return CourierHome(onExit: () {
        setState(() => courierMode = false);
        Realtime.instance.restart();
      });
    }
    // Til o'zgarganda tab sahifalari qayta quriladi (Navigator ichidagi sahifalar o'z-o'zidan yangilanmaydi)
    final lk = L10n.lang.name;
    final pages = [
      TabNavigator(
          key: ValueKey('t0$lk'),
          navKey: keys[0],
          root: ShopsScreen(onSeller: () => switchMode(true))),
      // Reels: reytingi baland va qiziqishga mos mahsulotlar
      TabNavigator(
          key: ValueKey('t1$lk'), navKey: keys[1], root: const ReelsScreen()),
      // Xarita tabi: do'konlar va yo'nalishlar. Sofia chatiga bosh sahifadagi
      // banner orqali kiriladi, shu sabab navigatsiya bitta ortiqcha tabdan xoli.
      TabNavigator(
          key: ValueKey('t2$lk'),
          navKey: keys[2],
          root: const MapScreen(inTab: true)),
      TabNavigator(
          key: ValueKey('t3$lk'),
          navKey: keys[3],
          root: SellerEntry(
              onEntered: () => switchMode(true),
              onCourierEntered: () {
                setState(() {
                  courierMode = true;
                  sellerMode = false;
                  index = 0;
                });
                Realtime.instance.restart();
              })),
      TabNavigator(
          key: ValueKey('t4$lk'),
          navKey: keys[4],
          root: const BuyerProfileScreen()),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = keys[index].currentState;
        if (nav != null && nav.canPop()) nav.pop();
      },
      child: Scaffold(
        body: PageView(
          controller: pager,
          // Ichki Reels foto-sliderni va xaritani Flutter gesture arenasi
          // birinchi oladi; bo'sh joyda esa yonga surish bilan keyingi bo'limga
          // o'tiladi. Shu sabab barcha tablarda asosiy pager faol.
          physics: const PageScrollPhysics(),
          onPageChanged: (i) {
            if (i >= 0 && i < keys.length && i != index) {
              setState(() => index = i);
            }
          },
          children: [for (final page in pages) KeepAlivePage(child: page)],
        ),
        // Reels va xarita ekranlarida ham panel kontent ustida suzib turadi.
        bottomNavigationBar: FloatingNav(
          index: index,
          onTap: onTab,
          items: [
            NavItem(Icons.storefront_outlined, Icons.storefront_rounded,
                tr("Do'konlar")),
            NavItem(Icons.play_circle_outline_rounded,
                Icons.play_circle_rounded, tr('Reels')),
            NavItem(Icons.map_outlined, Icons.map_rounded, tr('Xarita')),
            NavItem(Icons.grid_view_outlined, Icons.grid_view_rounded,
                tr('Xizmatlar')),
            NavItem(Icons.person_outline_rounded, Icons.person_rounded,
                tr('Profil')),
          ],
        ),
      ),
    );
  }
}

/// Umumiy yordamchilar
void showToast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16)));
}

Future<bool> confirmDialog(BuildContext context, String title,
    {String? text, String? ok, bool danger = false}) async {
  final okText = ok ?? tr('Ha');
  final r = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (c) => AlertDialog(
      icon: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
            color: (danger ? c.p.danger : const Color(0xFFE8A317))
                .withValues(alpha: .14),
            borderRadius: BorderRadius.circular(16)),
        child: Icon(danger ? Icons.delete_outline : Icons.info_outline,
            color: danger ? c.p.danger : const Color(0xFFA86F00)),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: text == null
          ? null
          : Text(text,
              textAlign: TextAlign.center, style: TextStyle(color: c.p.muted)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text(tr('Bekor qilish')))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(
                  style: danger
                      ? FilledButton.styleFrom(backgroundColor: c.p.danger)
                      : null,
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(okText))),
        ]),
      ],
    ),
  );
  return r == true;
}
