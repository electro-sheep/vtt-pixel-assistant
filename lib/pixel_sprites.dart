import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Next-Level Active Pixel-Art Sprite, Particle & Terrain Floor Engine (56x40 Creature Grid + 110x10 Terrain Grid).
///
/// 3-Tier Creature Progression:
/// - Tier 1 ('ptero' / 'stego')   : Sky Pterodactyl — Lightweight Speed (small.en, ~0.5 GB VRAM)
/// - Tier 2 ('cultist' / 'monster'): Hooded Cultist Scribe — Humanoid Grammarly Mentor (medium.en, ~1.5 GB VRAM)
/// - Tier 3 ('trex')              : Apex Green T-Rex — Heavyweight Powerhouse (large-v3-turbo, ~2.0 GB VRAM)
///
/// Supports 8 active animation states:
/// - 'idle'    : Breathing, wing/robe/tail sway, live cursor eye-tracking & 3-stage blink
/// - 'walk'    : 12-frame articulated stride + footstep dust puffs along the terrain floor
/// - 'curious' : Wind updraft wing stretch (Ptero), grimoire page turn (Cultist), ground sniff (T-Rex)
/// - 'sleep'   : Roosted/meditating rest posture, closed eyelids, slow breathing & floating pixel Zs
/// - 'listen'  : Voice-reactive beak/quill/jaw movement, glowing crests/runes & sonar wave rings
/// - 'typing'  : Floating holographic pixel keyboard / levitating quill scroll with active key-tapping
/// - 'fixing'  : Grammarly-magic starburst particle explosion & celebratory hop
/// - 'roar'    : Apex T-Rex roar shockwave / Pterodactyl sonic gale / Cultist arcane rune invocation

class PixelBuffer {
  final int width;
  final int height;
  final List<Color?> pixels;

  PixelBuffer(this.width, this.height)
      : pixels = List<Color?>.filled(width * height, null);

  void setPx(int x, int y, Color? c) {
    if (x >= 0 && x < width && y >= 0 && y < height) {
      pixels[y * width + x] = c;
    }
  }

  Color? getPx(int x, int y) {
    if (x >= 0 && x < width && y >= 0 && y < height) {
      return pixels[y * width + x];
    }
    return null;
  }

  void fillRect(int x, int y, int w, int h, Color c) {
    for (int py = y; py < y + h; py++) {
      for (int px = x; px < x + w; px++) {
        setPx(px, py, c);
      }
    }
  }

  void drawLine(int x0, int y0, int x1, int y1, Color c) {
    int dx = (x1 - x0).abs();
    int sx = x0 < x1 ? 1 : -1;
    int dy = -(y1 - y0).abs();
    int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    int cx = x0;
    int cy = y0;
    while (true) {
      setPx(cx, cy, c);
      if (cx == x1 && cy == y1) break;
      int e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        cx += sx;
      }
      if (e2 <= dx) {
        err += dx;
        cy += sy;
      }
    }
  }

  void drawOvalFilled(int cx, int cy, int rx, int ry, Color c) {
    for (int py = cy - ry; py <= cy + ry; py++) {
      for (int px = cx - rx; px <= cx + rx; px++) {
        final double dx = (px - cx) / (rx + 0.25);
        final double dy = (py - cy) / (ry + 0.25);
        if (dx * dx + dy * dy <= 1.0) {
          setPx(px, py, c);
        }
      }
    }
  }

  /// Adds a crisp 1-pixel retro dark outline around all sprite pixels
  void applyPixelOutline(Color outlineColor) {
    final List<Color?> copy = List<Color?>.from(pixels);
    const List<List<int>> dirs = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (copy[y * width + x] != null) continue;
        for (final d in dirs) {
          final int nx = x + d[0];
          final int ny = y + d[1];
          if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
            if (copy[ny * width + nx] != null) {
              pixels[y * width + x] = outlineColor;
              break;
            }
          }
        }
      }
    }
  }
}

class HighResPixelGenerator {
  static const int kGridW = 56;
  static const int kGridH = 40;
  static const int kFloorW = 110;
  static const int kFloorH = 10;

  static PixelBuffer buildFrame({
    required String creature,
    required String animState,
    required int tick,
    required double audioLevel,
    double lookDx = 0.5,
    double lookDy = 0.0,
  }) {
    switch (creature) {
      case 'trex':
        return _buildGreenTrex(animState, tick, audioLevel, lookDx, lookDy);
      case 'cultist':
      case 'monster':
        return _buildCultist(animState, tick, audioLevel, lookDx, lookDy);
      case 'ptero':
      case 'stego':
      default:
        return _buildPterodactyl(animState, tick, audioLevel, lookDx, lookDy);
    }
  }

