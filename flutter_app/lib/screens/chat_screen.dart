import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'assistant_screen.dart';
import 'shops_screen.dart';

class _Msg {
  final String role;
  final String text;
  final Product? product;
  _Msg(this.role, this.text, {this.product});
}

/// AI sotuvchi bilan chat
class ChatScreen extends StatefulWidget {
  final Shop? shop;
  final String? prefill;
  const ChatScreen({super.key, this.shop, this.prefill});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final msgs = <_Msg>[];
  final inp = TextEditingController();
  final scroll = ScrollController();
  bool busy = false;
  Shop? shop;

  @override
  void initState() {
    super.initState();
    shop = widget.shop ?? AppState.instance.chatShop;
    if (shop != null) _loadHistory();
    if (widget.shop == null) AppState.instance.addListener(_onStateChange);
  }

  void _onStateChange() {
    final s = AppState.instance.chatShop;
    if (s == null && shop != null) {
      setState(() => shop = null);
    } else if (s != null && s.id != shop?.id) {
      shop = s;
      _loadHistory();
    }
  }

  @override
  void dispose() {
    if (widget.shop == null) AppState.instance.removeListener(_onStateChange);
    super.dispose();
  }

  void _applyHistory(dynamic r) {
    final h = (r['history'] as List);
    msgs.clear();
    if (h.isEmpty) {
      msgs.add(_Msg('assistant', tr('Assalomu alaykum! Xush kelibsiz, sizga nima kerak edi?')));
    } else {
      for (final m in h) {
        msgs.add(_Msg(m['role'], m['content']));
      }
    }
    if (mounted) setState(() {});
    _scrollDown();
  }

  Future<void> clearHistory() async {
    if (!await confirmDialog(context, tr('Suhbat tarixini tozalaysizmi?'), text: tr("Yozishmalar o'chiriladi, sotuvchi suhbatni boshidan boshlaydi."), ok: tr('Tozalash'), danger: true)) return;
    try {
      await Api.instance.delete('/api/chat/history?shopId=${shop!.id}');
      _applyHistory({'history': []});
      if (mounted) showToast(context, tr('Suhbat tozalandi'));
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _loadHistory() async {
    final path = '/api/chat/history?shopId=${shop!.id}';
    final cached = Api.instance.cached(path);
    if (cached != null) _applyHistory(cached);
    try {
      final r = await Api.instance.get(path);
      final h = (r['history'] as List);
      msgs.clear();
      if (h.isEmpty) {
        msgs.add(_Msg('assistant', tr('Assalomu alaykum! Xush kelibsiz, sizga nima kerak edi?')));
      } else {
        for (final m in h) {
          msgs.add(_Msg(m['role'], m['content']));
        }
      }
      if (mounted) setState(() {});
      _scrollDown();
      if (widget.prefill != null) send(widget.prefill!);
    } catch (_) {}
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> send(String text, {String? mode}) async {
    text = text.trim();
    if (text.isEmpty || busy || shop == null) return;
    setState(() {
      busy = true;
      inp.clear();
      if (mode != 'catalog') msgs.add(_Msg('user', text));
    });
    _scrollDown();
    try {
      final r = await Api.instance.post('/api/chat', {'shopId': shop!.id, 'message': text, 'lang': L10n.code, if (mode != null) 'mode': mode});
      if ((r['text'] ?? '').toString().isNotEmpty) msgs.add(_Msg('assistant', r['text']));
      for (final p in (r['products'] as List? ?? const [])) {
        msgs.add(_Msg('product', '', product: Product.fromJson(p)));
      }
      if (r['order'] != null && mounted) showToast(context, 'Buyurtma qabul qilindi');
    } catch (e) {
      msgs.add(_Msg('assistant', tr("Hozir javob bera olmayapman, birozdan so'ng urinib ko'ring.")));
    }
    if (mounted) setState(() => busy = false);
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    final s = shop;
    final p = context.p;
    // Do'kon tanlanmagan — umumiy AI yordamchi do'kon tavsiya qiladi
    if (s == null) return AssistantScreen(inTab: widget.shop == null);
    return Scaffold(
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 16, 12),
          decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.border))),
          child: Row(children: [
            if (Navigator.of(context).canPop()) ...[IconBtn(Icons.arrow_back_ios_new_rounded, bg: p.bg, onTap: () => Navigator.of(context).maybePop()), const SizedBox(width: 10)],
            ShopAvatar(s, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.sellerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: p.success, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${s.name} ${tr('sotuvchisi · onlayn')}', style: TextStyle(fontSize: 12, color: p.success, fontWeight: FontWeight.w700))
                ]),
              ]),
            ),
            // Do'kon sotuvchisidan chiqib, ilova yordamchisi Sofiaga o'tish
            IconBtn(Icons.auto_awesome_rounded, bg: p.accentSoft, color: p.accent, onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AssistantScreen(inTab: false)))),
            const SizedBox(width: 8),
            IconBtn(Icons.phone_outlined, bg: p.successSoft, color: p.success, onTap: () => launchUrl(Uri.parse('tel:${s.phone}'))),
            const SizedBox(width: 8),
            IconBtn(Icons.delete_outline_rounded, bg: p.bg, onTap: clearHistory),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: msgs.length + (busy ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == msgs.length) return const TypingBubble();
              final m = msgs[i];
              if (m.role == 'product') return _ProductBubble(m.product!, s);
              return ChatBubble(m.text, me: m.role == 'user');
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            QuickChip(tr('Eng arzoni?'), () => send(tr('Eng arzoni qaysi?'))),
            QuickChip(tr('Yetkazib berish bormi?'), () => send(tr('Yetkazib berish bormi?'))),
            QuickChip(tr("Mahsulotlarni ko'rsating"), () => send(tr("Sizda qanday mahsulotlar bor? Ko'rsating."), mode: 'catalog')),
          ]),
        ),
        ChatInput(controller: inp, hint: tr('Xabar yozing...'), onSend: () => send(inp.text), bottomExtra: 0),
      ]),
    );
  }
}

