import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../l10n.dart';
import '../realtime.dart';
import '../state.dart';
import '../theme.dart';

/// Xaridor hisobini tasdiqlash oynasi.
/// Ilovani ko'rish uchun hisob shart emas. Buyurtma berish, Reels, obuna va layk oldidan shu oyna chiqadi:
/// ism, familiya, telefon, telegram, email → emailga 6 xonali kod → kod to'g'ri bo'lsa hisob tasdiqlanadi.
/// Tasdiqlansa true qaytaradi; so'rov shundan keyin o'zi qayta yuboriladi (qarang: Api.onNeedAuth).
Future<bool> showBuyerAuth(BuildContext context) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const BuyerAuthSheet(),
  );
  return r == true;
}

/// Foydalanuvchiga ko'rsatiladigan xato matni (VerifyCodeBox tutib oladi)
class AuthMessage implements Exception {
  final String text;
  AuthMessage(this.text);
  @override
  String toString() => text;
}

class BuyerAuthSheet extends StatefulWidget {
  const BuyerAuthSheet({super.key});
  @override
  State<BuyerAuthSheet> createState() => _BuyerAuthSheetState();
}

class _BuyerAuthSheetState extends State<BuyerAuthSheet> {
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  final api = Api.instance;
  late final first = TextEditingController(text: api.firstName);
  late final last = TextEditingController(text: api.lastName);
  late final phone = TextEditingController(text: (api.phone ?? '').replaceFirst('+998', ''));
  late final telegram = TextEditingController(text: api.telegram ?? '');
  late final email = TextEditingController(text: api.email ?? '');
  bool busy = false;
  String? error;
  String? errorField;
  Map<String, dynamic>? sent; // kod yuborilgach server javobi: email, resendIn, devCode

