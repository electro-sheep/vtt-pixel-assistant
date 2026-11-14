import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Small retro UI kit for the terrain-floor HUD: buttons that react to hover and
/// press, a fix toast, score bars, a live audio meter and a pop-in transition.

/// Chunky pixel button. Lifts and brightens on hover, sinks into its hard shadow
/// when pressed, so every click has visible feedback.
class PixelButton extends StatefulWidget {
  final String label;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const PixelButton({
    super.key,
    required this.label,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    const Color base = Color(0xFF1D2432);
    final Color c = widget.color;
    final Color fill = _down
        ? Color.lerp(base, c, 0.42)!
        : (_hover || widget.active)
            ? Color.lerp(base, c, widget.active ? 0.26 : 0.18)!
            : base;
    final double sink = _down ? 2.0 : 0.0;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(sink, sink, 0),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(
                color: _hover ? Color.lerp(c, Colors.white, 0.35)! : c,
                width: 1.5,
              ),
              boxShadow: [
                if (!_down)
                  BoxShadow(
                    color: _hover ? c.withAlpha(120) : const Color(0x99000000),
                    offset: const Offset(2, 2),
                    blurRadius: 0,
                  ),
              ],
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: _hover ? Color.lerp(c, Colors.white, 0.55) : c,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades + scales its child in once when it first appears (menus, drawers).
class PopIn extends StatelessWidget {
  final Widget child;
  final Alignment alignment;
  final Duration duration;

  const PopIn({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.duration = const Duration(milliseconds: 170),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.94 + 0.06 * t,
            alignment: alignment,
            child: child,
          ),
        );
      },
    );
  }
}

/// "✔ teh → the" chip that pops up over the creature, drifts upward and fades,
/// so each automatic correction is seen without having to look at the HUD.
class FixToast extends StatelessWidget {
  final String original;
  final String replacement;
  final int extraCount;
  final Color color;
  final VoidCallback onDone;

  const FixToast({
    super.key,
    required this.original,
    required this.replacement,
    required this.color,
    required this.onDone,
    this.extraCount = 0,
  });

  static String _clip(String s) =>
      s.length <= 20 ? s : '${s.substring(0, 19)}…';

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 2600),
      onEnd: onDone,
      builder: (BuildContext context, double t, Widget? child) {
        final double pop = Curves.easeOutBack.transform((t / 0.14).clamp(0.0, 1.0));
        final double fade = t > 0.72 ? (1.0 - t) / 0.28 : 1.0;
        final double rise =
            Curves.easeOutCubic.transform((t * 1.6).clamp(0.0, 1.0)) * 22 + t * 12;
        return Transform.translate(
          offset: Offset(0, -rise),
          child: Opacity(
            opacity: (math.min(1.0, t / 0.08) * fade).clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.7 + 0.3 * pop, child: child),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xF2101822),
          border: Border.all(color: color, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0xAA000000), offset: Offset(2, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✔ ', style: TextStyle(color: color, fontSize: 10)),
            Text(
              _clip(original),
              style: const TextStyle(
                color: Color(0xFF90A4AE),
                fontSize: 10.5,
                decoration: TextDecoration.lineThrough,
                decorationColor: Color(0xFFFF8A80),
              ),
            ),
            const Text(
              ' → ',
              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 10.5),
            ),
            Text(
              _clip(replacement),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (extraCount > 0)
              Text(
                '  +$extraCount',
                style: const TextStyle(color: Color(0xFFFFD740), fontSize: 9.5),
              ),
          ],
        ),
      ),
    );
  }
}

/// Four tiny bars (Correctness / Clarity / Engagement / Delivery) that glide to
/// their new value instead of jumping.
class PillarBars extends StatelessWidget {
  final Map<String, int> scores;

  const PillarBars({super.key, required this.scores});

  static const List<List<String>> _pillars = [
    ['correctness', 'C', 'Correctness: spelling, homophones, grammar'],
    ['clarity', 'L', 'Clarity: concise, easy to follow'],
    ['engagement', 'E', 'Engagement: vivid word choice'],
    ['delivery', 'D', 'Delivery: confident tone'],
  ];

  static Color colorFor(int score) {
    if (score >= 90) return const Color(0xFF69F0AE);
    if (score >= 78) return const Color(0xFFFFD740);
    return const Color(0xFFFF8A80);
  }

  @override
  Widget build(BuildContext context) {
    const double barW = 22.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in _pillars)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Tooltip(
              message: '${p[2]} — ${scores[p[0]] ?? 100}/100',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p[1],
                    style: const TextStyle(
                      color: Color(0xFFCE93D8),
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: barW,
                    height: 6,
                    alignment: Alignment.centerLeft,
                    color: const Color(0xFF2A2140),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      width: barW * ((scores[p[0]] ?? 100).clamp(0, 100) / 100.0),
                      height: 6,
                      color: colorFor(scores[p[0]] ?? 100),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Number that counts up/down to its new value.
class CountingText extends StatelessWidget {
  final int value;
  final String Function(int) format;
  final TextStyle style;

  const CountingText({
    super.key,
    required this.value,
    required this.format,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, Widget? _) =>
          Text(
        format(v.round()),
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

/// Mic level as bouncing pixel bars. Idle = a flat dim line; speaking = a wave
/// whose height follows the real audio level.
class PixelAudioMeter extends StatelessWidget {
  final double level;
  final bool active;
  final int tick;

  const PixelAudioMeter({
    super.key,
    required this.level,
    required this.active,
    required this.tick,
  });

  @override
  Widget build(BuildContext context) {
    const int bars = 10;
    const double maxH = 12.0;
    return SizedBox(
      height: maxH,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(bars, (int i) {
          final double wave = 0.55 + 0.45 * math.sin(tick * 0.9 + i * 1.7);
          final double idle = active ? 0.10 + 0.06 * math.sin(tick * 0.35 + i) : 0.0;
          final double v = (level * wave * 1.25 + idle).clamp(0.0, 1.0);
          final double h = 2.0 + (maxH - 2.0) * v;
          final Color col = v > 0.72
              ? const Color(0xFFFF5252)
              : v > 0.42
                  ? const Color(0xFFFFD740)
                  : (v > 0.04 ? const Color(0xFF00E676) : const Color(0xFF37474F));
          return AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 4,
            height: h,
            margin: const EdgeInsets.only(right: 2),
            color: col,
          );
        }),
      ),
    );
  }
}
