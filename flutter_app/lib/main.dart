import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'l10n.dart';
import 'notify.dart';
import 'realtime.dart';
import 'screens/account_screen.dart';
import 'screens/onboarding_screen.dart';
import 'state.dart';
import 'theme.dart';
import 'screens/shops_screen.dart';
import 'screens/reels_screen.dart';
import 'screens/assistant_screen.dart';
import 'screens/my_orders_screen.dart';
import 'screens/seller/seller_home.dart';
import 'screens/seller/auth_screen.dart';
import 'screens/courier/courier_home.dart';
import 'widgets.dart';

/// Hozir ochiq pastki bo'lim (Reels ko'rish vaqtini faqat u ochiq bo'lganda hisoblaydi). -1: sotuvchi yoki kuryer rejimi
final rootTab = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Kontent status bar va pastki tizim paneli ostiga ham cho'ziladi (edge-to-edge)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const SalerApp());
}

/// Status bar ikonkalari mavzuga qarab qora/oq bo'ladi, panellar shaffof
SystemUiOverlayStyle overlayFor(Brightness b) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: b == Brightness.dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: b,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: b == Brightness.dark ? Brightness.light : Brightness.dark,
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
    // Splash: Android splashi bilan bir xil — qora fon, sariq logo (Yandex uslubi)
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(children: [
        Positioned(top: -140, left: -100, child: _Glow(p.accent.withValues(alpha: .18), 420)),
        Positioned(bottom: -160, right: -120, child: _Glow(const Color(0xFFFF8A00).withValues(alpha: .14), 400)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: .7 + .3 * v, child: child)),
                child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: p.accent.withValues(alpha: .35), offset: const Offset(0, 16), blurRadius: 44)]),
                child: Image.asset('assets/img/logo_circle.png', fit: BoxFit.contain),
              ),
              ),
              const SizedBox(height: 22),
              const Text('Saler AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.6, color: Colors.white)),
              const SizedBox(height: 4),
              Text("Do'kon va AI sotuvchi", style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: .6), fontWeight: FontWeight.w600)),
              const SizedBox(height: 32),
              if (error == null)
                SizedBox(
                  width: 120,
                  child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(minHeight: 4, color: p.accent, backgroundColor: p.accent.withValues(alpha: .15))),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: p.danger.withValues(alpha: .18), borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Icon(Icons.cloud_off_rounded, color: p.danger),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Text("Serverga ulanib bo'lmadi.\nInternetni tekshirib, qayta urinib ko'ring.", style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600, height: 1.4))),
                  ]),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))),
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
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]))),
      );
}

class SalerApp extends StatefulWidget {
  const SalerApp({super.key});
  @override
  State<SalerApp> createState() => _SalerAppState();
}