  // =========================================================================
  // 1. TIER 3: GREEN JURASSIC T-REX (56x40 Heavyweight Powerhouse)
  // =========================================================================
  static PixelBuffer _buildGreenTrex(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy,
  ) {
    final buf = PixelBuffer(kGridW, kGridH);

    const Color outline = Color(0xFF0A190C);
    const Color darkGreen = Color(0xFF1B5E20);
    const Color midGreen = Color(0xFF2E7D32);
    const Color brightGreen = Color(0xFF43A047);
    const Color limeScale = Color(0xFF81C784);
    const Color bellyCream = Color(0xFFDCEDC8);
    const Color bellyShadow = Color(0xFFAED581);
    const Color eyeGold = Color(0xFFFFD54F);
    const Color pupilBlack = Color(0xFF111111);
    const Color toothWhite = Color(0xFFFFFFFF);
    const Color tongueRed = Color(0xFFE53935);

    final bool isWalk = animState == 'walk';
    final bool isSleep = animState == 'sleep';
    final bool isCurious = animState == 'curious';
    final bool isTyping = animState == 'typing';
    final bool isListen =
        animState == 'listen' || isTyping || animState == 'target_wait';
    final bool isFixing = animState == 'fixing' || animState == 'happy';
    final bool isRoar = animState == 'roar';

    final int bodyBob = isSleep
        ? 4
        : (isWalk
            ? ((tick % 3 == 0) ? -1 : 0)
            : (isFixing
                ? ((tick % 4 < 2) ? -2 : 0)
                : ((tick % 10 < 5) ? 0 : 1)));

    int jawOpen = 0;
    if (isRoar) {
      jawOpen = 5;
    } else if (isListen) {
      jawOpen = (1 + (audioLevel * 4.5).round()).clamp(1, 4);
      if (isTyping && tick % 2 == 0 && jawOpen < 2) jawOpen = 2;
    } else if (isFixing) {
      jawOpen = (tick % 4 < 2) ? 3 : 1;
    }

    // 1. Articulated Muscular Tail with 2-Harmonic Organic Wave (x=2..20)
    final double tailPhase = tick * 0.42;
    for (int tx = 2; tx <= 20; tx++) {
      final double progress = (20 - tx) / 18.0;
      final int sway = isSleep
          ? 2
          : (math.sin(tailPhase + progress * 2.6) * (isWalk ? 2.4 : 1.4) +
                  math.cos(tailPhase * 0.5 + progress * 4.0) * 0.6)
              .round();
      final int thick = (1 + (1.0 - progress) * 4.6).round();
      final int cy = 21 + bodyBob + sway - (progress * 2).round();
      for (int dy = -thick; dy <= thick; dy++) {
        Color col = midGreen;
        if (dy == -thick) col = brightGreen;
        if (dy >= thick - 1) col = bellyShadow;
        if (dy == -thick && tx % 3 == 0) col = limeScale;
        if (dy == 0 && (tx + cy) % 4 == 0) col = darkGreen;
        buf.setPx(tx, cy + dy, col);
      }
    }

    // 2. Torso, Dithered Scales & Breathing Ribcage (x=18..34, y=14..27)
    final int breathExpand = (tick % 14 < 7) ? 1 : 0;
    buf.drawOvalFilled(26, 21 + bodyBob, 9, 6 + breathExpand, midGreen);
    buf.drawOvalFilled(25, 19 + bodyBob, 8, 4, brightGreen);
    buf.drawOvalFilled(28, 24 + bodyBob, 6, 3, bellyCream);
    for (int bx = 22; bx <= 32; bx += 2) {
      buf.setPx(bx, 25 + bodyBob, bellyShadow);
      if (bx % 4 == 0) buf.setPx(bx + 1, 23 + bodyBob, bellyShadow);
    }
    // Dorsal crest spines & dappled pixel flank scales
    for (int sx = 18; sx <= 31; sx += 2) {
      buf.setPx(sx, 14 + bodyBob, limeScale);
      buf.setPx(sx, 15 + bodyBob, limeScale);
      buf.setPx(sx + 1, 16 + bodyBob, brightGreen);
      if (sx % 4 == 0) {
        buf.setPx(sx + 1, 19 + bodyBob, limeScale);
        buf.setPx(sx, 21 + bodyBob, darkGreen);
      }
    }
    buf.drawOvalFilled(22, 21 + bodyBob, 4, 4, darkGreen);
    buf.drawOvalFilled(23, 20 + bodyBob, 3, 3, midGreen);

    // 3. Hind Legs (12-frame smooth dinosaur walk stride with knee/ankle flex)
    final int legCycle = tick % 12;
    int leftLegX = 22;
    int leftLegY = 27;
    int rightLegX = 28;
    int rightLegY = 27;

    if (isWalk) {
      const List<int> dxPattern = [-3, -2, -1, 0, 1, 2, 3, 2, 1, 0, -1, -2];
      const List<int> dyPattern = [0, -1, -2, -2, -1, 0, 0, 0, 0, 0, 0, -1];
      leftLegX += dxPattern[legCycle];
      leftLegY += dyPattern[legCycle];
      rightLegX += dxPattern[(legCycle + 6) % 12];
      rightLegY += dyPattern[(legCycle + 6) % 12];
    }

    if (!isSleep) {
      // Far leg
      buf.fillRect(rightLegX, rightLegY + bodyBob, 4, 5, darkGreen);
      buf.fillRect(rightLegX + 1, rightLegY + 5 + bodyBob, 3, 3, darkGreen);
      buf.fillRect(rightLegX + 1, rightLegY + 7 + bodyBob, 5, 2, darkGreen);
      buf.setPx(rightLegX + 6, rightLegY + 8 + bodyBob, toothWhite);

      // Near leg with muscular thigh highlight
      buf.drawOvalFilled(leftLegX + 1, leftLegY + 1 + bodyBob, 3, 3, midGreen);
      buf.setPx(leftLegX + 1, leftLegY + bodyBob, brightGreen);
      buf.fillRect(leftLegX, leftLegY + 3 + bodyBob, 4, 4, midGreen);
      buf.fillRect(leftLegX + 1, leftLegY + 6 + bodyBob, 3, 2, brightGreen);
      buf.fillRect(leftLegX, leftLegY + 7 + bodyBob, 6, 2, midGreen);
      buf.setPx(leftLegX + 6, leftLegY + 8 + bodyBob, toothWhite);
      buf.setPx(leftLegX + 4, leftLegY + 8 + bodyBob, toothWhite);
    } else {
      // Tucked sleeping legs
      buf.drawOvalFilled(25, 29, 6, 3, darkGreen);
      buf.setPx(31, 30, toothWhite);
      buf.setPx(29, 30, toothWhite);
    }

    // 4. Articulated T-Rex Forearms (animated claw flex & typing taps)
    final int armTap = (isTyping || isListen || isFixing)
        ? (tick % 3 - 1)
        : ((tick % 16 < 8) ? 0 : 1);
    buf.fillRect(32, 20 + bodyBob, 4, 2, brightGreen);
    buf.fillRect(35, 21 + bodyBob + armTap, 3, 2, midGreen);
    buf.setPx(38, 21 + bodyBob + armTap, toothWhite);
    buf.setPx(38, 22 + bodyBob + armTap, toothWhite);

    // 5. Counter-Balanced T-Rex Skull, Expressive Brow & Jaw
    final int headCounterBob = isWalk ? (((tick + 2) % 6 < 3) ? 1 : 0) : 0;
    final int headTilt = isCurious ? 4 : (isRoar ? -2 : headCounterBob);
    final int headY = 7 + bodyBob + headTilt;
    buf.fillRect(28, headY + 5, 7, 6, midGreen);
    buf.fillRect(29, headY + 4, 6, 3, brightGreen);
    buf.fillRect(30, headY + 1, 16, 6, midGreen);
    buf.fillRect(31, headY, 14, 3, brightGreen);
    buf.fillRect(45, headY + 2, 3, 5, midGreen);
    buf.fillRect(32, headY - 1, 7, 2, limeScale);
    buf.setPx(30, headY, limeScale);
    buf.fillRect(44, headY + 2, 2, 1, darkGreen); // Nostril

    // Lifelike 3-stage eyelid blink & cursor-tracking golden eye
    final int blinkPhase = tick % 36;
    if (isSleep || (!isListen && !isFixing && !isRoar && blinkPhase >= 34)) {
      buf.fillRect(34, headY + 1, 4, 3, darkGreen);
      buf.fillRect(34, headY + 2, 4, 1, outline);
    } else if (!isListen &&
        !isFixing &&
        !isRoar &&
        (blinkPhase == 33 || blinkPhase == 0)) {
      buf.fillRect(34, headY + 1, 4, 1, limeScale);
      buf.fillRect(34, headY + 2, 4, 2, eyeGold);
      final int pxOff = (lookDx >= 0) ? 2 : 0;
      buf.fillRect(34 + pxOff, headY + 2, 2, 1, pupilBlack);
    } else {
      buf.fillRect(34, headY + 1, 4, 3, eyeGold);
      final int pxOff = (lookDx >= 0) ? 2 : 0;
      final int pyOff = (lookDy > 0.3) ? 1 : 0;
      buf.fillRect(34 + pxOff, headY + 1 + pyOff, 2, 2, pupilBlack);
      buf.setPx(34, headY + 1, toothWhite);
      buf.fillRect(33, headY, 5, 1, isRoar ? darkGreen : limeScale);
    }

    // Nostril snort / breath steam puff on exhale
    if (!isSleep && (isRoar || (tick % 20 >= 16))) {
      final int puffOff = (tick % 20) - 16;
      buf.setPx(
          48 + puffOff, headY + 1 - (puffOff ~/ 2), const Color(0xBBFFFFFF));
      buf.setPx(49 + puffOff, headY - (puffOff ~/ 2), const Color(0x88E0F7FA));
    }

    // Upper Razor Teeth
    for (int tx = 35; tx <= 46; tx += 2) {
      buf.setPx(tx, headY + 7, toothWhite);
      if (tx >= 39) buf.setPx(tx, headY + 8, toothWhite);
    }

    // Lower Jaw & Animated Flickering Tongue
    final int lowerY = headY + 8 + jawOpen;
    if (jawOpen > 0) {
      final int tongueWave = (tick % 4 < 2) ? 0 : 1;
      buf.fillRect(32, headY + 7 + tongueWave, 10, jawOpen, tongueRed);
      buf.setPx(42, headY + 7 + tongueWave, const Color(0xFFFF8A80));
    }
    buf.fillRect(30, lowerY, 16, 3, midGreen);
    buf.fillRect(31, lowerY + 2, 13, 1, bellyShadow);
    if (jawOpen >= 1) {
      for (int tx = 36; tx <= 45; tx += 2) {
        buf.setPx(tx, lowerY - 1, toothWhite);
      }
    }

    buf.applyPixelOutline(outline);
    _drawActivePropsAndParticles(buf, 'trex', animState, tick, audioLevel);

    return buf;
  }

