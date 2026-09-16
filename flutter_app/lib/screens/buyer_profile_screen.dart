import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../main.dart' show confirmDialog;
import '../realtime.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth/buyer_auth.dart';
import 'map_screen.dart';
import 'my_orders_screen.dart';
import 'rating_screen.dart';
import 'shops_screen.dart' show FavoritesScreen, openCart;

/// Xaridorning alohida profili.
///
/// Buyurtmalar pastki navigatsiyani band qilmaydi: u shu profil ichidagi
/// asosiy bo'lim sifatida ochiladi. Mehmon foydalanuvchi ham bu yerda email
/// orqali hisobini tasdiqlashi mumkin.
class BuyerProfileScreen extends StatefulWidget {
  const BuyerProfileScreen({super.key});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  Future<void> _openOrders() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    if (await ensureBuyer(context) && mounted) setState(() {});
  }

  Future<void> _logout() async {
    if (!await confirmDialog(context, tr('Hisobdan chiqasizmi?'),
        ok: tr('Chiqish'), danger: true)) {
      return;
    }
    await Api.instance.logout();
    final state = AppState.instance;
    state.stopPolling();
    state.sellerShop = null;
    state.courier = null;
    Realtime.instance.restart();
    state.refresh();
    if (mounted) setState(() {});
  }

  void _cycleTheme() {
    final current = AppState.instance.themeMode;
    final next =
        ThemeMode.values[(current.index + 1) % ThemeMode.values.length];
    AppState.instance.setTheme(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final p = context.p;
        final api = Api.instance;
        final registered = api.registered;
        final name = registered
            ? api.userName.trim().isEmpty
                ? tr('Xaridor')
                : api.userName.trim()
            : tr('Mehmon');
        final initialsText = initials(name).isEmpty ? '?' : initials(name);
        return Scaffold(
          appBar: AppBar(title: Text(tr('Profil'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, navPad),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(22),
                  border: context.isDark ? Border.all(color: p.border) : null,
                  boxShadow: softShadow(context),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: p.accentSoft,
                        borderRadius: BorderRadius.circular(19),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initialsText,
                        style: TextStyle(
                          color: p.accentText,
                          fontWeight: FontWeight.w900,
                          fontSize: 21,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18)),
                          const SizedBox(height: 3),
                          Text(
                            registered
                                ? (api.phone?.isNotEmpty == true
                                    ? api.phone!
                                    : api.email ?? '')
                                : tr("Buyurtma berish uchun tizimga kiring"),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.muted,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (registered)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: p.successSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.verified_rounded,
                            size: 16, color: p.success),
                      ),
                  ],
                ),
              ),
              if (!registered) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _signIn,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(tr('Tizimga kirish')),
                ),
              ],
              const SizedBox(height: 22),
              Text(tr('Tezkor amallar'),
                  style: TextStyle(
                      color: p.muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: .4)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                // Ikki qatorli (mavzu/til) yozuvlar kichik ekranlarda ham
                // kesilmasligi uchun kartochka biroz balandroq turadi.
                childAspectRatio: 1.18,
                children: [
                  _QuickAction(
                    icon: switch (AppState.instance.themeMode) {
                      ThemeMode.light => Icons.light_mode_outlined,
                      ThemeMode.dark => Icons.dark_mode_outlined,
                      _ => Icons.brightness_auto_outlined,
                    },
                    label: tr('Mavzu'),
                    subtitle: switch (AppState.instance.themeMode) {
                      ThemeMode.light => tr("Yorug'"),
                      ThemeMode.dark => tr("Qorong'i"),
                      _ => tr('Avtomatik'),
                    },
                    onTap: _cycleTheme,
                  ),
                  _QuickAction(
                    icon: Icons.shopping_cart_outlined,
                    label: tr('Savatcha'),
                    badge: AppState.instance.cartCount,
                    onTap: () => openCart(context),
                  ),
                  _QuickAction(
                    icon: Icons.favorite_border_rounded,
                    label: tr('Sevimlilar'),
                    badge: AppState.instance.favs.length,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FavoritesScreen())),
                  ),
                  _QuickAction(
                    icon: Icons.translate_rounded,
                    label: tr('Til'),
                    subtitle:
                        '${L10n.flags[L10n.lang]} ${L10n.names[L10n.lang]}',
                    onTap: () => showLangSheet(context),
                  ),
                  _QuickAction(
                    icon: Icons.map_outlined,
                    label: tr('Xarita'),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MapScreen())),
                  ),
                  _QuickAction(
                    icon: Icons.workspace_premium_rounded,
                    label: tr('Reyting'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RatingScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(tr('Mening sahifam'),
                  style: TextStyle(
                      color: p.muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: .4)),
              const SizedBox(height: 8),
              _ProfileCard(children: [
                _ProfileTile(
                  icon: Icons.receipt_long_outlined,
                  title: tr('Buyurtmalarim'),
                  subtitle: tr("Berilgan buyurtmalar va ularning holati"),
                  onTap: _openOrders,
                ),
              ]),
              if (registered) ...[
                const SizedBox(height: 18),
                Text(tr('Aloqa ma\'lumotlari'),
                    style: TextStyle(
                        color: p.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: .4)),
                const SizedBox(height: 8),
                _ProfileCard(children: [
                  if (api.email?.isNotEmpty == true)
                    _ProfileInfo(Icons.alternate_email_rounded, api.email!),
                  if (api.telegram?.isNotEmpty == true)
                    _ProfileInfo(Icons.send_outlined, api.telegram!),
                  if (api.phone?.isNotEmpty == true)
                    _ProfileInfo(Icons.phone_outlined, api.phone!),
                ]),
              ],
              if (registered) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.danger,
                    side: BorderSide(color: p.danger.withValues(alpha: .26)),
                  ),
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(tr('Hisobdan chiqish')),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final List<Widget> children;
  const _ProfileCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: context.isDark ? Border.all(color: p.border) : null,
        boxShadow: softShadow(context, y: 5, blur: 18, a: .04),
      ),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                Divider(height: 1, indent: 68, color: p.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final int? badge;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: context.isDark ? Border.all(color: p.border) : null,
            boxShadow: softShadow(context, y: 5, blur: 16, a: .035),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: p.accentSoft,
                          borderRadius: BorderRadius.circular(13)),
                      alignment: Alignment.center,
                      child: Icon(icon, color: p.accentText, size: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 11.5)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: p.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 9.5)),
                  ],
                ),
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(9)),
                    child: Text('$badge',
                        style: TextStyle(
                            color: p.onAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListTile(
      minVerticalPadding: 13,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: p.accentSoft, borderRadius: BorderRadius.circular(13)),
        alignment: Alignment.center,
        child: Icon(icon, color: p.accentText, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: p.muted, fontWeight: FontWeight.w600, fontSize: 11.5)),
      trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
      onTap: onTap,
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ProfileInfo(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
        child: Row(children: [
          Icon(icon, size: 19, color: context.p.muted),
          const SizedBox(width: 13),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
