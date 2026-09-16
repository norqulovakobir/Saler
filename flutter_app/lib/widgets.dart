import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'api.dart';
import 'config.dart';
import 'l10n.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';

const _colors = [
  0xFF3B6BFF,
  0xFFF4A261,
  0xFF1F9D6A,
  0xFFD63384,
  0xFF7C5CFF,
  0xFFE4572E,
  0xFF17BEBB,
  0xFF2A9D8F
];
Color colorFor(String s) =>
    Color(_colors[s.codeUnits.fold(0, (a, b) => a + b) % _colors.length]);
String initials(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((w) => w.isEmpty ? '' : w[0])
    .join()
    .toUpperCase();

/// Pastki navigatsiya balandligi uchun ro'yxat padding'i
// Pastki "floating pill" navigatsiya balandroq: aktiv bo'limning nomi ham shu
// panel ichida ko'rinadi, shuning uchun ro'yxatlar uning ostida qolmasin.
const double navPad = 116;

/// 42px yumaloq ikonka tugmasi (sarlavha uchun)
class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final Color? bg;
  final int? badge;
  final double size;
  const IconBtn(this.icon,
      {super.key, this.onTap, this.color, this.bg, this.badge, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Stack(clipBehavior: Clip.none, children: [
      Material(
        color: bg ?? p.card,
        borderRadius: BorderRadius.circular(size * .33),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size * .33),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * .33),
                boxShadow: bg == null
                    ? softShadow(context, y: 4, blur: 14, a: .06)
                    : null),
            child: Icon(icon, size: size * .5, color: color ?? p.text),
          ),
        ),
      ),
      if (badge != null && badge! > 0)
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18),
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
                color: p.accent, borderRadius: BorderRadius.circular(9)),
            alignment: Alignment.center,
            child: Text('$badge',
                style: TextStyle(
                    color: p.onAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
  }
}

/// Kun/tun tugmasi: avtomatik → yorug' → qorong'i
class ThemeBtn extends StatelessWidget {
  final double size;
  const ThemeBtn({super.key, this.size = 42});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppState.instance,
        builder: (_, __) {
          final m = AppState.instance.themeMode;
          final icon = switch (m) {
            ThemeMode.light => Icons.light_mode_outlined,
            ThemeMode.dark => Icons.dark_mode_outlined,
            _ => Icons.brightness_auto_outlined
          };
          return IconBtn(icon, size: size, onTap: () {
            final next = ThemeMode.values[(m.index + 1) % 3];
            AppState.instance.setTheme(next);
            ScaffoldMessenger.maybeOf(context)
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                  content: Text('Mavzu: ${const {
                    ThemeMode.system: 'Avtomatik',
                    ThemeMode.light: "Yorug'",
                    ThemeMode.dark: "Qorong'i"
                  }[next]}'),
                  duration: const Duration(seconds: 1),
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 100)));
          });
        },
      );
}

/// Til tugmasi: bosilganda til tanlash oynasi
class LangBtn extends StatelessWidget {
  final double size;
  const LangBtn({super.key, this.size = 42});
  @override
  Widget build(BuildContext context) => IconBtn(Icons.translate_rounded,
      size: size, onTap: () => showLangSheet(context));
}

/// Til tanlash oynasi (xaridor va sotuvchi uchun bir xil)
void showLangSheet(BuildContext context) {
  showModalBottomSheet(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Ilova tili'),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4)),
            const SizedBox(height: 12),
            for (final l in AppLang.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: L10n.lang == l ? c.p.accentSoft : c.p.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      AppState.instance.setLang(l);
                      Navigator.pop(c);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: L10n.lang == l ? c.p.accent : c.p.border,
                              width: L10n.lang == l ? 1.5 : 1)),
                      child: Row(children: [
                        Text(L10n.flags[l]!,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(L10n.names[l]!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15))),
                        if (L10n.lang == l)
                          Icon(Icons.check_circle_rounded,
                              color: c.p.accentText),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
    ),
  );
}

/// Glassmorphism panel: orqasidagi kontent xiralashib ko'rinadi
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  const Glass({super.key, required this.child, this.radius = 22, this.padding});
  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: (dark ? const Color(0xFF1C1F25) : Colors.white)
                .withValues(alpha: dark ? .62 : .66),
            border: Border.all(
                color: Colors.white.withValues(alpha: dark ? .08 : .6),
                width: 1),
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: dark ? .06 : .35),
                  Colors.white.withValues(alpha: 0)
                ]),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Rol belgisi (avatar chetidagi kichik doira): sotuvchi / kuryer / yuk tashuvchi / boshqa