  // =========================================================================
  // 2. TIER 1: SKY PTERODACTYL (56x40 Lightweight Speed Flyer)
  // =========================================================================
  static PixelBuffer _buildPterodactyl(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy,
  ) {
    final buf = PixelBuffer(kGridW, kGridH);

    const Color outline = Color(0xFF08141E);
    const Color wingShadow = Color(0xFF006064);
    const Color wingTeal = Color(0xFF00ACC1);
    const Color wingSky = Color(0xFF26C6DA);
    const Color wingMembrane = Color(0xFF80DEEA);
    const Color bodyAzure = Color(0xFF0288D1);
    const Color bellyCream = Color(0xFFE0F7FA);
    const Color crestBase = Color(0xFFE65100);
    const Color crestAmber = Color(0xFFFF8F00);
    const Color crestGold = Color(0xFFFFD54F);
    const Color beakGold = Color(0xFFFFB300);
    const Color beakTip = Color(0xFFFF6F00);
    const Color eyeWhite = Color(0xFFFFFFFF);
    const Color pupilDark = Color(0xFF102027);

    final bool isWalk = animState == 'walk';
    final bool isSleep = animState == 'sleep';
    final bool isCurious = animState == 'curious';
    final bool isTyping = animState == 'typing';
    final bool isListen =
        animState == 'listen' || isTyping || animState == 'target_wait';
    final bool isFixing = animState == 'fixing' || animState == 'happy';
    final bool isRoar = animState == 'roar';

    // Lightweight agile hover/perch bob
    final bool isFlapping = isListen || isFixing || isRoar || isCurious;
    final int hoverBob = isSleep
        ? 5
        : (isFlapping
            ? (math.sin(tick * 0.85) * 2.5).round() - 2
            : (isWalk
                ? ((tick % 4 < 2) ? -1 : 0)
                : (math.sin(tick * 0.35) * 1.2).round()));

    final int cx = 25;
    final int cy = 22 + hoverBob;

    // 1. Far Wing (Articulated Leathery Membrane flapping or folded)
    final double flapAngle = isSleep
        ? -0.4
        : (isFlapping
            ? math.sin(tick * 0.95) * 1.15
            : math.sin(tick * 0.35) * 0.35);
    final int farWingTipY = (cy - 9 - (flapAngle * 7)).round().clamp(2, 33);
    final int farWingTipX = (cx - 14 + (flapAngle * 3)).round();
    buf.drawLine(cx - 2, cy - 2, farWingTipX, farWingTipY, wingShadow);
    for (int wx = farWingTipX; wx <= cx - 2; wx++) {
      final double t = (wx - farWingTipX) / ((cx - 2 - farWingTipX).abs() + 1);
      final int topY = (farWingTipY + (cy - 2 - farWingTipY) * t).round();
      final int botY = (topY + 4 + (t * 4)).round();
      for (int wy = topY; wy <= botY; wy++) {
        buf.setPx(wx, wy, (wy == topY) ? wingTeal : wingShadow);
      }
    }

    // 2. Rudder Tail with Diamondvane Tip
    final int tailWave = (math.sin(tick * 0.45) * 1.5).round();
    buf.drawLine(cx - 7, cy + 2, cx - 17, cy + 4 + tailWave, wingShadow);
    buf.drawOvalFilled(cx - 18, cy + 4 + tailWave, 3, 2, crestAmber);
    buf.setPx(cx - 18, cy + 4 + tailWave, crestGold);

    // 3. Agile Aerodynamic Torso & Feathered Chest
    buf.drawOvalFilled(cx, cy, 7, 5, bodyAzure);
    buf.drawOvalFilled(cx + 1, cy - 1, 6, 4, wingSky);
    buf.drawOvalFilled(cx + 2, cy + 2, 5, 3, bellyCream);

    // 4. Near Wing (Sweeping Primary Spar, Wing Claw & Translucent Membrane)
    final int nearWingTipY = (cy - 11 - (flapAngle * 9)).round().clamp(2, 34);
    final int nearWingTipX = (cx - 18 - (flapAngle * 2)).round().clamp(2, 24);
    final int wingElbowX = cx - 6;
    final int wingElbowY = (cy - 5 - (flapAngle * 4)).round();

    for (int wx = nearWingTipX; wx <= cx + 1; wx++) {
      final double t =
          (wx - nearWingTipX) / ((cx + 1 - nearWingTipX).abs() + 1);
      final int sparY = (nearWingTipY + (cy - 1 - nearWingTipY) * t).round();
      final int scallop = ((wx % 4 == 0) ? 1 : 0);
      final int membraneBot = (sparY + 3 + (t * 6).round() - scallop);
      for (int wy = sparY; wy <= membraneBot; wy++) {
        Color c = wingMembrane;
        if (wy <= sparY + 1) c = wingSky;
        if (wy == sparY) c = crestGold;
        if (wy >= membraneBot - 1) c = wingTeal;
        buf.setPx(wx, wy, c);
      }
    }
    // Wing thumb claw at elbow joint
    buf.setPx(wingElbowX, wingElbowY - 1, eyeWhite);
    buf.setPx(wingElbowX + 1, wingElbowY - 2, eyeWhite);

    // 5. Perched / Striding Taloned Legs
    final int step = isWalk ? (tick % 8) : 0;
    final int leftFootDx = (step < 4) ? -2 : 1;
    final int rightFootDx = (step < 4) ? 1 : -2;
    final int legTopY = cy + 4;
    if (!isSleep) {
      // Far leg
      buf.fillRect(cx + 2 + rightFootDx, legTopY, 2, 6, wingShadow);
      buf.fillRect(cx + 2 + rightFootDx, legTopY + 5, 4, 2, crestAmber);
      buf.setPx(cx + 6 + rightFootDx, legTopY + 6, eyeWhite);
      // Near leg
      buf.fillRect(cx - 2 + leftFootDx, legTopY, 2, 7, bodyAzure);
      buf.fillRect(cx - 2 + leftFootDx, legTopY + 6, 4, 2, beakGold);
      buf.setPx(cx + 2 + leftFootDx, legTopY + 7, eyeWhite);
    } else {
      buf.fillRect(cx - 1, cy + 4, 4, 3, beakGold);
    }

    // 6. Swept-Back Cranial Crest, Head & Long Aerodynamic Beak
    final int headY = cy - 7 + (isCurious ? 2 : 0);
    final int headX = cx + 6;

    // Sweeping rearward crest (x = headX - 10 .. headX + 1)
    for (int cr = 0; cr <= 10; cr++) {
      final int crX = headX - cr;
      final int crY = headY - 1 - (cr ~/ 2);
      final int crH = (4 - (cr ~/ 3)).clamp(1, 4);
      for (int dy = 0; dy < crH; dy++) {
        Color c = (dy == 0) ? crestGold : (dy == 1 ? crestAmber : crestBase);
        if ((isListen || isFixing) && (cr + tick) % 4 == 0) {
          c = const Color(0xFF00E5FF);
        }
        buf.setPx(crX, crY + dy, c);
      }
    }

    // Neck & Cranium
    buf.fillRect(cx + 4, cy - 4, 4, 5, wingSky);
    buf.fillRect(headX - 1, headY, 7, 5, wingSky);
    buf.fillRect(headX, headY - 1, 5, 2, crestAmber);

    // Long pointed upper beak (x = headX + 6 .. headX + 18)
    for (int bx = 0; bx <= 12; bx++) {
      final int h = (3 - (bx ~/ 4)).clamp(1, 3);
      for (int by = 0; by < h; by++) {
        buf.setPx(
          headX + 6 + bx,
          headY + 1 + by + (bx ~/ 6),
          (bx > 8) ? beakTip : (by == 0 ? crestGold : beakGold),
        );
      }
    }

    // Voice-reactive lower beak
    int beakOpen = 0;
    if (isRoar) {
      beakOpen = 4;
    } else if (isListen) {
      beakOpen = (1 + (audioLevel * 4.0).round()).clamp(1, 3);
      if (isTyping && tick % 2 == 0 && beakOpen < 2) beakOpen = 2;
    } else if (isFixing) {
      beakOpen = (tick % 4 < 2) ? 2 : 0;
    }
    for (int bx = 0; bx <= 9; bx++) {
      buf.setPx(
        headX + 6 + bx,
        headY + 4 + beakOpen + (bx ~/ 5),
        (bx > 6) ? beakTip : crestBase,
      );
    }

    // Cursor-tracking eye & 3-stage blink
    final int blinkPhase = tick % 34;
    if (isSleep || (!isListen && !isFixing && !isRoar && blinkPhase >= 32)) {
      buf.fillRect(headX + 2, headY + 1, 3, 2, wingShadow);
      buf.fillRect(headX + 2, headY + 2, 3, 1, outline);
    } else {
      buf.fillRect(headX + 2, headY + 1, 3, 2, eyeWhite);
      final int pxOff = (lookDx >= 0) ? 1 : 0;
      final int pyOff = (lookDy > 0.3) ? 1 : 0;
      buf.setPx(headX + 2 + pxOff, headY + 1 + pyOff, pupilDark);
    }

    buf.applyPixelOutline(outline);
    _drawActivePropsAndParticles(buf, 'ptero', animState, tick, audioLevel);

    return buf;
  }

