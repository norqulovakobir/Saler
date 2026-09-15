import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';

/// Xaridor hisobi. Ilovadan foydalanish va xarid qilish uchun ro'yxatdan o'tish yoki kirish majburiy.
class AccountScreen extends StatefulWidget {
  final VoidCallback onDone;
  const AccountScreen({super.key, required this.onDone});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool register = true;
  bool busy = false;
  bool hide = true;
  String? error;
  final name = TextEditingController();
  final phone = TextEditingController();
  final pass = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    String? problem;
    if (register && name.text.trim().isEmpty) problem = tr('Ismingizni kiriting');
    if (problem == null && digits.length != 9) problem = tr("Telefon raqamini to'liq kiriting");
    if (problem == null && pass.text.length < 6) problem = tr('Parol kamida 6 belgi');
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
      final body = {'phone': '+998$digits', 'password': pass.text, if (register) 'name': name.text.trim()};
      final r = await Api.instance.post(register ? '/api/auth/register' : '/api/auth/login', body);
      await Api.instance.saveUser(r['user']);
      await AppState.instance.reloadMe();
      if (mounted) widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = tr("Serverga ulanib bo'lmadi. Internetni tekshiring"));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _switch(bool value) {
    if (busy) return;
    setState(() {
      register = value;
      error = null;
    });
  }

  Widget _tab(String label, bool value) {
    final sel = register == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switch(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: sel ? context.p.accent : Colors.transparent, borderRadius: BorderRadius.circular(11)),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: sel ? const Color(0xFF14161A) : Colors.white.withValues(alpha: .75))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(children: [
          Positioned(top: -150, left: -110, child: _Glow(p.accent.withValues(alpha: .16), 420)),
          Positioned(bottom: -170, right: -130, child: _Glow(const Color(0xFFFF8A00).withValues(alpha: .12), 420)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: p.accent.withValues(alpha: .35), blurRadius: 40, offset: const Offset(0, 14))]),
                        child: Image.asset('assets/img/logo_circle.png', fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(register ? tr('Hisob yarating') : tr('Hisobingizga kiring'),
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.5)),
                    const SizedBox(height: 6),
                    Text(tr("Xarid qilish, do'konlarga obuna bo'lish va AI sotuvchi bilan gaplashish uchun"),
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 14, height: 1.4)),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [_tab(tr("Ro'yxatdan o'tish"), true), _tab(tr('Kirish'), false)]),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24)),
                      child: AutofillGroup(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (register) ...[
                            TextField(
                              controller: name,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(labelText: tr('Ismingiz'), prefixIcon: const Icon(Icons.person_outline_rounded)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: phone,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [AutofillHints.telephoneNumberNational],
                            textInputAction: TextInputAction.next,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                            decoration: InputDecoration(labelText: tr('Telefon raqami'), prefixIcon: const Icon(Icons.phone_outlined), prefixText: '+998 ', hintText: '90 123 45 67'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: pass,
                            obscureText: hide,
                            autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                            onSubmitted: (_) => submit(),
                            decoration: InputDecoration(
                              labelText: tr('Parol'),
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => hide = !hide)),
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
                                const SizedBox(width: 8),
                                Expanded(child: Text(error!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w600, fontSize: 13, height: 1.35))),
                              ]),
                            ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: busy ? null : submit,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            child: busy
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                                : Text(register ? tr("Ro'yxatdan o'tish") : tr('Kirish')),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: busy ? null : () => _switch(!register),
                      child: Text(register ? tr('Hisobingiz bormi? Kirish') : tr("Hisobingiz yo'qmi? Ro'yxatdan o'tish"), style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
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
