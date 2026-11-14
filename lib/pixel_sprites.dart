import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Indie-Game Quality Pixel-Art Sprite, Particle & Terrain Engine (56x40 Creature Grid + 110x10 Terrain Grid).
///
/// 3-Tier Creature Progression:
/// - Tier 1 ('ptero' / 'stego')   : Sky Pterodactyl — Lightweight Speed (small.en, ~0.5 GB VRAM)
/// - Tier 2 ('cultist' / 'monster'): Ember Void Cultist (Enter the Gungeon style) — Grammarly Scribe (medium.en, ~1.5 GB VRAM)
/// - Tier 2 ('cultist_lunar')     : Lunatic Beak Cultist (Terraria style) — Grammarly Scribe (medium.en, ~1.5 GB VRAM)
/// - Tier 3 ('trex')              : Apex Green T-Rex — Heavyweight Powerhouse (large-v3-turbo, ~2.0 GB VRAM)

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

  /// Applies a crisp 1-pixel game-style selective outline around all sprite pixels
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
      case 'cultist_lunar':
        return _buildLunaticCultist(
            animState, tick, audioLevel, lookDx, lookDy);
      case 'review':
      case 'cultist':
      case 'monster':
        return _buildEmberCultist(
          animState,
          tick,
          audioLevel,
          lookDx,
          lookDy,
          isReviewerMode: creature == 'review',
        );
      case 'ptero':
      case 'stego':
      default:
        return _buildPterodactyl(animState, tick, audioLevel, lookDx, lookDy);
    }
  }

  // =========================================================================
  // 1. TIER 2A: EMBER VOID CULTIST (Enter the Gungeon Style — Image 1 Reference)
  //    Warm vermilion/orange hood with purple back-shadow, thick bright gold cowl
  //    border, circular dark-navy void face, 1x2 cyan+white eyes, gold brooch
  //    with emerald gem, gold sleeve cuffs & bottom hem + levitating grimoire!
  // =========================================================================
  static PixelBuffer _buildEmberCultist(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy, {
    bool isReviewerMode = false,
  }) {
    final buf = PixelBuffer(kGridW, kGridH);

    // Exact Indie-Game Palette matched to Reference Image 1
    const Color outline = Color(0xFF14061C);
    const Color hoodRedTop = Color(0xFFD43214);
    const Color hoodOrange = Color(0xFFE5641A);
    const Color hoodPurpleShadow = Color(0xFF7B105E);
    const Color goldBright = Color(0xFFFFEE18);
    const Color goldMid = Color(0xFFE6B812);
    const Color goldShadow = Color(0xFFA87B12);
    const Color voidNavy = Color(0xFF040828);
    const Color eyeCyanTop = Color(0xFF18A0F8);
    const Color eyeWhiteBot = Color(0xFFFFFFFF);
    const Color emeraldGem = Color(0xFF00E84A);
    const Color parchment = Color(0xFFFFF8E1);
    const Color bookCover = Color(0xFF5D2E1E);
    const Color quillCyan = Color(0xFF80DEEA);

    final bool isWalk = animState == 'walk';
    final bool isSleep = animState == 'sleep';
    final bool isCurious = animState == 'curious';
    final bool isTyping = animState == 'typing';
    final bool isListen =
        animState == 'listen' || isTyping || animState == 'target_wait';
    final bool isFixing = animState == 'fixing' || animState == 'happy';
    final bool isRoar = animState == 'roar';

    // Snappy Gungeon-style bounce & squash-and-stretch
    final int bounceY = isSleep
        ? 2
        : (isWalk
            ? ((tick % 4 < 2) ? -2 : 0)
            : (isFixing
                ? ((tick % 4 < 2) ? -3 : 0)
                : ((tick % 10 < 5) ? 0 : 1)));

    final int cx = 24;
    final int hoodY = 5 + bounceY;

    // --- A. ROUNDED CHIBI HOOD & COWL (y = hoodY .. hoodY + 18, 19px tall) ---
    // Row-by-row hand-crafted pixel dome matching Image 1's exact silhouette
    final List<List<int>> hoodBounds = [
      [-4, 4], // row 0 (top crown)
      [-6, 6], // row 1
      [-8, 7], // row 2
      [-9, 8], // row 3
      [-10, 9], // row 4
      [-11, 10], // row 5
      [-11, 10], // row 6
      [-11, 11], // row 7
      [-11, 11], // row 8
      [-11, 11], // row 9
      [-11, 10], // row 10
      [-11, 10], // row 11
      [-11, 9], // row 12
      [-10, 9], // row 13
      [-9, 8], // row 14
      [-8, 7], // row 15
    ];

    for (int r = 0; r < hoodBounds.length; r++) {
      final int y = hoodY + r;
      final int xMin = hoodBounds[r][0];
      final int xMax = hoodBounds[r][1];
      for (int dx = xMin; dx <= xMax; dx++) {
        Color c = hoodOrange;
        if (r <= 1) {
          c = (dx >= 2) ? hoodPurpleShadow : hoodRedTop;
        } else if (dx >= xMax - 2) {
          // Purple shadow on the back of the hood (left when flipped, right side here)
          c = hoodPurpleShadow;
        } else if (dx >= xMax - 4 && r >= 3 && r <= 10) {
          c = hoodRedTop;
        } else if (r <= 3) {
          c = hoodRedTop;
        }
        buf.setPx(cx + dx, y, c);
      }
    }

    // Thick Golden-Yellow Cowl Ring Framing the Void Face (cx - 1, hoodY + 9)
    final int faceCx = cx - 1;
    final int faceCy = hoodY + 9;
    buf.drawOvalFilled(faceCx, faceCy, 8, 6, goldBright);
    // Shaded lower-side gold rim (matching Image 1's #A87B12 lower cowl)
    for (int py = faceCy; py <= faceCy + 6; py++) {
      for (int px = faceCx - 8; px <= faceCx + 8; px++) {
        if (buf.getPx(px, py) == goldBright && py >= faceCy + 1) {
          buf.setPx(px, py, (py >= faceCy + 3) ? goldShadow : goldMid);
        }
      }
    }

    // Large Circular Dark-Navy Void Face Inside the Cowl
    buf.drawOvalFilled(faceCx, faceCy + 1, 6, 5, voidNavy);

    // Iconic 1x2 Vertical Pixel Eyes (Cyan top #18A0F8 + White bottom #FFFFFF)
    final int blinkPhase = tick % 36;
    final int lookShiftX = (lookDx >= 0.25) ? 1 : (lookDx <= -0.25 ? -1 : 0);
    final int lookShiftY = (lookDy > 0.35) ? 1 : 0;
    final int eyeLeftX = faceCx - 4 + lookShiftX;
    final int eyeRightX = faceCx + 2 + lookShiftX;
    final int eyeTopY = faceCy - 1 + lookShiftY;

    if (isSleep || (!isListen && !isFixing && !isRoar && blinkPhase >= 34)) {
      // Sleeping / blinking horizontal cyan slits
      buf.fillRect(eyeLeftX, eyeTopY + 1, 2, 1, eyeCyanTop);
      buf.fillRect(eyeRightX, eyeTopY + 1, 2, 1, eyeCyanTop);
    } else if (isFixing || isRoar) {
      // Excited glowing eyes during spellcast / grammar fix!
      buf.fillRect(eyeLeftX, eyeTopY, 2, 1, goldBright);
      buf.fillRect(eyeLeftX, eyeTopY + 1, 2, 2, eyeWhiteBot);
      buf.fillRect(eyeRightX, eyeTopY, 2, 1, goldBright);
      buf.fillRect(eyeRightX, eyeTopY + 1, 2, 2, eyeWhiteBot);
    } else {
      // Classic Gungeon Cultist 2x3 / 1x2 two-tone eyes (Cyan top, White bottom)
      buf.fillRect(eyeLeftX, eyeTopY, 2, 1, eyeCyanTop);
      buf.fillRect(eyeLeftX, eyeTopY + 1, 2, 2, eyeWhiteBot);
      buf.fillRect(eyeRightX, eyeTopY, 2, 1, eyeCyanTop);
      buf.fillRect(eyeRightX, eyeTopY + 1, 2, 2, eyeWhiteBot);
    }

    // --- B. COMPACT ROBED BODY, EMERALD CLASP, SLEEVES & GOLD HEM (y = hoodY + 15 .. hoodY + 27) ---
    final int robeTopY = hoodY + 15;
    final int robeBotY = hoodY + 26;
    final int sway = isWalk ? ((tick % 4 < 2) ? -1 : 1) : 0;

    for (int ry = robeTopY; ry <= robeBotY; ry++) {
      final double prog = (ry - robeTopY) / 11.0;
      final int halfW = (7 + prog * 3.5).round();
      final int rowCx = cx + (prog > 0.5 ? sway : 0);
      for (int rx = rowCx - halfW; rx <= rowCx + halfW; rx++) {
        Color c = hoodOrange;
        if (rx <= rowCx - halfW + 2 && ry < robeTopY + 4) {
          c = hoodPurpleShadow;
        } else if (rx >= rowCx + halfW - 2) {
          c = hoodPurpleShadow; // Purple back-robe shadow
        } else if ((rx - (faceCx)).abs() <= 1) {
          c = hoodRedTop; // Central vertical robe pleat
        } else if (rx < faceCx - 3) {
          c = hoodRedTop;
        }
        // Bright Gold Bottom Hem (last 2 rows of robe, with center split!)
        if (ry >= robeBotY - 1) {
          if (rx == faceCx) {
            c = goldShadow;
          } else if (rx >= rowCx + halfW - 2) {
            c = goldShadow;
          } else {
            c = goldBright;
          }
        }
        buf.setPx(rx, ry, c);
      }
    }

    // Gold Collar Brooch with Bright Emerald-Green Gem (exact match to Image 1!)
    final int broochX = faceCx - 2;
    final int broochY = robeTopY;
    buf.fillRect(broochX, broochY, 5, 4, goldBright);
    buf.fillRect(broochX, broochY + 3, 5, 1, goldMid);
    buf.fillRect(broochX + 1, broochY + 1, 3, 2, emeraldGem);

    // Gold-Cuffed Sleeves & Little Dark Void Hands (left & right)
    final int handWave =
        (isListen || isTyping || isFixing || isRoar) ? -2 + (tick % 3) : 0;
    // Left sleeve & hand
    buf.fillRect(cx - 9, robeTopY + 3 + handWave, 3, 2, goldBright);
    buf.fillRect(cx - 9, robeTopY + 5 + handWave, 3, 3, voidNavy);
    // Right sleeve & hand (gesturing toward the levitating grimoire!)
    buf.fillRect(cx + 4, robeTopY + 3 + handWave, 5, 2, goldBright);
    buf.fillRect(cx + 4, robeTopY + 5 + handWave, 5, 3, voidNavy);

    // --- C. LEVITATING GRAMMARLY GRIMOIRE & SELF-WRITING QUILL ---
    final int bookHover =
        (math.sin(tick * 0.45) * 1.6).round() + (isFixing ? -2 : 0);
    final int bookX = 38;
    final int bookY = 17 + bounceY + bookHover;
    buf.fillRect(bookX, bookY + 2, 12, 5, bookCover);
    buf.fillRect(bookX + 4, bookY + 3, 4, 5, goldBright);
    buf.fillRect(bookX + 1, bookY, 10, 4, parchment);
    // Animated glowing ink lines on pages
    final int inkTick = tick % 6;
    buf.fillRect(bookX + 2, bookY + 1, 3, 1, hoodPurpleShadow);
    buf.fillRect(bookX + 6, bookY + 1, (inkTick % 3) + 1, 1, emeraldGem);
    buf.fillRect(bookX + 2, bookY + 2, (inkTick % 4) + 1, 1, eyeCyanTop);

    // Enchanted Quill or Arcane Magnifying Lens inspecting the grimoire
    if (isReviewerMode) {
      final int lensX = bookX + 3 + ((tick ~/ 2) % 5);
      final int lensY = bookY - 2;
      buf.drawOvalFilled(lensX, lensY, 3, 3, goldBright);
      buf.drawOvalFilled(lensX, lensY, 2, 2, eyeCyanTop);
      buf.setPx(lensX - 1, lensY - 1, eyeWhiteBot);
      buf.drawLine(lensX + 2, lensY + 2, lensX + 5, lensY + 5, goldMid);
    } else {
      final int qx = (isListen || isTyping || isFixing || isCurious)
          ? (bookX + 2 + (tick % 7))
          : (bookX + 6);
      final int qy = bookY - 1 - ((isListen && tick % 2 == 0) ? 1 : 0);
      buf.setPx(qx, qy + 1, goldBright);
      buf.drawLine(qx, qy, qx + 4, qy - 5, quillCyan);
      buf.drawLine(qx + 1, qy - 1, qx + 5, qy - 5, eyeWhiteBot);
    }

    buf.applyPixelOutline(outline);
    _drawActivePropsAndParticles(
      buf,
      isReviewerMode ? 'review' : 'cultist',
      animState,
      tick,
      audioLevel,
    );
    return buf;
  }

  // =========================================================================
  // 2. TIER 2B: LUNATIC BEAK CULTIST (Terraria Style — Image 2 Reference)
  //    Royal cobalt-blue hooded robe with swept-back pointed hood tail, gold
  //    cowl & V-mantle trim, curved white plague-doctor beak mask, and
  //    wide wizard sleeves with gesturing hands!
  // =========================================================================
  static PixelBuffer _buildLunaticCultist(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy,
  ) {
    final buf = PixelBuffer(kGridW, kGridH);

    // Exact Indie-Game Palette matched to Reference Image 2
    const Color outline = Color(0xFF140C24);
    const Color blueDeep = Color(0xFF0E1D66);
    const Color blueRoyal = Color(0xFF1C3B9E);
    const Color blueCobalt = Color(0xFF2E5CE6);
    const Color goldBright = Color(0xFFFFF038);
    const Color goldMid = Color(0xFFD49B24);
    const Color goldDark = Color(0xFF9E6418);
    const Color maskWhite = Color(0xFFF8F8FF);
    const Color maskLavender = Color(0xFFD6CBE2);
    const Color maskShadow = Color(0xFFA391B5);
    const Color eyeVoid = Color(0xFF1A0E26);
    const Color eyeGlow = Color(0xFF00E5FF);

    final bool isWalk = animState == 'walk';
    final bool isSleep = animState == 'sleep';
    final bool isTyping = animState == 'typing';
    final bool isListen =
        animState == 'listen' || isTyping || animState == 'target_wait';
    final bool isFixing = animState == 'fixing' || animState == 'happy';
    final bool isRoar = animState == 'roar';

    final int bounceY = isSleep
        ? 2
        : (isWalk
            ? ((tick % 4 < 2) ? -2 : 0)
            : (isFixing
                ? ((tick % 4 < 2) ? -3 : 0)
                : ((tick % 10 < 5) ? 0 : 1)));

    final int cx = 25;
    final int topY = 5 + bounceY;

    // --- A. SWEPT-BACK ROYAL BLUE HOOD WITH POINTED TAIL (facing right by default) ---
    final int tailWave = (math.sin(tick * 0.4) * 1.2).round();
    for (int r = 0; r <= 12; r++) {
      final int y = topY + r;
      final int leftX = cx - 8 - (r <= 4 ? (4 - r) : 0) + (r ~/ 3);
      final int rightX = cx + 6 - (r > 8 ? (r - 8) : 0);
      for (int x = leftX; x <= rightX; x++) {
        Color c = blueRoyal;
        if (r <= 2 || x >= rightX - 2) c = blueCobalt;
        if (x <= leftX + 3 && r >= 4) c = blueDeep;
        // Gold top & front trim of hood
        if (r <= 1 && x >= cx - 2) c = goldBright;
        if (x >= rightX - 1 && r <= 10) {
          c = (r < 6) ? goldBright : goldMid;
        }
        buf.setPx(x, y, c);
      }
    }
    // Swept-back pointed hood tail extending to the left (x = cx - 14 .. cx - 8)
    for (int tx = 0; tx <= 6; tx++) {
      final int px = cx - 8 - tx;
      final int py = topY + 4 - (tx ~/ 2) + tailWave;
      buf.fillRect(px, py, 2, (4 - (tx ~/ 2)).clamp(1, 4), blueRoyal);
      buf.setPx(px, py, blueCobalt);
    }

    // --- B. ICONIC CURVED WHITE PLAGUE-DOCTOR BEAK MASK PROTRUDING FROM HOOD ---
    final int beakBaseX = cx + 5;
    final int beakBaseY = topY + 3;
    // Shadowed hood interior behind mask
    buf.fillRect(beakBaseX - 2, beakBaseY, 3, 9, eyeVoid);
    // Curved beak jutting out to the right (x = beakBaseX .. beakBaseX + 9)
    for (int bx = 0; bx <= 9; bx++) {
      final int byTop = beakBaseY + 1 + ((bx * bx) ~/ 14);
      final int byBot = beakBaseY + 7 + (bx ~/ 3) - (bx > 6 ? (bx - 6) : 0);
      for (int by = byTop; by <= byBot; by++) {
        Color c = maskWhite;
        if (by == byBot) c = maskShadow;
        if (by == byBot - 1 && bx < 6) c = maskLavender;
        buf.setPx(beakBaseX + bx, by, c);
      }
    }
    // Dark expressive eye socket on mask + glowing cyan pupil when active
    buf.fillRect(beakBaseX + 1, beakBaseY + 2, 2, 3, eyeVoid);
    if (!isSleep && (isListen || isFixing || isRoar)) {
      buf.setPx(beakBaseX + 2, beakBaseY + 3, eyeGlow);
    }

    // --- C. FLOWING ROYAL BLUE ROBE, V-SHAPED GOLD MANTLE & WIDE WIZARD SLEEVES ---
    final int robeTop = topY + 13;
    final int robeBot = topY + 28;
    final int stepSway = isWalk ? ((tick % 4 < 2) ? -1 : 1) : 0;

    for (int ry = robeTop; ry <= robeBot; ry++) {
      final double prog = (ry - robeTop) / 15.0;
      final int halfW = (6 + prog * 6.5).round();
      final int rCx = cx + (prog > 0.5 ? stepSway : 0);
      for (int rx = rCx - halfW; rx <= rCx + halfW; rx++) {
        Color c = blueRoyal;
        // 3-pleat shading across the flowing robe skirt
        if (rx < rCx - 3) {
          c = blueDeep;
        } else if (rx >= rCx + 1 && rx <= rCx + 5) {
          c = blueCobalt;
        } else if (rx > rCx + 6) {
          c = blueDeep;
        }
        // V-shaped Gold Mantle Collar
        final int vCollarY = robeTop + 1 + ((rx - (cx + 1)).abs() ~/ 2);
        if (ry == vCollarY && (rx - (cx + 1)).abs() <= 7) {
          c = (rx > cx) ? goldBright : goldMid;
        }
        // V-shaped Gold Waist Sash
        final int vSashY = robeTop + 7 + ((rx - (cx + 1)).abs() ~/ 2);
        if (ry == vSashY && (rx - (cx + 1)).abs() <= 6) {
          c = (rx > cx) ? goldBright : goldDark;
        }
        buf.setPx(rx, ry, c);
      }
    }

    // Wide Wizard Sleeves with Gold Cuffs & Pale Gesturing Hands
    final int castLift =
        (isListen || isTyping || isFixing || isRoar) ? -2 + (tick % 3) : 0;
    // Back/Left arm & gesturing hand
    buf.fillRect(cx - 10, robeTop + 4 + castLift, 4, 5, blueDeep);
    buf.fillRect(cx - 11, robeTop + 5 + castLift, 1, 4, goldMid);
    buf.fillRect(cx - 13, robeTop + 6 + castLift, 2, 3, maskLavender);
    // Front/Right arm & gesturing hand
    buf.fillRect(cx + 5, robeTop + 3 + castLift, 5, 6, blueCobalt);
    buf.fillRect(cx + 10, robeTop + 4 + castLift, 2, 5, goldBright);
    buf.fillRect(cx + 12, robeTop + 5 + castLift, 4, 3, maskWhite);
    buf.setPx(cx + 16, robeTop + 5 + castLift, maskWhite); // Pointing finger!

    // Floating Arcane Sigil / Scroll when dictating or fixing
    if (isListen || isTyping || isFixing || isRoar) {
      final int orbX = 46;
      final int orbY = 14 + bounceY + ((tick % 4 < 2) ? -1 : 1);
      buf.drawOvalFilled(orbX, orbY, 3, 3, goldBright);
      buf.drawOvalFilled(orbX, orbY, 2, 2, eyeGlow);
      buf.setPx(orbX, orbY, maskWhite);
    }

    buf.applyPixelOutline(outline);
    _drawActivePropsAndParticles(
        buf, 'cultist_lunar', animState, tick, audioLevel);
    return buf;
  }

  // =========================================================================
  // 3. TIER 3: APEX GREEN JURASSIC T-REX (56x40 Heavyweight Powerhouse)
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

    // Squash & stretch bounce
    final int bodyBob = isSleep
        ? 4
        : (isWalk
            ? ((tick % 4 < 2) ? -2 : 0)
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
      buf.fillRect(rightLegX, rightLegY + bodyBob, 4, 5, darkGreen);
      buf.fillRect(rightLegX + 1, rightLegY + 5 + bodyBob, 3, 3, darkGreen);
      buf.fillRect(rightLegX + 1, rightLegY + 7 + bodyBob, 5, 2, darkGreen);
      buf.setPx(rightLegX + 6, rightLegY + 8 + bodyBob, toothWhite);

      buf.drawOvalFilled(leftLegX + 1, leftLegY + 1 + bodyBob, 3, 3, midGreen);
      buf.setPx(leftLegX + 1, leftLegY + bodyBob, brightGreen);
      buf.fillRect(leftLegX, leftLegY + 3 + bodyBob, 4, 4, midGreen);
      buf.fillRect(leftLegX + 1, leftLegY + 6 + bodyBob, 3, 2, brightGreen);
      buf.fillRect(leftLegX, leftLegY + 7 + bodyBob, 6, 2, midGreen);
      buf.setPx(leftLegX + 6, leftLegY + 8 + bodyBob, toothWhite);
      buf.setPx(leftLegX + 4, leftLegY + 8 + bodyBob, toothWhite);
    } else {
      buf.drawOvalFilled(25, 29, 6, 3, darkGreen);
      buf.setPx(31, 30, toothWhite);
      buf.setPx(29, 30, toothWhite);
    }

    // 4. Articulated T-Rex Forearms
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
    buf.fillRect(44, headY + 2, 2, 1, darkGreen);

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

    if (!isSleep && (isRoar || (tick % 20 >= 16))) {
      final int puffOff = (tick % 20) - 16;
      buf.setPx(
          48 + puffOff, headY + 1 - (puffOff ~/ 2), const Color(0xBBFFFFFF));
      buf.setPx(49 + puffOff, headY - (puffOff ~/ 2), const Color(0x88E0F7FA));
    }

    for (int tx = 35; tx <= 46; tx += 2) {
      buf.setPx(tx, headY + 7, toothWhite);
      if (tx >= 39) buf.setPx(tx, headY + 8, toothWhite);
    }

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
  // 4. TIER 1: SKY PTERODACTYL (56x40 Lightweight Speed Flyer)
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

    final bool isFlapping = isListen || isFixing || isRoar || isCurious;
    final int hoverBob = isSleep
        ? 5
        : (isFlapping
            ? (math.sin(tick * 0.85) * 2.5).round() - 2
            : (isWalk
                ? ((tick % 4 < 2) ? -2 : 0)
                : (math.sin(tick * 0.35) * 1.2).round()));

    final int cx = 25;
    final int cy = 22 + hoverBob;

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

    final int tailWave = (math.sin(tick * 0.45) * 1.5).round();
    buf.drawLine(cx - 7, cy + 2, cx - 17, cy + 4 + tailWave, wingShadow);
    buf.drawOvalFilled(cx - 18, cy + 4 + tailWave, 3, 2, crestAmber);
    buf.setPx(cx - 18, cy + 4 + tailWave, crestGold);

    buf.drawOvalFilled(cx, cy, 7, 5, bodyAzure);
    buf.drawOvalFilled(cx + 1, cy - 1, 6, 4, wingSky);
    buf.drawOvalFilled(cx + 2, cy + 2, 5, 3, bellyCream);

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
    buf.setPx(wingElbowX, wingElbowY - 1, eyeWhite);
    buf.setPx(wingElbowX + 1, wingElbowY - 2, eyeWhite);

    final int step = isWalk ? (tick % 8) : 0;
    final int leftFootDx = (step < 4) ? -2 : 1;
    final int rightFootDx = (step < 4) ? 1 : -2;
    final int legTopY = cy + 4;
    if (!isSleep) {
      buf.fillRect(cx + 2 + rightFootDx, legTopY, 2, 6, wingShadow);
      buf.fillRect(cx + 2 + rightFootDx, legTopY + 5, 4, 2, crestAmber);
      buf.setPx(cx + 6 + rightFootDx, legTopY + 6, eyeWhite);
      buf.fillRect(cx - 2 + leftFootDx, legTopY, 2, 7, bodyAzure);
      buf.fillRect(cx - 2 + leftFootDx, legTopY + 6, 4, 2, beakGold);
      buf.setPx(cx + 2 + leftFootDx, legTopY + 7, eyeWhite);
    } else {
      buf.fillRect(cx - 1, cy + 4, 4, 3, beakGold);
    }

    final int headY = cy - 7 + (isCurious ? 2 : 0);
    final int headX = cx + 6;

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

    buf.fillRect(cx + 4, cy - 4, 4, 5, wingSky);
    buf.fillRect(headX - 1, headY, 7, 5, wingSky);
    buf.fillRect(headX, headY - 1, 5, 2, crestAmber);

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
  // 5. ACTIVE GAME-FEEL PROPS & PARTICLE EFFECTS
  // =========================================================================
  static void _drawActivePropsAndParticles(
    PixelBuffer buf,
    String creature,
    String animState,
    int tick,
    double audioLevel,
  ) {
    final bool isCultist = creature == 'cultist' ||
        creature == 'cultist_lunar' ||
        creature == 'review' ||
        creature == 'monster';

    // A. Snappy Game Footstep Dust Kick-Up during Walk
    if (animState == 'walk') {
      const Color dustLight = Color(0xDDFFF8E1);
      const Color dustMid = Color(0xAA90A4AE);
      final int puffPhase = tick % 6;
      final int dustX = 11 - puffPhase * 2;
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

    // C. Curious / Grazing Props (Orbiting Arcane Runes or Prehistoric Ferns)
    if (animState == 'curious') {
      if (isCultist) {
        const Color runeCol = Color(0xFFFFEE18);
        const Color runeCore = Color(0xFF00E84A);
        for (int r = 0; r < 3; r++) {
          final double ang = (tick * 0.28) + r * 2.09;
          final int rx = (24 + math.cos(ang) * 18).round();
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

    // D. Active Typing Props: Floating Holographic Pixel Keyboard
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

    // E. Listening Sonar Rings & RPG Emote Indicator
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

    // F. Grammar Fix / Spellcast / Roar Particle Starburst
    if (animState == 'fixing' || animState == 'happy' || animState == 'roar') {
      const Color starCyan = Color(0xFF00E5FF);
      const Color starGold = Color(0xFFFFEE18);
      const Color starEmerald = Color(0xFF00E84A);
      final List<List<int>> stars = [
        [8, 6 + (tick % 4)],
        [48, 5 + ((tick + 1) % 4)],
        [25, 2 + ((tick + 2) % 3)],
        [13, 4 + ((tick + 3) % 3)],
        [42, 10 + (tick % 3)],
      ];
      final List<Color> cols = [starCyan, starGold, starEmerald];
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

    // G. Ambient Floating Game Fireflies / Arcane Embers
    if (animState != 'sleep') {
      final Color moteCol = isCultist
          ? const Color(0xCCFFEE18)
          : (creature == 'trex'
              ? const Color(0xAA69F0AE)
              : const Color(0xAA80DEEA));
      for (int m = 0; m < 2; m++) {
        final double ang = tick * 0.14 + m * 3.14;
        final int mx = (25 + math.cos(ang) * 20).round();
        final int my = (16 + math.sin(ang * 1.3) * 9).round();
        if (buf.getPx(mx, my) == null) {
          buf.setPx(mx, my, moteCol);
        }
      }
    }
  }

  // =========================================================================
  // 6. LIVING PIXEL TERRAIN FLOOR GENERATOR (110x10 Grid on Top of Floor Box)
  // =========================================================================
  static PixelBuffer buildTerrainFloor({
    required String creature,
    required int tick,
    required bool isActive,
  }) {
    final buf = PixelBuffer(kFloorW, kFloorH);
    final bool isCultist = creature == 'cultist' ||
        creature == 'cultist_lunar' ||
        creature == 'review' ||
        creature == 'monster';

    if (isCultist) {
      const Color stoneDark = Color(0xFF1A1224);
      const Color stoneMid = Color(0xFF2D223B);
      const Color stoneHighlight = Color(0xFF4A3B5C);
      const Color mortar = Color(0xFF0E0814);
      const Color runeGlow = Color(0xFFFFEE18);
      const Color runeCyan = Color(0xFF00E5FF);
      const Color mossGreen = Color(0xFF00E84A);
      const Color waxCream = Color(0xFFFFF8E1);
      const Color flameGold = Color(0xFFFFEE18);
      const Color flameOrange = Color(0xFFFF6D00);

      buf.fillRect(0, 6, kFloorW, 4, stoneMid);
      buf.fillRect(0, 6, kFloorW, 1, stoneHighlight);
      buf.fillRect(0, 9, kFloorW, 1, stoneDark);

      for (int x = 0; x < kFloorW; x++) {
        if (x % 11 == 0) {
          buf.fillRect(x, 6, 1, 4, mortar);
        }
        if (x % 7 == 3) {
          buf.setPx(x, 7, stoneDark);
        }
        if (x % 19 == 5) {
          buf.setPx(x, 5, mossGreen);
          buf.setPx(x + 1, 6, mossGreen);
        }
        if (x % 16 == 8 && x > 10 && x < kFloorW - 10) {
          final bool pulse = ((tick + x) % 6 < 3) || isActive;
          final Color rCol =
              (x % 32 == 8) ? (pulse ? runeCyan : runeGlow) : runeGlow;
          buf.setPx(x, 7, rCol);
          buf.setPx(x + 1, 8, rCol);
          buf.setPx(x + 2, 7, rCol);
        }
      }

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
      const Color soilDark = Color(0xFF271911);
      const Color soilMid = Color(0xFF3E2723);
      const Color soilLight = Color(0xFF5D4037);
      const Color turfBase = Color(0xFF1B5E20);
      const Color grassMid = Color(0xFF2E7D32);
      const Color grassBright = Color(0xFF43A047);
      const Color grassNeon = Color(0xFF69F0AE);
      const Color flowerAmber = Color(0xFFFFD54F);
      const Color flowerCyan = Color(0xFF00E5FF);

      buf.fillRect(0, 7, kFloorW, 3, soilMid);
      buf.fillRect(0, 9, kFloorW, 1, soilDark);
      buf.fillRect(0, 5, kFloorW, 2, turfBase);

      final int windShift = ((tick ~/ 4) % 3) - 1;

      for (int x = 0; x < kFloorW; x++) {
        if (x % 4 == 0) buf.setPx(x, 7, turfBase);
        if (x % 7 == 0) buf.setPx(x, 8, soilLight);

        final int hash = (x * 37 + 13) % 7;
        final int bladeH = (hash % 4) + 1;
        final int tipSway = (bladeH >= 3) ? windShift : 0;

        for (int dy = 1; dy <= bladeH; dy++) {
          final int bx =
              (x + (dy == bladeH ? tipSway : 0)).clamp(0, kFloorW - 1);
          final int by = 5 - dy;
          Color c = grassMid;
          if (dy == bladeH) {
            c = (isActive && x % 5 == 0) ? grassNeon : grassBright;
          } else if (dy >= 2) {
            c = grassBright;
          }
          buf.setPx(bx, by, c);
        }

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