  // =========================================================================
  // 3. TIER 2: HOODED CULTIST SCRIBE (56x40 Humanoid Grammarly Mentor)
  //    "Somebody with a covered face in a little robe" + levitating quill & book
  // =========================================================================
  static PixelBuffer _buildCultist(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy,
  ) {
    final buf = PixelBuffer(kGridW, kGridH);

    const Color outline = Color(0xFF0D0614);
    const Color robeDeep = Color(0xFF311B92);
    const Color robeCrimson = Color(0xFF6A1B4D);
    const Color robePlum = Color(0xFF8E24AA);
    const Color robeHighlight = Color(0xFFAB47BC);
    const Color goldTrim = Color(0xFFFFD54F);
    const Color goldDark = Color(0xFFFF8F00);
    const Color voidFace = Color(0xFF09040E);
    const Color maskCloth = Color(0xFF1A0F2E);
    const Color eyeCyan = Color(0xFF00E5FF);
    const Color eyeGold = Color(0xFFFFEA00);
    const Color eyeGreen = Color(0xFF69F0AE);
    const Color parchment = Color(0xFFFFF8E1);
    const Color bookCover = Color(0xFF4E342E);
    const Color quillFeather = Color(0xFF80DEEA);
    const Color bootLeather = Color(0xFF261822);

    final bool isWalk = animState == 'walk';
    final bool isSleep = animState == 'sleep';
    final bool isCurious = animState == 'curious';
    final bool isTyping = animState == 'typing';
    final bool isListen =
        animState == 'listen' || isTyping || animState == 'target_wait';
    final bool isFixing = animState == 'fixing' || animState == 'happy';
    final bool isRoar = animState == 'roar';

    final int bodyBob = isSleep
        ? 3
        : (isWalk
            ? ((tick % 4 < 2) ? -1 : 0)
            : (isFixing
                ? ((tick % 4 < 2) ? -2 : 0)
                : ((tick % 12 < 6) ? 0 : 1)));

    final int cx = 25;
    final int baseY = 33; // Feet rest on the cobblestone floor

    // 1. Little Boots Peeking Beneath the Robe Hem (animated 12-frame stride)
    if (!isSleep) {
      final int step = isWalk ? (tick % 8) : 0;
      final int leftDx = isWalk ? ((step < 4) ? -2 : 2) : 0;
      final int rightDx = isWalk ? ((step < 4) ? 2 : -2) : 0;
      final int leftLift = (isWalk && step < 2) ? -1 : 0;
      final int rightLift = (isWalk && step >= 4 && step < 6) ? -1 : 0;
      buf.fillRect(cx - 5 + leftDx, baseY + leftLift, 4, 2, bootLeather);
      buf.setPx(cx - 2 + leftDx, baseY + 1 + leftLift, goldDark);
      buf.fillRect(cx + 2 + rightDx, baseY + rightLift, 4, 2, bootLeather);
      buf.setPx(cx + 5 + rightDx, baseY + 1 + rightLift, goldDark);
    }

    // 2. Flowing Little Robe & Mantle with Gold Rune Trim (y = 18..32)
    final int robeSway =
        isWalk ? ((tick % 6 < 3) ? -1 : 1) : (math.sin(tick * 0.3) * 1).round();
    for (int ry = 18 + bodyBob; ry <= 32 + bodyBob; ry++) {
      final double progress = (ry - (18 + bodyBob)) / 14.0;
      final int halfW = (5 + progress * 4.5).round();
      final int rowCenter = cx + (progress > 0.6 ? robeSway : 0);
      for (int rx = rowCenter - halfW; rx <= rowCenter + halfW; rx++) {
        Color col = robeCrimson;
        if (rx < rowCenter - halfW + 2) col = robeDeep;
        if (rx > rowCenter + halfW - 2) col = robePlum;
        if (rx == rowCenter + halfW - 1 && ry < 26 + bodyBob) {
          col = robeHighlight;
        }
        // Vertical central gold stole & bottom gold hem
        if ((rx - rowCenter).abs() <= 1 && ry >= 20 + bodyBob) {
          col = (ry % 2 == 0) ? goldTrim : goldDark;
        }
        if (ry == 32 + bodyBob) {
          col = ((rx + ry) % 2 == 0) ? goldTrim : goldDark;
        }
        buf.setPx(rx, ry, col);
      }
    }

    // Corded waist sash / belt with dangling charm
    buf.fillRect(cx - 6, 24 + bodyBob, 13, 2, goldDark);
    buf.fillRect(cx - 1, 24 + bodyBob, 3, 2, goldTrim);
    buf.setPx(cx + 2, 26 + bodyBob, goldTrim);
    buf.setPx(cx + 2, 27 + bodyBob, eyeCyan);

    // 3. Pointed Arcane Hood & Covered/Shadowed Face (y = 6..19)
    final int headTilt = isCurious ? 1 : (isRoar ? -1 : 0);
    final int hoodTopY = 6 + bodyBob + headTilt;

    // Pointed hood peak curving back to the left
    buf.fillRect(cx - 7, hoodTopY, 4, 2, robeDeep);
    buf.fillRect(cx - 5, hoodTopY + 1, 9, 2, robeCrimson);
    buf.drawOvalFilled(cx, hoodTopY + 7, 8, 6, robeCrimson);
    buf.drawOvalFilled(cx + 1, hoodTopY + 6, 7, 5, robePlum);

    // Gold trim along the front cowl edge of the hood
    for (int hy = hoodTopY + 2; hy <= hoodTopY + 11; hy++) {
      buf.setPx(cx - 6, hy, goldDark);
      buf.setPx(cx + 7, hy, goldTrim);
    }
    buf.fillRect(cx - 5, hoodTopY + 2, 12, 1, goldTrim);

    // Deep shadowed void inside the hood + cloth face wrap covering lower face
    buf.drawOvalFilled(cx + 1, hoodTopY + 7, 5, 4, voidFace);
    // Cloth mask / scarf wrapping across the lower face ("covered face")
    buf.fillRect(cx - 4, hoodTopY + 9, 11, 3, maskCloth);
    buf.fillRect(cx - 3, hoodTopY + 9, 9, 1, robeDeep);
    // Subtle voice-reactive rune shimmer on the face scarf while dictating!
    if (isListen && audioLevel > 0.06) {
      final int runeGlowW = (audioLevel * 6).round().clamp(1, 5);
      buf.fillRect(cx + 1 - (runeGlowW ~/ 2), hoodTopY + 10, runeGlowW, 1,
          eyeCyan);
    }

    // Two Mysterious Glowing Eyes Peering Out from Under the Hood
    final int blinkPhase = tick % 36;
    final Color activeEyeColor = isFixing
        ? eyeGold
        : (isListen ? eyeGreen : (isRoar ? const Color(0xFFFF4081) : eyeCyan));

    if (isSleep || (!isListen && !isFixing && !isRoar && blinkPhase >= 34)) {
      // Closed glowing slits
      buf.fillRect(cx - 2, hoodTopY + 7, 2, 1, goldDark);
      buf.fillRect(cx + 3, hoodTopY + 7, 2, 1, goldDark);
    } else {
      final int lookShiftX = (lookDx >= 0.2) ? 1 : (lookDx <= -0.2 ? -1 : 0);
      final int lookShiftY = (lookDy > 0.35) ? 1 : 0;
      final int eyeY = hoodTopY + 6 + lookShiftY;
      // Left peering eye
      buf.fillRect(cx - 3 + lookShiftX, eyeY, 2, 2, activeEyeColor);
      buf.setPx(cx - 3 + lookShiftX, eyeY, const Color(0xFFFFFFFF));
      // Right peering eye
      buf.fillRect(cx + 2 + lookShiftX, eyeY, 2, 2, activeEyeColor);
      buf.setPx(cx + 2 + lookShiftX, eyeY, const Color(0xFFFFFFFF));
    }

    // 4. Draped Robe Sleeves & Hands Holding the Levitating Grammarly Grimoire + Quill
    final int sleeveY = 20 + bodyBob + ((isListen || isTyping || isFixing) ? -1 : 0);
    buf.fillRect(cx + 4, sleeveY, 6, 4, robePlum);
    buf.fillRect(cx + 9, sleeveY, 1, 4, goldTrim);
    // Tiny cuffed hand
    buf.fillRect(cx + 10, sleeveY + 1, 2, 2, maskCloth);

    // Levitating Open Grimoire / Scroll in front of the Cultist (x = 38..49)
    final int bookHover =
        (math.sin(tick * 0.45) * 1.5).round() + (isFixing ? -2 : 0);
    final int bookX = 39;
    final int bookY = 18 + bodyBob + bookHover;
    // Book leather cover & glowing gold spine
    buf.fillRect(bookX, bookY + 2, 11, 5, bookCover);
    buf.fillRect(bookX + 4, bookY + 3, 3, 5, goldTrim);
    // Open cream parchment pages
    buf.fillRect(bookX + 1, bookY, 9, 4, parchment);
    // Animated ink text lines being written on the parchment
    final int inkProgress = (tick % 7);
    buf.fillRect(bookX + 2, bookY + 1, 3, 1, robeDeep);
    buf.fillRect(bookX + 6, bookY + 1, (inkProgress % 3) + 1, 1, eyeCyan);
    buf.fillRect(bookX + 2, bookY + 2, (inkProgress % 4) + 1, 1, robeCrimson);

    // Self-Writing Enchanted Feather Quill (scribbles rapidly when listening/fixing/typing!)
    final int quillScribbleX =
        (isListen || isTyping || isFixing || isCurious)
            ? (bookX + 2 + (tick % 6))
            : (bookX + 5);
    final int quillScribbleY = bookY - 1 - ((tick % 2 == 0 && isListen) ? 1 : 0);
    // Quill nib (gold) + feather shaft (cyan/white)
    buf.setPx(quillScribbleX, quillScribbleY + 1, goldTrim);
    buf.drawLine(
      quillScribbleX,
      quillScribbleY,
      quillScribbleX + 4,
      quillScribbleY - 5,
      quillFeather,
    );
    buf.drawLine(
      quillScribbleX + 1,
      quillScribbleY - 1,
      quillScribbleX + 5,
      quillScribbleY - 5,
      const Color(0xFFFFFFFF),
    );

    buf.applyPixelOutline(outline);
    _drawActivePropsAndParticles(buf, 'cultist', animState, tick, audioLevel);

    return buf;
  }

