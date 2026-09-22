import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Ilovaning harakat tili: yuklash halqasi, ekran o'tishlari va
/// ro'yxatlarning ketma-ket chiqishi shu yerdan boshqariladi.
/// Hamma joyda bir xil tezlik va egri chiziq ishlatiladi — shunda ilova
/// yaxlit his beradi.

/// Standart tezliklar
const kFast = Duration(milliseconds: 180);
const kMedium = Duration(milliseconds: 320);
const kSlow = Duration(milliseconds: 520);

/// Brend yuklash animatsiyasi: sariq yoy aylanadi, ichkarida logo nafas oladi.
/// [showLogo] false bo'lsa faqat halqa ko'rinadi (kichik joylar uchun).
class RydexLoader extends StatefulWidget {
  final double size;
  final bool showLogo;
  final Color? color;
  const RydexLoader({super.key, this.size = 120, this.showLogo = true, this.color});

  @override
  State<RydexLoader> createState() => _RydexLoaderState();
}

class _RydexLoaderState extends State<RydexLoader> with TickerProviderStateMixin {
  late final spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  late final pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    spin.dispose();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? context.p.accent;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([spin, pulse]),
        builder: (_, __) {
          final breathe = Curves.easeInOut.transform(pulse.value);
          return CustomPaint(
            painter: _RingPainter(spin.value, accent, breathe),
            child: widget.showLogo
                ? Center(
                    child: Transform.scale(
                      scale: .94 + .06 * breathe,
                      child: Padding(
                        padding: EdgeInsets.all(widget.size * .17),
                        child: Image.asset('assets/img/logo_circle.png', fit: BoxFit.contain),
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  /// 0..1 — aylanish holati
  final double t;
  final Color accent;

  /// 0..1 — nafas olish (yorug'lik kuchi)
  final double breathe;
  const _RingPainter(this.t, this.accent, this.breathe);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    final rect = Rect.fromCircle(center: c, radius: r);
    final a = t * 2 * math.pi;

    // Iz: butun halqa zaif ko'rinib turadi
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent.withValues(alpha: .14),
    );

    // Asosiy yoy: sweep gradient bilan boshi shaffof, oxiri to'q
    const sweep = math.pi * 1.15;
    canvas.drawArc(
      rect,
      a,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.5
        ..shader = SweepGradient(
          startAngle: a,
          endAngle: a + sweep,
          colors: [accent.withValues(alpha: 0), accent],
          transform: GradientRotation(a),
        ).createShader(rect),
    );

    // Qarama-qarshi tomondagi qisqa yoy — chuqurlik beradi
    canvas.drawArc(
      rect.deflate(9),
      -a * 1.6,
      math.pi * .5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.5
        ..color = accent.withValues(alpha: .35 + .25 * breathe),
    );

    // Yoy uchidagi nuqta va uning nuri
    final head = Offset(c.dx + r * math.cos(a + sweep), c.dy + r * math.sin(a + sweep));
    canvas.drawCircle(head, 7 + 2 * breathe, Paint()..color = accent.withValues(alpha: .18));
    canvas.drawCircle(head, 3.4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.breathe != breathe || old.accent != accent;
}

/// Matn ustidan o'tuvchi yorug'lik (yuklanayotganini bildiradi)
class ShimmerText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const ShimmerText(this.text, {super.key, required this.style});

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style.color ?? Colors.white;
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(-1 - 2 * (1 - c.value), 0),
          end: Alignment(1 - 2 * (1 - c.value), 0),
          colors: [base, context.p.accent, base],
          stops: const [.25, .5, .75],
        ).createShader(r),
        child: Text(widget.text, style: widget.style),
      ),
    );
  }
}

/// Element ekranga chiqqanda pastdan suzib, ochilib keladi.
/// [delay] bilan ro'yxat elementlarini ketma-ket chiqarish mumkin.
class AppearIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;
  const AppearIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 18});

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: kSlow);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (_, child) {
          final v = Curves.easeOutCubic.transform(c.value);
          return Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, widget.offset * (1 - v)), child: child),
          );
        },
        child: widget.child,
      );
}

/// Ekranlar o'rtasidagi o'tish: eskisi orqaga chekinib xiralashadi,
/// yangisi pastdan bir oz ko'tarilib ochiladi (fade-through).
class FadeThroughTransitions extends PageTransitionsBuilder {
  const FadeThroughTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T>? route, BuildContext? context, Animation<double> animation,
      Animation<double> secondary, Widget child) {
    final enter = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final exit = CurvedAnimation(parent: secondary, curve: Curves.easeInOut);
    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .045), end: Offset.zero).animate(enter),
        child: ScaleTransition(
          // Ketayotgan ekran sal kichrayadi — qatlam hissi paydo bo'ladi
          scale: Tween(begin: 1.0, end: .96).animate(exit),
          child: FadeTransition(opacity: Tween(begin: 1.0, end: .0).animate(exit), child: child),
        ),
      ),
    );
  }
}