  @override
  void dispose() {
    for (final c in [first, last, phone, telegram, email]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _digits => phone.text.replaceAll(RegExp(r'\D'), '');
  Map<String, dynamic> get _body => {
        'firstName': first.text.trim(),
        'lastName': last.text.trim(),
        'phone': '+998$_digits',
        'telegram': telegram.text.trim(),
        'email': email.text.trim(),
      };

  String? _check() {
    String? bad(String field, String msg) {
      errorField = field;
      return msg;
    }
    if (first.text.trim().length < 2) return bad('firstName', tr('Ismingizni kiriting'));
    if (last.text.trim().length < 2) return bad('lastName', tr('Familiyangizni kiriting'));
    if (_digits.length != 9) return bad('phone', tr("Telefon raqamini to'liq kiriting"));
    if (telegram.text.trim().isEmpty) return bad('telegram', tr('Telegram username yoki raqamingizni kiriting'));
    if (!_emailRe.hasMatch(email.text.trim())) return bad('email', tr("Email manzilini to'g'ri kiriting"));
    return null;
  }

  /// 1-qadam: ma'lumotlar tekshiriladi va emailga kod yuboriladi
  Future<void> sendCode() async {
    FocusScope.of(context).unfocus();
    final problem = _check();
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      busy = true;
      error = null;
      errorField = null;
    });
    try {
      final r = await api.post('/api/auth/buyer', _body);
      if (mounted) setState(() => sent = Map<String, dynamic>.from(r as Map));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          errorField = e.field;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = tr("Serverga ulanib bo'lmadi. Internetni tekshiring"));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, dynamic>> _resend() async => Map<String, dynamic>.from(await api.post('/api/auth/buyer', _body) as Map);

  /// 2-qadam: kod bilan hisob tasdiqlanadi
  Future<void> _verify(String code) async {
    final r = await api.post('/api/auth/buyer', {..._body, 'code': code});
    await api.saveUser(r['user']);
    AppState.instance.startLive();
    Realtime.instance.restart();
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _field(TextEditingController c, String key, String label, IconData icon,
      {TextInputType? type,
      String? hint,
      String? prefix,
      List<TextInputFormatter>? fmt,
      TextCapitalization cap = TextCapitalization.none,
      Iterable<String>? autofill,
      TextInputAction action = TextInputAction.next}) {
    return TextField(
      controller: c,
      keyboardType: type,
      textInputAction: action,
      inputFormatters: fmt,
      textCapitalization: cap,
      autofillHints: autofill,
      autocorrect: false,
      enabled: !busy,
      onChanged: errorField == key
          ? (_) => setState(() {
                error = null;
                errorField = null;
              })
          : null,
      onSubmitted: action == TextInputAction.done ? (_) => sendCode() : null,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixText: prefix, prefixIcon: Icon(icon, size: 20), errorText: errorField == key ? error : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final s = sent;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: s != null
            ? VerifyCodeBox(
                email: s['email']?.toString() ?? email.text.trim(),
                resendIn: (s['resendIn'] as num?)?.toInt() ?? 60,
                devCode: s['devCode']?.toString(),
                onVerify: _verify,
                onResend: _resend,
                onBack: () => setState(() => sent = null),
              )
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                      width: 44, height: 44, decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.verified_user_outlined, color: p.accentText)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Hisobingizni tasdiqlang'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                      Text(tr("Bir marta: ma'lumotlaringiz va emailga keladigan 6 xonali kod"),
                          style: TextStyle(fontSize: 12.5, color: p.muted, fontWeight: FontWeight.w500, height: 1.3)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _field(first, 'firstName', tr('Ism'), Icons.person_outline_rounded, cap: TextCapitalization.words, autofill: const [AutofillHints.givenName])),
                      const SizedBox(width: 8),
                      Expanded(child: _field(last, 'lastName', tr('Familiya'), Icons.badge_outlined, cap: TextCapitalization.words, autofill: const [AutofillHints.familyName])),
                    ]),
                    const SizedBox(height: 10),
                    _field(phone, 'phone', tr('Telefon raqami'), Icons.phone_outlined,
                        type: TextInputType.phone,
                        prefix: '+998 ',
                        hint: '90 123 45 67',
                        fmt: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                        autofill: const [AutofillHints.telephoneNumberNational]),
                    const SizedBox(height: 10),
                    _field(telegram, 'telegram', 'Telegram', Icons.send_outlined, hint: '@username'),
                    const SizedBox(height: 10),
                    _field(email, 'email', 'Email', Icons.alternate_email_rounded,
                        type: TextInputType.emailAddress, hint: 'siz@gmail.com', autofill: const [AutofillHints.email], action: TextInputAction.done),
                  ]),
                ),
                if (error != null && errorField == null) ...[const SizedBox(height: 12), ErrorNote(error!)],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : sendCode,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Row(mainAxisSize: MainAxisSize.min, children: [Text(tr('Kod yuborish')), const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 18)]),
                ),
                const SizedBox(height: 10),
                Center(
                    child: Text(tr("Ma'lumotlar faqat buyurtma va sotuvchi bilan aloqa uchun ishlatiladi"),
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: p.muted))),
              ]),
      ),
    );
  }
}

/// Qizil xato yozuvi
class ErrorNote extends StatelessWidget {
  final String text;
  const ErrorNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: p.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: p.danger, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }
}

/// Emailga yuborilgan 6 xonali kodni kiritish: hisoblagich bilan qayta yuborish, test rejimidagi kod,
/// 6 raqam kiritilgach o'zi tekshiradi. Xaridor, sotuvchi, kuryer va parol tiklashda bir xil ishlatiladi.
class VerifyCodeBox extends StatefulWidget {
  final String email;
  final int resendIn;

  /// EmailJS sozlanmagan test rejimida server kodni javobda qaytaradi
  final String? devCode;
  final Future<void> Function(String code) onVerify;

  /// Yangi kod so'rash; server javobi (resendIn, devCode) qaytariladi
  final Future<Map<String, dynamic>> Function() onResend;
  final VoidCallback? onBack;

  /// Kod maydonidan oldingi qo'shimcha maydonlar (masalan, yangi parol)
  final List<Widget> extra;
  const VerifyCodeBox({super.key, required this.email, required this.onVerify, required this.onResend, this.resendIn = 60, this.devCode, this.onBack, this.extra = const []});
  @override
  State<VerifyCodeBox> createState() => _VerifyCodeBoxState();
}