  // =========================================================================
  // 4. ACTIVE SCENE PROPS & PARTICLE EFFECTS (Dust, Hologram Keyboard, Zzz, Runes)
  // =========================================================================
  static void _drawActivePropsAndParticles(
    PixelBuffer buf,
    String creature,
    String animState,
    int tick,
    double audioLevel,
  ) {
    final bool isCultist = creature == 'cultist' || creature == 'monster';

    // A. Footstep Dust Puffs during Walk
    if (animState == 'walk') {
      const Color dustLight = Color(0xCCCFD8DC);
      const Color dustMid = Color(0x9990A4AE);
      final int puffPhase = tick % 6;
      final int dustX = 12 - puffPhase * 2;
      final int dustY = 34 - (puffPhase ~/ 2);
      buf.fillRect(dustX, dustY, 2, 2, dustLight);
      buf.setPx(dustX - 2, dustY + 1, dustMid);
      buf.setPx(dustX + 3, dustY - 1, dustMid);
    }

    // B. Sleeping Floating Pixel "Z z ." Bubbles
    if (animState == 'sleep') {
      const Color zCol = Color(0xFF80D8FF);
      final int zRise = (tick ~/ 2) % 8;
      final int zx = 43 + (zRise % 2);
      final int zy = 12 - zRise;
      buf.fillRect(zx, zy, 4, 1, zCol);
      buf.setPx(zx + 2, zy + 1, zCol);
      buf.setPx(zx + 1, zy + 2, zCol);
      buf.fillRect(zx, zy + 3, 4, 1, zCol);
      buf.fillRect(zx - 5, zy + 5, 3, 1, zCol);
      buf.setPx(zx - 4, zy + 6, zCol);
      buf.fillRect(zx - 5, zy + 7, 3, 1, zCol);
    }

    // C. Curious / Grazing Props (Orbiting Grammarly runes or wind/fern sprouts)
    if (animState == 'curious') {
      if (isCultist) {
        const Color runeCol = Color(0xFFEA80FC);
        const Color runeCore = Color(0xFFFFFFFF);
        for (int r = 0; r < 3; r++) {
          final double ang = (tick * 0.25) + r * 2.09;
          final int rx = (26 + math.cos(ang) * 18).round();
          final int ry = (18 + math.sin(ang) * 10).round();
          buf.fillRect(rx - 1, ry - 1, 3, 3, runeCol);
          buf.setPx(rx, ry, runeCore);
        }
      } else {
        const Color fernDark = Color(0xFF2E7D32);
        const Color fernBright = Color(0xFF69F0AE);
        buf.fillRect(47, 31, 2, 4, fernDark);
        buf.fillRect(45, 29, 2, 3, fernBright);
        buf.fillRect(49, 28, 2, 4, fernBright);
        buf.setPx(44, 28, fernBright);
        buf.setPx(51, 27, fernBright);
      }
    }

    // D. Active Typing Props: Floating Holographic Pixel Keyboard / Arcane Scroll
    if (animState == 'typing') {
      const Color holoFrame = Color(0xFF00E5FF);
      const Color holoBg = Color(0xAA004D40);
      const Color keyLit = Color(0xFFFFF59D);
      final int hover = (tick % 4 < 2) ? 0 : -1;
      buf.fillRect(41, 25 + hover, 12, 6, holoBg);
      buf.fillRect(41, 25 + hover, 12, 1, holoFrame);
      buf.fillRect(41, 30 + hover, 12, 1, holoFrame);
      for (int kx = 42; kx <= 51; kx += 2) {
        final bool pressed = ((kx + tick) % 4 == 0);
        buf.setPx(
          kx,
          27 + hover + (pressed ? 1 : 0),
          pressed ? keyLit : holoFrame,
        );
        buf.setPx(kx + 1, 28 + hover, holoFrame);
      }
    }

    // E. Listening Sonar Rings
    if (animState == 'listen' || animState == 'target_wait') {
      const Color waveCol = Color(0xFF00E676);
      const Color waveGlow = Color(0xFF69F0AE);
      final int phase = tick % 4;
      final int arcX = 50 + phase;
      if (arcX < kGridW - 1) {
        for (int dy = -4; dy <= 4; dy++) {
          final int dx = (dy.abs() >= 3) ? -1 : 0;
          buf.setPx(arcX + dx, 14 + dy, (dy.abs() <= 1) ? waveGlow : waveCol);
        }
      }
    }

    // F. Grammar Fix / Roar Particle Starburst
    if (animState == 'fixing' || animState == 'happy' || animState == 'roar') {
      const Color starCyan = Color(0xFF00E5FF);
      const Color starGold = Color(0xFFFFD740);
      const Color starPink = Color(0xFFFF4081);
      final List<List<int>> stars = [
        [8, 6 + (tick % 4)],
        [48, 5 + ((tick + 1) % 4)],
        [27, 2 + ((tick + 2) % 3)],
        [14, 4 + ((tick + 3) % 3)],
        [42, 10 + (tick % 3)],
      ];
      final List<Color> cols = [starCyan, starGold, starPink];
      for (int i = 0; i < stars.length; i++) {
        final int sx = stars[i][0];
        final int sy = stars[i][1];
        final Color c = cols[(i + tick) % cols.length];
        buf.setPx(sx, sy, c);
        buf.setPx(sx - 1, sy, c);
        buf.setPx(sx + 1, sy, c);
        buf.setPx(sx, sy - 1, c);
        buf.setPx(sx, sy + 1, c);
      }
    }

    // G. Subtle Ambient Floating Pixel Motes / Fireflies (always alive!)
    if (animState != 'sleep') {
      final Color moteCol = isCultist
          ? const Color(0xAAEA80FC)
          : (creature == 'trex'
              ? const Color(0xAA69F0AE)
              : const Color(0xAA80DEEA));
      for (int m = 0; m < 2; m++) {
        final double ang = tick * 0.14 + m * 3.14;
        final int mx = (26 + math.cos(ang) * 21).round();
        final int my = (16 + math.sin(ang * 1.3) * 9).round();
        if (buf.getPx(mx, my) == null) {
          buf.setPx(mx, my, moteCol);
        }
      }
    }
  }