class RoleBadge extends StatelessWidget {
  final String role; // seller | courier | cargo | other
  final double size;
  const RoleBadge(this.role, {super.key, this.size = 20});
  static IconData iconOf(String role) => switch (role) {
        'seller' => Icons.storefront_rounded,
        'courier' => Icons.two_wheeler_rounded,
        'cargo' => Icons.local_shipping_rounded,
        _ => Icons.person_rounded
      };
  static Color colorOf(String role) => switch (role) {
        'seller' => const Color(0xFFFFCC00),
        'courier' => const Color(0xFF1F9D6A),
        'cargo' => const Color(0xFFFF8A00),
        _ => const Color(0xFF6B7280)
      };
  static String labelOf(String role) => switch (role) {
        'seller' => tr('Sotuvchi'),
        'courier' => tr('Kuryer'),
        'cargo' => tr('Yuk tashuvchi'),
        _ => tr('Boshqa')
      };
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: colorOf(role),
            shape: BoxShape.circle,
            border: Border.all(color: context.p.card, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
        child: Icon(iconOf(role),
            size: size * .55,
            color: role == 'seller' ? const Color(0xFF111111) : Colors.white),
      );
}

/// Kuryer / yuk tashuvchi avatari: profil rasmi yoki transport belgisi, chetida rol belgisi
class ProviderAvatar extends StatelessWidget {
  final String? photo;
  final IconData icon;
  final String role;
  final double size;
  final bool online;
  const ProviderAvatar(
      {super.key,
      this.photo,
      required this.icon,
      required this.role,
      this.size = 52,
      this.online = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              color: p.accent,
              shape: BoxShape.circle,
              border: online ? Border.all(color: p.success, width: 2.5) : null,
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
              ]),
          clipBehavior: Clip.antiAlias,
          child: photo != null
              ? Image.network(Api.instance.photoUrl(photo!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(icon, color: p.onAccent, size: size * .5))
              : Icon(icon, color: p.onAccent, size: size * .5),
        ),
        Positioned(
            right: -2,
            bottom: -2,
            child: RoleBadge(role, size: (size * .4).clamp(18, 26))),
      ]),
    );
  }
}

/// Do'kon avatari: logo yoki bosh harflar ([badge] — chetida "sotuvchi" belgisi)
class ShopAvatar extends StatelessWidget {
  final Shop shop;
  final double size;
  final bool shadow;
  final bool badge;
  const ShopAvatar(this.shop,
      {super.key, this.size = 48, this.shadow = false, this.badge = false});
  @override
  Widget build(BuildContext context) {
    final c = colorFor(shop.name);
    if (badge) {
      return SizedBox(
        width: size + 4,
        height: size + 4,
        child: Stack(clipBehavior: Clip.none, children: [
          ShopAvatar(shop, size: size, shadow: shadow),
          Positioned(
              right: -2,
              bottom: -2,
              child: RoleBadge('seller', size: (size * .38).clamp(18, 26))),
        ]),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .3),
          boxShadow: shadow
              ? [
                  BoxShadow(
                      color: c.withValues(alpha: .3),
                      offset: const Offset(0, 10),
                      blurRadius: 24)
                ]
              : null),
      clipBehavior: Clip.antiAlias,
      child: shop.logo != null
          ? Image.network(Api.instance.photoUrl(shop.logo!), fit: BoxFit.cover)
          : Container(
              color: c,
              alignment: Alignment.center,
              child: Text(initials(shop.name),
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: size * .36))),
    );
  }
}

/// Do'kon kartochkasi (bosh sahifa)
class ShopCard extends StatelessWidget {
  final Shop s;
  final VoidCallback onTap;
  const ShopCard(this.s, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = colorFor(s.name);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: softShadow(context),
              border: context.isDark ? Border.all(color: p.border) : null),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Container(
                height: 112,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        c.withValues(alpha: context.isDark ? .35 : .18),
                        c.withValues(alpha: context.isDark ? .15 : .06)
                      ]),
                ),
                clipBehavior: Clip.antiAlias,
                // Logo: orqada xiralashgan katta nusxasi, oldida aniq logo — premium "muqova" effekti
                child: s.logo != null
                    ? Stack(fit: StackFit.expand, children: [
                        ImageFiltered(
                            imageFilter:
                                ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Opacity(
                                opacity: .7,
                                child: Image.network(
                                    Api.instance.photoUrl(s.logo!),
                                    fit: BoxFit.cover))),
                        Center(
                            child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(19),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 14,
                                          offset: Offset(0, 6))
                                    ]),
                                child: ShopAvatar(s, size: 60))),
                      ])
                    : Center(child: ShopAvatar(s, size: 54)),
              ),
              Positioned(top: 8, right: 8, child: RatingPill(s)),
            ]),
            const SizedBox(height: 10),
            Text(s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Text(s.description.isNotEmpty ? s.description : s.sellerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: p.muted, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

/// Daraja rangi (Yangi/Bronza/Kumush/Oltin/Platina)
Color levelColor(String level) => switch (level) {
      'Platina' => const Color(0xFF6C7BFF),
      'Oltin' => const Color(0xFFE0A100),
      'Kumush' => const Color(0xFF8A94A6),
      'Bronza' => const Color(0xFFB8702A),
      _ => const Color(0xFF1F9D6A),
    };

/// Kartochkadagi reyting: yulduz + baho + daraja
class RatingPill extends StatelessWidget {
  final Shop s;
  const RatingPill(this.s, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xBF14161A),
            borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFC53D)),
          const SizedBox(width: 3),
          Text(s.rating.toStringAsFixed(1),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 5),
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: levelColor(s.level), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(trLevel(s.level),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

/// 5 ta yulduz (yarim yulduz bilan)
class Stars extends StatelessWidget {
  final double rating;
  final double size;
  const Stars(this.rating, {super.key, this.size = 16});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(
              rating >= i
                  ? Icons.star_rounded
                  : rating >= i - .5
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
              size: size,
              color: rating >= i - .5
                  ? const Color(0xFFFFC53D)
                  : context.p.muted.withValues(alpha: .5)),
      ]);
}