/// Tez javob chipi (chat va yordamchi uchun)
class QuickChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const QuickChip(this.text, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: context.p.card,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), boxShadow: softShadow(context, y: 2, blur: 8), border: context.isDark ? Border.all(color: context.p.border) : null),
              child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
}

/// "Yozmoqda..." pufakchasi
class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: context.p.card,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20), bottomLeft: Radius.circular(6)),
              boxShadow: softShadow(context, y: 4, blur: 14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final a in [.9, .5, .25])
              Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 2.5), decoration: BoxDecoration(color: context.p.muted.withValues(alpha: a), shape: BoxShape.circle))
          ]),
        ),
      );
}

class _ProductBubble extends StatelessWidget {
  final Product p;
  final Shop shop;
  const _ProductBubble(this.p, this.shop);
  @override
  Widget build(BuildContext context) {
    final pal = context.p;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 300,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: pal.border) : null),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          InkWell(
            onTap: () => openProduct(context, p, shop),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                ProductImage(p, size: 84),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  if (p.description.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.muted, fontWeight: FontWeight.w500))),
                  const SizedBox(height: 4),
                  PriceText(p.price, size: 16),
                ])),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40), padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      icon: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(tr('Sotib olish')),
                      onPressed: () => openOrderForm(context, [CartItem(p, 1)]))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          padding: EdgeInsets.zero,
                          backgroundColor: pal.bg,
                          side: BorderSide.none,
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                      label: Text(tr('Savatcha')),
                      onPressed: () {
                        AppState.instance.addToCart(p, force: true);
                        showToast(context, tr("Savatchaga qo'shildi"));
                      })),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Matnli xabar pufakchasi: xaridorniki qora (o'ngda), suhbatdoshniki oq (chapda)
class ChatBubble extends StatelessWidget {
  final String text;
  final bool me;
  const ChatBubble(this.text, {super.key, required this.me});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .76),
        decoration: BoxDecoration(
          color: me ? p.dark : p.card,
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(me ? 20 : 6), bottomRight: Radius.circular(me ? 6 : 20)),
          boxShadow: me ? null : softShadow(context, y: 4, blur: 14),
          border: context.isDark && !me ? Border.all(color: p.border) : null,
        ),
        child: Text(text, style: TextStyle(color: me ? p.onDark : p.text, fontSize: 15, height: 1.45, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// Xabar kiritish paneli. [bottomExtra] — tab ichida pastki navigatsiya uchun joy
class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;
  final double bottomExtra;
  const ChatInput({super.key, required this.controller, required this.hint, required this.onSend, this.bottomExtra = 0});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      // Tab ichida: pastki suzuvchi navigatsiya uchun joy (navPad ichida tizim paneli ham bor); klaviatura ochiq bo'lsa joy kerak emas
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + (kb > 0 ? 0 : (bottomExtra > 0 ? bottomExtra : MediaQuery.of(context).padding.bottom))),
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.border))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
                hintText: hint,
                fillColor: p.bg,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13)),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: p.accent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onSend,
            borderRadius: BorderRadius.circular(16),
            child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: p.accent.withValues(alpha: .35), offset: const Offset(0, 8), blurRadius: 20)]),
                child: Icon(Icons.send_rounded, color: p.onAccent, size: 20)),
          ),
        ),
      ]),
    );
  }
}
