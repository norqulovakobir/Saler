import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api.dart';
import '../../l10n.dart';
import '../../realtime.dart';
import '../../state.dart';
import '../../theme.dart';
import 'auth_ui.dart';

/// Xaridor tizimga kirishi: ism, familiya, telefon, Telegram va email yoziladi,
/// emailga 6 xonali kod keladi va kod tasdiqlangandan keyin hisob tasdiqlanadi.
/// Parol kerak emas — xaridor uchun email kod yetarli.

class BuyerForm {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final phone = TextEditingController();
  final telegram = TextEditingController();
  final email = TextEditingController();

  BuyerForm() {
    // Ilgari kiritilgan ma'lumotlar bo'lsa, oldindan to'ldiriladi
    final api = Api.instance;
    firstName.text = api.firstName;
    lastName.text = api.lastName;
    if (api.firstName.isEmpty && api.userName != 'Xaridor') firstName.text = api.userName;
    phone.text = (api.phone ?? '').replaceFirst('+998', '');
    telegram.text = api.telegram ?? '';
    email.text = api.email ?? '';
  }

  void dispose() {
    for (final c in [firstName, lastName, phone, telegram, email]) {
      c.dispose();
    }
  }

  String get digits => phone.text.replaceAll(RegExp(r'\D'), '');

  /// Xato bo'lsa matn qaytaradi, hammasi to'g'ri bo'lsa null
  String? validate() {
    if (firstName.text.trim().length < 2) return tr('Ismingizni kiriting');
    if (lastName.text.trim().length < 2) return tr('Familiyangizni kiriting');
    if (digits.length != 9) return tr("Telefon raqamini to'liq kiriting");
    if (telegram.text.trim().isEmpty) return tr('Telegram username yoki raqamingizni kiriting');
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email.text.trim())) return tr("Email manzilini to'g'ri kiriting");
    return null;
  }

  Map<String, dynamic> body({String? code}) => {
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'phone': '+998$digits',
        'telegram': telegram.text.trim(),
        'email': email.text.trim(),
        if (code != null) 'code': code,
      };
}

/// 1-qadam: ma'lumotlarni yuborib emailga kod oladi. Test rejimidagi kodni qaytaradi
Future<String?> buyerSendCode(BuyerForm f) async {
  final r = await Api.instance.post('/api/auth/buyer', f.body());
  return r['devCode']?.toString();
}

/// 2-qadam: kodni tasdiqlaydi va hisobni ilovaga bog'laydi
Future<void> buyerVerify(BuyerForm f, String code) async {
  final r = await Api.instance.post('/api/auth/buyer', f.body(code: code));
  await Api.instance.saveUser(r['user']);
  await AppState.instance.reloadMe();
  AppState.instance.startLive();
  Realtime.instance.restart();
}

/// Xaridor maydonlari (buyurtma oynasida ham, kirish oynasida ham ishlatiladi)
class BuyerFields extends StatelessWidget {
  final BuyerForm form;
  final VoidCallback? onSubmit;
  const BuyerFields({super.key, required this.form, this.onSubmit});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: AuthField(controller: form.firstName, label: tr('Ism'), icon: Icons.person_outline_rounded, caps: TextCapitalization.words)),
          const SizedBox(width: 10),
          Expanded(child: AuthField(controller: form.lastName, label: tr('Familiya'), caps: TextCapitalization.words)),
        ]),
        AuthField(
          controller: form.phone,
          label: tr('Telefon raqami'),
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          prefixText: '+998 ',
          hint: '90 123 45 67',
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
        ),
        AuthField(controller: form.telegram, label: 'Telegram', icon: Icons.send_outlined, hint: '@username'),
        AuthField(
          controller: form.email,
          label: 'Email',
          icon: Icons.alternate_email_rounded,
          keyboard: TextInputType.emailAddress,
          hint: 'siz@email.com',
          action: TextInputAction.done,
          onSubmit: onSubmit,
        ),
      ]);
}

/// Buyurtma berish yoki Reels uchun tizimga kirish oynasi
class BuyerAuthSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  const BuyerAuthSheet({super.key, required this.title, required this.subtitle, required this.buttonLabel});
  @override
  State<BuyerAuthSheet> createState() => _BuyerAuthSheetState();
}

class _BuyerAuthSheetState extends State<BuyerAuthSheet> {
  final form = BuyerForm();
  bool busy = false;
  bool codeStep = false;
  String? devCode;
  String? error;

  @override
  void dispose() {
    form.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final problem = form.validate();
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(codeStep ? tr('Emailni tasdiqlang') : widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 4),
          Text(codeStep ? tr("Emailingizga yuborilgan 6 xonali kodni kiriting") : widget.subtitle, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          if (codeStep)
            CodeStep(
              email: form.email.text.trim(),
              devCode: devCode,
              buttonLabel: widget.buttonLabel,
              onResend: () => buyerSendCode(form),
              onSubmit: (code) async {
                final nav = Navigator.of(context);
                await buyerVerify(form, code);
                nav.pop(true);
              },
            )
          else ...[
            BuyerFields(form: form, onSubmit: send),
            AuthErrorText(error),
            AuthButton(tr('Kodni olish'), busy: busy, onTap: send, icon: Icons.arrow_forward_rounded),
            const SizedBox(height: 8),
            Center(
              child: Text(tr("Ma'lumotlaringiz faqat buyurtmani rasmiylashtirish uchun ishlatiladi"),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Amal xaridor hisobini talab qiladi: kirgan bo'lsa darhol true, aks holda oyna ochiladi
Future<bool> ensureBuyer(BuildContext context, {String? title, String? subtitle, String? buttonLabel}) async {
  if (Api.instance.registered) return true;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => BuyerAuthSheet(
      title: title ?? tr('Tizimga kirish'),
      subtitle: subtitle ?? tr("Ism, telefon va emailingizni kiriting — emailga 6 xonali kod yuboramiz"),
      buttonLabel: buttonLabel ?? tr('Tasdiqlash'),
    ),
  );
  return ok == true;
}