/// Mahsulot rasmi (birinchi rasm) yoki yumshoq gradient placeholder.
/// Rasm kesilmaydi — to'liq ko'rinadi (contain), orqasida yumshoq fon.
class ProductImage extends StatelessWidget {
  final Product p;
  final double? size;
  final double radius;
  const ProductImage(this.p, {super.key, this.size, this.radius = 14});
  @override
  Widget build(BuildContext context) {
    final pal = context.p;
    final bg = BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [pal.imageA, pal.imageB]));
    final ph = Container(
        width: size,
        height: size,
        decoration: bg,
        child: Icon(Icons.shopping_bag_outlined, size: 32, color: pal.muted));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: p.photos.isEmpty
          ? ph
          : Container(
              width: size,
              height: size,
              decoration: bg,
              child: Image.network(
                Api.instance.photoUrl(p.photos.first),
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => ph,
                loadingBuilder: (c, child, prog) => prog == null ? child : ph,
              ),
            ),
    );
  }
}

/// Mahsulot kartochkasi (grid)
class ProductCard extends StatelessWidget {
  final Product p;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  const ProductCard(this.p, {super.key, required this.onTap, this.onAdd});
  @override
  Widget build(BuildContext context) {
    final pal = context.p;
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final fav = AppState.instance.isFav(p.id);
        return Material(
          color: pal.card,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: softShadow(context),
                  border:
                      context.isDark ? Border.all(color: pal.border) : null),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(children: [
                      AspectRatio(
                          aspectRatio: 1,
                          child:
                              Hero(tag: 'p-${p.id}', child: ProductImage(p))),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: pal.card,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => AppState.instance.toggleFav(p),
                            child: SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                    fav
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 16,
                                    color: fav
                                        ? const Color(0xFFD63384)
                                        : pal.muted)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    height: 1.25)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(child: PriceText(p.price, size: 15)),
                              Material(
                                color: pal.bg,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () => Share.share(
                                      "${p.name} — ${fmtPrice(p.price)} so'm\nhttps://t.me/$botUsername?startapp=p_${p.id}",
                                      subject: p.name),
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: Icon(Icons.ios_share_rounded,
                                          size: 16, color: pal.text)),
                                ),
                              ),
                              if (onAdd != null) const SizedBox(width: 6),
                              if (onAdd != null)
                                Material(
                                  color: pal.accent,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                      onTap: onAdd,
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: Icon(Icons.add,
                                              size: 18, color: pal.onAccent))),
                                ),
                            ]),
                          ]),
                    ),
                  ]),
            ),
          ),
        );
      },
    );
  }
}

/// "6 500 000 so'm" — raqam qalin, valyuta kichik
class PriceText extends StatelessWidget {
  final num price;
  final double size;
  final Color? color;
  const PriceText(this.price, {super.key, this.size = 15, this.color});
  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(
            text: fmtPrice(price),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: size,
                color: color,
                letterSpacing: -.3)),
        TextSpan(
            text: " so'm",
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: size * .73,
                color: (color ?? context.p.text).withValues(alpha: .55))),
      ]));
}

/// Qidiruv maydoni ko'rinishi
class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String>? onChanged;

  /// Faqat katta bosh sahifa qidiruvi uchun balandlik beriladi; qolgan
  /// ekranlardagi qidiruvlar avvalgi ixcham o'lchamda qoladi.
  final double? height;
  const SearchField(
      {super.key, required this.hint, this.onChanged, this.height});
  @override
  Widget build(BuildContext context) {
    final field = TextField(
      onChanged: onChanged,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: context.p.muted),
          hintText: hint,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none)),
    );
    return Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: softShadow(context, y: 4, blur: 14)),
        child: height == null ? field : SizedBox(height: height, child: field));
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 12),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.2))),
          if (action != null)
            GestureDetector(
                onTap: onAction,
                child: Text(action!,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: context.p.accentText))),
        ]),
      );
}