  // =========================================================================
  // 5. LIVING PIXEL TERRAIN FLOOR GENERATOR (110x10 Grid on Top of Floor Box)
  //    - Dinosaurs ('trex', 'ptero', 'stego'): Swaying Prehistoric Grass, Ferns & Soil
  //    - Cultist ('cultist', 'monster')      : Carved Cobblestones, Runes & Candles
  // =========================================================================
  static PixelBuffer buildTerrainFloor({
    required String creature,
    required int tick,
    required bool isActive,
  }) {
    final buf = PixelBuffer(kFloorW, kFloorH);
    final bool isCultist = creature == 'cultist' || creature == 'monster';

    if (isCultist) {
      // ARCANE COBBLESTONE ALTAR FLOOR WITH RUNES & FLICKERING CANDLES
      const Color stoneDark = Color(0xFF1A1224);
      const Color stoneMid = Color(0xFF2D223B);
      const Color stoneHighlight = Color(0xFF4A3B5C);
      const Color mortar = Color(0xFF0E0814);
      const Color runeGlow = Color(0xFFEA80FC);
      const Color runeCyan = Color(0xFF00E5FF);
      const Color mossGreen = Color(0xFF2E7D32);
      const Color waxCream = Color(0xFFFFF8E1);
      const Color flameGold = Color(0xFFFFD54F);
      const Color flameOrange = Color(0xFFFF6D00);

      // Base stone slab (rows 6..9)
      buf.fillRect(0, 6, kFloorW, 4, stoneMid);
      buf.fillRect(0, 6, kFloorW, 1, stoneHighlight);
      buf.fillRect(0, 9, kFloorW, 1, stoneDark);

      // Individual cobblestone joints & glowing runes
      for (int x = 0; x < kFloorW; x++) {
        if (x % 11 == 0) {
          buf.fillRect(x, 6, 1, 4, mortar);
        }
        if (x % 7 == 3) {
          buf.setPx(x, 7, stoneDark);
        }
        // Ancientmoss tufts growing between cracks
        if (x % 19 == 5) {
          buf.setPx(x, 5, mossGreen);
          buf.setPx(x + 1, 6, mossGreen);
        }
        // Pulsing arcane runes carved into the flagstones
        if (x % 16 == 8 && x > 10 && x < kFloorW - 10) {
          final bool pulse = ((tick + x) % 6 < 3) || isActive;
          final Color rCol =
              (x % 32 == 8) ? (pulse ? runeCyan : runeGlow) : runeGlow;
          buf.setPx(x, 7, rCol);
          buf.setPx(x + 1, 8, rCol);
          buf.setPx(x + 2, 7, rCol);
        }
      }

      // Flickering Sanctuary Candles at left & right corners of the stone floor
      const List<int> candleX = [4, 9, kFloorW - 10, kFloorW - 5];
      for (int i = 0; i < candleX.length; i++) {
        final int cx = candleX[i];
        final int h = (i % 2 == 0) ? 4 : 3;
        buf.fillRect(cx, 6 - h, 2, h, waxCream);
        final int flicker = ((tick + i * 3) % 3 == 0) ? -1 : 0;
        buf.setPx(cx, 5 - h + flicker, flameGold);
        buf.setPx(cx + 1, 5 - h, flameOrange);
      }
    } else {
      // PREHISTORIC LUSH SWAYING GRASS, FERN FRONDS, WILDFLOWERS & SOIL
      const Color soilDark = Color(0xFF271911);
      const Color soilMid = Color(0xFF3E2723);
      const Color soilLight = Color(0xFF5D4037);
      const Color turfBase = Color(0xFF1B5E20);
      const Color grassMid = Color(0xFF2E7D32);
      const Color grassBright = Color(0xFF43A047);
      const Color grassNeon = Color(0xFF69F0AE);
      const Color flowerAmber = Color(0xFFFFD54F);
      const Color flowerCyan = Color(0xFF00E5FF);

      // Rich pixel soil & root layer (rows 7..9)
      buf.fillRect(0, 7, kFloorW, 3, soilMid);
      buf.fillRect(0, 9, kFloorW, 1, soilDark);
      // Thick green turf mat (rows 5..6)
      buf.fillRect(0, 5, kFloorW, 2, turfBase);

      final int windShift = ((tick ~/ 4) % 3) - 1;

      for (int x = 0; x < kFloorW; x++) {
        // Hanging grass roots into soil
        if (x % 4 == 0) buf.setPx(x, 7, turfBase);
        if (x % 7 == 0) buf.setPx(x, 8, soilLight);

        // Swaying grass blades of varying heights (rows 1..4)
        final int hash = (x * 37 + 13) % 7;
        final int bladeH = (hash % 4) + 1; // 1..4 px tall above row 5
        final int tipSway = (bladeH >= 3) ? windShift : 0;

        for (int dy = 1; dy <= bladeH; dy++) {
          final int bx = (x + (dy == bladeH ? tipSway : 0)).clamp(0, kFloorW - 1);
          final int by = 5 - dy;
          Color c = grassMid;
          if (dy == bladeH) {
            c = (isActive && x % 5 == 0) ? grassNeon : grassBright;
          } else if (dy >= 2) {
            c = grassBright;
          }
          buf.setPx(bx, by, c);
        }

        // Prehistoric fern clusters & tiny blossoms
        if (x % 18 == 6) {
          buf.setPx(x - 1, 3, grassNeon);
          buf.setPx(x, 2, grassNeon);
          buf.setPx(x + 1, 3, grassNeon);
        }
        if (x % 23 == 11) {
          buf.setPx(
            x,
            2,
            (creature == 'ptero' || creature == 'stego')
                ? flowerCyan
                : flowerAmber,
          );
        }
      }
    }

    return buf;
  }
}