class _SalerAppState extends State<SalerApp> {
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
    if (Api.instance.registered) AppState.instance.startLive();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => MaterialApp(
        title: 'Saler AI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppState.instance.themeMode,
        builder: (ctx, child) => AnnotatedRegion<SystemUiOverlayStyle>(value: overlayFor(Theme.of(ctx).brightness), child: child!),
        home: FutureBuilder(
          future: _init,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const BootSplash();
            if (snap.hasError) {
              debugPrint('Boot xatosi: ${snap.error}');
              return BootSplash(error: '${snap.error}', onRetry: () => setState(() => _init = _boot()));
            }
            // Birinchi kirishda tanishtiruv: til tanlash va bannerlar, oxirida hisob ekrani
            if (!AppState.instance.onboarded) return OnboardingScreen(onDone: () => setState(() {}));
            // Ilovadan foydalanish uchun hisob majburiy
            if (!Api.instance.registered) {
              return AccountScreen(onDone: () {
                AppState.instance.startLive();
                Realtime.instance.restart();
                setState(() {});
              });
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
  Widget build(BuildContext context) => Navigator(key: navKey, onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => root, settings: s));
}

class NavItem {
  final IconData icon;
  final IconData active;
  final String label;
  const NavItem(this.icon, this.active, this.label);
}

/// Suzuvchi pastki navigatsiya (dizayndagi oq pill)
class FloatingNav extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final Map<int, int> badges;
  const FloatingNav({super.key, required this.items, required this.index, required this.onTap, this.badges = const {}});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + MediaQuery.of(context).padding.bottom * .5),
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? .45 : .14), offset: const Offset(0, 12), blurRadius: 32)]),
        child: Glass(
          radius: 22,
          child: SizedBox(
            height: 66,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => onTap(i),
                        borderRadius: BorderRadius.circular(16),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Stack(clipBehavior: Clip.none, children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 44,
                              height: 30,
                              decoration: BoxDecoration(color: i == index ? p.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                              child: Icon(i == index ? items[i].active : items[i].icon, size: 22, color: i == index ? p.text : p.muted),
                            ),
                            if ((badges[i] ?? 0) > 0)
                              Positioned(
                                top: -6,
                                right: -4,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 16),
                                  height: 16,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(8)),
                                  alignment: Alignment.center,
                                  child: Text('${badges[i]}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 3),
                          Text(items[i].label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: i == index ? p.text : p.muted)),
                        ]),
                      ),
                    ),
                ])),
          ),
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
            width: 40, height: 40, decoration: BoxDecoration(color: context.p.accentSoft, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.shopping_bag_rounded, color: context.p.accent)),
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: context.p.muted))
        ]),
        backgroundColor: context.p.card,
        actions: [TextButton(onPressed: () => m.hideCurrentMaterialBanner(), child: Text(tr('Yopish')))],
      ));
      Future.delayed(const Duration(seconds: 6), () => messenger.currentState?.hideCurrentMaterialBanner());
    };
    if (sellerMode) AppState.instance.startPolling();
  }

  void switchMode(bool seller) {
    setState(() {
      sellerMode = seller;
      courierMode = false;
      index = 0;
    });
    // Sotuvchi kirgan bo'lsa, buyurtmalarni kuzatishni har doim davom ettiramiz
    AppState.instance.sellerShop != null ? AppState.instance.startPolling() : AppState.instance.stopPolling();
    // Sessiya kanallari o'zgardi (do'kon), jonli aloqa qayta ulanadi
    Realtime.instance.restart();
  }

  void onTab(int i) {
    if (i == index) {
      keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Til/mavzu o'zgarganda pastki navigatsiya ham yangilanadi
    return ScaffoldMessenger(key: messenger, child: ListenableBuilder(listenable: AppState.instance, builder: (context, _) => _build(context)));
  }

  Widget _build(BuildContext context) {
    final visibleTab = sellerMode || courierMode ? -1 : index;
    WidgetsBinding.instance.addPostFrameCallback((_) => rootTab.value = visibleTab);
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
      TabNavigator(key: ValueKey('t0$lk'), navKey: keys[0], root: ShopsScreen(onSeller: () => switchMode(true))),
      // Reels: reytingi baland va qiziqishga mos mahsulotlar
      TabNavigator(key: ValueKey('t1$lk'), navKey: keys[1], root: const ReelsScreen()),
      // Chat tabi — ilova yordamchisi Sofia (do'kon topib tavsiya beradi)
      TabNavigator(key: ValueKey('t2$lk'), navKey: keys[2], root: AssistantScreen(onClose: () => setState(() => index = 0))),
      TabNavigator(key: ValueKey('t3$lk'), navKey: keys[3], root: const MyOrdersScreen()),
      TabNavigator(key: ValueKey('t4$lk'), navKey: keys[4], root: SellerEntry(onEntered: () => switchMode(true), onCourierEntered: () {
            setState(() {
              courierMode = true;
              sellerMode = false;
              index = 0;
            });
            Realtime.instance.restart();
          })),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = keys[index].currentState;
        if (nav != null && nav.canPop()) nav.pop();
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: index, children: pages),
        // Chat tabida panel yashiriladi; Reels'da panel kontent ustida suzib turadi
        bottomNavigationBar: index == 2
            ? null
            : FloatingNav(
          index: index,
          onTap: onTab,
          items: [
            NavItem(Icons.storefront_outlined, Icons.storefront_rounded, tr("Do'konlar")),
            NavItem(Icons.play_circle_outline_rounded, Icons.play_circle_rounded, tr('Reels')),
            NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, tr('Chat')),
            NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, tr('Buyurtmalar')),
            NavItem(Icons.person_outline_rounded, Icons.person_rounded, tr('Sotuvchi')),
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
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Colors.red.shade700 : null, margin: const EdgeInsets.fromLTRB(16, 0, 16, 100)));
}

Future<bool> confirmDialog(BuildContext context, String title, {String? text, String? ok, bool danger = false}) async {
  final okText = ok ?? tr('Ha');
  final r = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (c) => AlertDialog(
      icon: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: (danger ? c.p.danger : const Color(0xFFE8A317)).withValues(alpha: .14), borderRadius: BorderRadius.circular(16)),
        child: Icon(danger ? Icons.delete_outline : Icons.info_outline, color: danger ? c.p.danger : const Color(0xFFA86F00)),
      ),
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: text == null ? null : Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.p.muted)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Bekor qilish')))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(style: danger ? FilledButton.styleFrom(backgroundColor: c.p.danger) : null, onPressed: () => Navigator.pop(c, true), child: Text(okText))),
        ]),
      ],
    ),
  );
  return r == true;
}