/// Tanlov chiplari (Yangi / Arzon / ...)
class ChoiceChips extends StatelessWidget {
  final List<(String, String)> items;
  final String value;
  final ValueChanged<String> onChanged;
  const ChoiceChips(
      {super.key,
      required this.items,
      required this.value,
      required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = items[i].$1 == value;
          return Material(
            color: sel ? p.dark : p.card,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () => onChanged(items[i].$1),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: context.isDark && !sel
                        ? Border.all(color: p.border)
                        : null),
                child: Text(items[i].$2,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: sel ? p.onDark : p.text.withValues(alpha: .75))),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Yuklanish skeleti (spinner o'rniga) — yumshoq "nafas oladigan" bloklar
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const Skeleton(
      {super.key, required this.height, this.width, this.radius = 16});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .45, end: 1.0)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
                color: context.p.card,
                borderRadius: BorderRadius.circular(widget.radius),
                border: context.isDark
                    ? Border.all(color: context.p.border)
                    : null)),
      );
}

/// Grid skeleti (do'konlar / mahsulotlar)
class GridSkeleton extends StatelessWidget {
  final int count;
  final double aspect;
  const GridSkeleton({super.key, this.count = 4, this.aspect = .8});
  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspect),
        itemCount: count,
        itemBuilder: (_, __) => const Skeleton(height: 200, radius: 20),
      );
}

/// Ro'yxat elementlari pastdan yumshoq chiqib keladi
class FadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeIn({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 320 + (index.clamp(0, 8)) * 50),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
                offset: Offset(0, 14 * (1 - v)), child: child)),
        child: child,
      );
}

class EmptyBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyBox(this.icon, this.text, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: context.p.card,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: softShadow(context)),
                child: Icon(icon, size: 30, color: context.p.muted)),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.p.muted, fontWeight: FontWeight.w600)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class StatusBadge extends StatelessWidget {
  final String status;
  final String label;
  const StatusBadge(this.status, this.label, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = switch (status) {
      'done' => p.success,
      'cancelled' => p.danger,
      _ => p.accentText
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(99)),
      child: Text(label,
          style:
              TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}

/// Qora "premium" banner (AI sotuvchi, sotuv)
class DarkBanner extends StatelessWidget {
  final Widget child;
  final Color glow;
  final Color glow2;
  final EdgeInsetsGeometry padding;
  const DarkBanner(
      {super.key,
      required this.child,
      this.glow = const Color(0xFFFFCC00),
      this.glow2 = const Color(0xFFFF8A00),
      this.padding = const EdgeInsets.all(18)});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: context.p.dark,
            borderRadius: BorderRadius.circular(22),
            border:
                context.isDark ? Border.all(color: context.p.border) : null),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned(right: -40, top: -40, child: _Glow(glow, 160)),
          Positioned(right: 30, bottom: -60, child: _Glow(glow2, 140)),
          Padding(padding: padding, child: child),
        ]),
      );
}

class _Glow extends StatelessWidget {
  final Color c;
  final double size;
  const _Glow(this.c, this.size);
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
                colors: [c.withValues(alpha: .6), c.withValues(alpha: 0)])),
      );
}

String fmtTime(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}

/// Rasm manbasini tanlash oynasi: kamera yoki galereya. Yopilsa null qaytadi.
Future<ImageSource?> askImageSource(BuildContext context) {
  final p = context.p;
  return showModalBottomSheet<ImageSource>(
    context: context,
    useRootNavigator: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (c) {
      Widget option(IconData icon, String title, String sub, ImageSource src) =>
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: p.accentSoft,
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: p.accent)),
            title: Text(tr(title),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle:
                Text(tr(sub), style: TextStyle(color: p.muted, fontSize: 13)),
            onTap: () => Navigator.pop(c, src),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(tr("Rasm qo'shish"),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800))),
                option(Icons.photo_camera_outlined, 'Kamera',
                    'Hozir suratga olish', ImageSource.camera),
                option(Icons.photo_library_outlined, 'Galereya',
                    'Telefondagi rasmlardan tanlash', ImageSource.gallery),
              ]),
        ),
      );
    },
  );
}

/// PageView'dagi bo'lim ko'rinmay qolganda ham xotirada qoladi: qayta ochilganda yangidan yuklanmaydi
class KeepAlivePage extends StatefulWidget {
  final Widget child;
  const KeepAlivePage({super.key, required this.child});
  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