class PixelCreaturePainter extends CustomPainter {
  final PixelBuffer buffer;
  final bool flipHorizontal;

  PixelCreaturePainter({
    required this.buffer,
    required this.flipHorizontal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int cols = buffer.width;
    final int rows = buffer.height;
    final double pixelSize = math.min(size.width / cols, size.height / rows);

    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Ground shadow oval directly under feet
    paint.color = const Color(0x55000000);
    canvas.drawRect(
      Rect.fromLTWH(
        pixelSize * 12,
        (rows - 3) * pixelSize,
        (cols - 24) * pixelSize,
        pixelSize * 1.8,
      ),
      paint,
    );

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final Color? color = buffer.getPx(x, y);
        if (color == null) continue;
        final int drawX = flipHorizontal ? (cols - 1 - x) : x;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            drawX * pixelSize,
            y * pixelSize,
            pixelSize + 0.35,
            pixelSize + 0.35,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelCreaturePainter oldDelegate) {
    return oldDelegate.buffer != buffer ||
        oldDelegate.flipHorizontal != flipHorizontal;
  }
}

class PixelTerrainFloorPainter extends CustomPainter {
  final PixelBuffer buffer;

  PixelTerrainFloorPainter({required this.buffer});

  @override
  void paint(Canvas canvas, Size size) {
    final int cols = buffer.width;
    final int rows = buffer.height;
    final double cellW = size.width / cols;
    final double cellH = size.height / rows;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final Color? color = buffer.getPx(x, y);
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            x * cellW,
            y * cellH,
            cellW + 0.4,
            cellH + 0.4,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelTerrainFloorPainter oldDelegate) {
    return oldDelegate.buffer != buffer;
  }
}

class PixelTerrainFloorWidget extends StatelessWidget {
  final String creature;
  final int tick;
  final bool isActive;
  final double width;
  final double height;