class _VerifyCodeBoxState extends State<VerifyCodeBox> {
  final code = TextEditingController();
  late int left = widget.resendIn;
  late String? devCode = widget.devCode;
  Timer? _t;
  bool busy = false;
  String? error;
  String? info;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || left <= 0) {
        t.cancel();
        return;
      }
      setState(() => left--);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = code.text.replaceAll(RegExp(r'\D'), '');
    if (c.length != 6) {
      setState(() => error = tr('6 xonali kodni kiriting'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await widget.onVerify(c);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        if (e.data?['codeExpired'] == true) code.clear();
      });
    } on AuthMessage catch (e) {
      if (mounted) setState(() => error = e.text);
    } catch (_) {
      if (mounted) setState(() => error = tr("Serverga ulanib bo'lmadi. Internetni tekshiring"));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      final r = await widget.onResend();
      if (!mounted) return;
      setState(() {
        left = (r['resendIn'] as num?)?.toInt() ?? 60;
        devCode = r['devCode']?.toString();
        code.clear();
        info = tr('Yangi kod yuborildi');
      });
      _tick();
    } on ApiException catch (e) {
      if (!mounted) return;
      final wait = (e.data?['retryAfter'] as num?)?.toInt();
      setState(() {
        error = e.message;
        if (wait != null) left = wait;
      });
      _tick();
    } catch (_) {
      if (mounted) setState(() => error = tr("Serverga ulanib bo'lmadi. Internetni tekshiring"));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        if (widget.onBack != null)
          IconButton(onPressed: busy ? null : widget.onBack, icon: const Icon(Icons.arrow_back_rounded), padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        Expanded(child: Text(tr('Emailni tasdiqlang'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4))),
      ]),
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: tr('6 xonali kod ')),
          TextSpan(text: widget.email, style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
          TextSpan(text: tr(' manziliga yuborildi')),
        ]),
        style: TextStyle(fontSize: 13.5, color: p.muted, fontWeight: FontWeight.w500, height: 1.4),
      ),
      ...widget.extra,
      const SizedBox(height: 16),
      TextField(
        controller: code,
        autofocus: true,
        enabled: !busy,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 12),
        decoration: InputDecoration(
            counterText: '', hintText: '••••••', hintStyle: TextStyle(color: p.muted.withValues(alpha: .4), letterSpacing: 12), contentPadding: const EdgeInsets.symmetric(vertical: 16)),
        onChanged: (v) {
          if (error != null) setState(() => error = null);
          if (v.length == 6 && !busy) _submit();
        },
        onSubmitted: (_) => _submit(),
      ),
      if (devCode != null) ...[
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy
              ? null
              : () {
                  code.text = devCode!;
                  _submit();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFE8A317).withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.science_outlined, size: 18, color: Color(0xFFA86F00)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('${tr('Test rejimi (email xizmati sozlanmagan). Kod')}: $devCode',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFFA86F00), fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      ],
      if (error != null) ...[const SizedBox(height: 10), ErrorNote(error!)],
      if (info != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.check_circle_outline_rounded, size: 16, color: p.success),
          const SizedBox(width: 6),
          Text(info!, style: TextStyle(fontSize: 13, color: p.success, fontWeight: FontWeight.w700)),
        ]),
      ],
      const SizedBox(height: 14),
      FilledButton(
        onPressed: busy ? null : _submit,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(tr('Tasdiqlash')),
      ),
      const SizedBox(height: 6),
      Center(
        child: left > 0
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('${tr('Qayta yuborish')}: $left s', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)))
            : TextButton(onPressed: busy ? null : _resend, child: Text(tr('Kodni qayta yuborish'), style: TextStyle(color: p.accentText, fontWeight: FontWeight.w800))),
      ),
      Center(child: Text(tr('Kod 10 daqiqa amal qiladi. Kelmasa Spam papkasini tekshiring'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: p.muted))),
    ]);
  }
}