  const PixelTerrainFloorWidget({
    super.key,
    required this.creature,
    required this.tick,
    required this.isActive,
    required this.width,
    this.height = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final PixelBuffer buffer = HighResPixelGenerator.buildTerrainFloor(
      creature: creature,
      tick: tick,
      isActive: isActive,
    );
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: PixelTerrainFloorPainter(buffer: buffer),
      ),
    );
  }
}

class PixelCreatureWidget extends StatelessWidget {
  final String creature;
  final String animState;
  final int tick;
  final bool flipHorizontal;
  final double pixelScale;
  final double audioLevel;
  final double lookDx;
  final double lookDy;
  final String? customSpritePath;

  const PixelCreatureWidget({
    super.key,
    required this.creature,
    required this.animState,
    required this.tick,
    required this.flipHorizontal,
    required this.pixelScale,
    required this.audioLevel,
    this.lookDx = 0.5,
    this.lookDy = 0.0,
    this.customSpritePath,
  });

  @override
  Widget build(BuildContext context) {
    final double cellPx = pixelScale * 0.52;
    final double width = HighResPixelGenerator.kGridW * cellPx;
    final double height = HighResPixelGenerator.kGridH * cellPx;

    if (creature == 'custom' &&
        customSpritePath != null &&
        customSpritePath!.isNotEmpty &&
        File(customSpritePath!).existsSync()) {
      final double bounceOffset =
          (animState == 'walk' || animState == 'listen' || animState == 'fixing')
              ? ((tick % 2 == 0) ? -cellPx * 2 : 0.0)
              : 0.0;
      return Transform.translate(
        offset: Offset(0, bounceOffset),
        child: Transform.flip(
          flipX: flipHorizontal,
          child: Image.file(
            File(customSpritePath!),
            width: width,
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        ),
      );
    }

    final double effectiveLookDx = flipHorizontal ? -lookDx : lookDx;

    final PixelBuffer buffer = HighResPixelGenerator.buildFrame(
      creature: creature,
      animState: animState,
      tick: tick,
      audioLevel: audioLevel,
      lookDx: effectiveLookDx,
      lookDy: lookDy,
    );

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: PixelCreaturePainter(
          buffer: buffer,
          flipHorizontal: flipHorizontal,
        ),
      ),
    );
  }
}
