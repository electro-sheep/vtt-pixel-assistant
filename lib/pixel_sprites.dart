import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Hand-Crafted Indie-Game Pixel-Art Sprite, Particle, Squash-Stretch & Terrain Engine
/// (56x40 Creature Grid + 110x10 Living Terrain Grid).
///
/// 4-Option Mode & Model Progression:
/// - Tier 0 ('review')            : Arcane Text Reviewer — Pure Screen-Text Review (No VTT, 0.0 GB VRAM)
/// - Tier 1 ('ptero' / 'stego')   : Sky Pterodactyl — Lightweight Speed (small.en, ~0.5 GB VRAM)
/// - Tier 2A ('cultist' / 'monster'): Ember Void Cultist (Enter the Gungeon style) — Grammarly Scribe (medium.en, ~1.5 GB VRAM)
/// - Tier 2B ('cultist_lunar')    : Lunatic Beak Cultist (Terraria style) — Grammarly Scribe (medium.en, ~1.5 GB VRAM)
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
        final double dx = (px - cx) / (rx + 0.28);
        final double dy = (py - cy) / (ry + 0.28);
        if (dx * dx + dy * dy <= 1.0) {
          setPx(px, py, c);
        }
      }
    }
  }

  /// Applies a selective hue-aware game outline around all sprite pixels so edges
  /// feel hand-anti-aliased rather than flat harsh black.
  void applyPixelOutline(Color baseOutlineColor) {
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
        Color? neighborCol;
        for (final d in dirs) {
          final int nx = x + d[0];
          final int ny = y + d[1];
          if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
            final Color? c = copy[ny * width + nx];
            if (c != null) {
              neighborCol = c;
              break;
            }
          }
        }
        if (neighborCol != null) {
          // Tint outline slightly toward the neighboring pixel's hue & top-light
          final double topBias = (y < height * 0.42) ? 0.22 : 0.12;
          pixels[y * width + x] =
              Color.lerp(baseOutlineColor, neighborCol, topBias);
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

  // Hand-tuned 12-frame keyframe curves for organic human-drawn motion
  static const List<int> _kWalkBob12 = [
    0, -1, -2, -2, -1, 0, 1, 0, -1, -2, -2, -1
  ];
  static const List<int> _kIdleBreath16 = [
    0, 0, 0, 0, -1, -1, -1, -1, -1, 0, 0, 0, 1, 1, 0, 0
  ];
  static const List<int> _kHappyHop8 = [0, -2, -3, -2, 0, 1, 0, -1];

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

  /// Smooth 5-stage eye blink state: 0 = open, 1 = half-lid, 2 = closed
  static int _eyeBlinkStage(int tick, int period) {
    final int p = tick % period;
    // Occasional natural double-blink every 3rd cycle
    if (p == period - 4 || p == period - 1) return 1;
    if (p == period - 3 || p == period - 2) return 2;
    return 0;
  }

  // =========================================================================
  // 1. TIER 2A & TIER 0: EMBER VOID CULTIST (Enter the Gungeon Chibi Scribe)
  //    Hand-crafted vermilion/orange hood with delayed cloth-tip physics,
  //    purple shadow fold, bright gold cowl border, circular dark-navy void
  //    face, expressive 2-tone eyes (blink / happy ^ ^ / curious tilt),
  //    emerald brooch, alternating golden-booted walk stride, and a figure-8
  //    levitating grimoire with animated flipping pages!
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

    // Rich Indie-Game Palette matched to Reference Image 1
    const Color outline = Color(0xFF160720);
    const Color hoodHighlight = Color(0xFFFF8A3D);
    const Color hoodOrange = Color(0xFFE5641A);
    const Color hoodRedTop = Color(0xFFD43214);
    const Color hoodPurpleShadow = Color(0xFF7B105E);
    const Color hoodDeepPlum = Color(0xFF4A083B);
    const Color goldSpecular = Color(0xFFFFF9A6);
    const Color goldBright = Color(0xFFFFEE18);
    const Color goldMid = Color(0xFFE6B812);
    const Color goldShadow = Color(0xFFA87B12);
    const Color voidNavy = Color(0xFF040828);
    const Color voidEdge = Color(0xFF0A1445);
    const Color eyeCyanTop = Color(0xFF18A0F8);
    const Color eyeWhiteBot = Color(0xFFFFFFFF);
    const Color emeraldGem = Color(0xFF00E84A);
    const Color emeraldGlow = Color(0xFF80FFAC);
    const Color parchment = Color(0xFFFFF8E1);
    const Color parchmentShade = Color(0xFFE6D5B8);
    const Color bookCover = Color(0xFF5D2E1E);
    const Color quillCyan = Color(0xFF80DEEA);
    const Color bootDark = Color(0xFF281236);

    final bool isWalk = animState == 'walk';
    final bool isSleep = animState == 'sleep';
    final bool isCurious = animState == 'curious';
    final bool isTyping = animState == 'typing';
    final bool isListen =
        animState == 'listen' || isTyping || animState == 'target_wait';
    final bool isFixing = animState == 'fixing' || animState == 'happy';
    final bool isRoar = animState == 'roar';

    // Keyframed body bob + delayed secondary cloth motion (2 ticks behind!)
    final int bounceY = isSleep
        ? 3
        : (isWalk
            ? _kWalkBob12[tick % 12]
            : (isFixing || isRoar
                ? _kHappyHop8[tick % 8]
                : _kIdleBreath16[tick % 16]));
    final int delayedBounceY = isSleep
        ? 3
        : (isWalk
            ? _kWalkBob12[(tick + 10) % 12]
            : _kIdleBreath16[(tick + 13) % 16]);
    final int hoodTipLagX = isWalk ? ((tick % 6 < 3) ? 1 : 0) : 0;

    final int cx = 23;
    final int hoodY = 5 + bounceY;

    // --- A. ROUNDED CHIBI HOOD & COWL WITH DELAYED CLOTH TIP ---
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
      final int y = hoodY + r + (r <= 2 ? (delayedBounceY - bounceY) : 0);
      final int lag = (r <= 3) ? hoodTipLagX : 0;
      final int xMin = hoodBounds[r][0] + lag;
      final int xMax = hoodBounds[r][1] + lag;
      for (int dx = xMin; dx <= xMax; dx++) {
        Color c = hoodOrange;
        if (r == 0 && dx >= -3 && dx <= 0) {
          c = hoodHighlight; // Top-left sun highlight
        } else if (r <= 1) {
          c = (dx >= 2) ? hoodPurpleShadow : hoodRedTop;
        } else if (dx >= xMax - 1 && r >= 4 && r <= 12) {
          c = hoodDeepPlum;
        } else if (dx >= xMax - 3) {
          c = hoodPurpleShadow;
        } else if (dx >= xMax - 5 && r >= 3 && r <= 10) {
          c = hoodRedTop;
        } else if (r <= 3) {
          c = (dx <= xMin + 2) ? hoodHighlight : hoodRedTop;
        }
        buf.setPx(cx + dx, y, c);
      }
    }

    // Thick Golden-Yellow Cowl Ring Framing the Void Face
    final int curiousTiltX = isCurious ? 1 : 0;
    final int faceCx = cx - 1 + curiousTiltX;
    final int faceCy = hoodY + 9 + (isSleep ? 1 : 0);
    buf.drawOvalFilled(faceCx, faceCy, 8, 6, goldBright);
    for (int py = faceCy - 6; py <= faceCy + 6; py++) {
      for (int px = faceCx - 8; px <= faceCx + 8; px++) {
        if (buf.getPx(px, py) == goldBright) {
          if (py <= faceCy - 4 && px <= faceCx) {
            buf.setPx(px, py, goldSpecular);
          } else if (py >= faceCy + 3) {
            buf.setPx(px, py, goldShadow);
          } else if (py >= faceCy + 1) {
            buf.setPx(px, py, goldMid);
          }
        }
      }
    }

    // Circular Dark-Navy Void Face Inside the Cowl with subtle inner rim
    buf.drawOvalFilled(faceCx, faceCy + 1, 6, 5, voidEdge);
    buf.drawOvalFilled(faceCx, faceCy + 1, 5, 4, voidNavy);

    // Expressive Two-Tone Pixel Eyes (Blink, Happy ^ ^, Curious Squint, Cursor Track)
    final int blinkStage = _eyeBlinkStage(tick, 44);
    final int lookShiftX = (lookDx >= 0.22) ? 1 : (lookDx <= -0.22 ? -1 : 0);
    final int lookShiftY = (lookDy > 0.30) ? 1 : (lookDy < -0.35 ? -1 : 0);
    final int eyeLeftX = faceCx - 4 + lookShiftX;
    final int eyeRightX = faceCx + 2 + lookShiftX;
    final int eyeTopY = faceCy - 1 + lookShiftY;

    if (isSleep || (!isListen && !isFixing && !isRoar && blinkStage == 2)) {
      // Cozy closed cyan eye arcs
      buf.fillRect(eyeLeftX, eyeTopY + 2, 2, 1, eyeCyanTop);
      buf.fillRect(eyeRightX, eyeTopY + 2, 2, 1, eyeCyanTop);
    } else if (isFixing || isRoar) {
      // Joyful glowing happy eye arches (^ ^) with golden sparkle!
      buf.setPx(eyeLeftX, eyeTopY + 1, goldBright);
      buf.setPx(eyeLeftX + 1, eyeTopY, eyeWhiteBot);
      buf.setPx(eyeLeftX + 2, eyeTopY + 1, eyeCyanTop);
      buf.setPx(eyeRightX, eyeTopY + 1, eyeCyanTop);
      buf.setPx(eyeRightX + 1, eyeTopY, eyeWhiteBot);
      buf.setPx(eyeRightX + 2, eyeTopY + 1, goldBright);
    } else if (isCurious) {
      // Left eye normal, right eye raised inquisitively!
      buf.fillRect(eyeLeftX, eyeTopY + 1, 2, 1, eyeCyanTop);
      buf.fillRect(eyeLeftX, eyeTopY + 2, 2, 1, eyeWhiteBot);
      buf.fillRect(eyeRightX, eyeTopY - 1, 2, 1, goldBright);
      buf.fillRect(eyeRightX, eyeTopY, 2, 2, eyeWhiteBot);
    } else if (blinkStage == 1) {
      // Half-lid smooth transition frame
      buf.fillRect(eyeLeftX, eyeTopY + 1, 2, 1, eyeCyanTop);
      buf.fillRect(eyeLeftX, eyeTopY + 2, 2, 1, eyeWhiteBot);
      buf.fillRect(eyeRightX, eyeTopY + 1, 2, 1, eyeCyanTop);
      buf.fillRect(eyeRightX, eyeTopY + 2, 2, 1, eyeWhiteBot);
    } else {
      // Classic Gungeon Cultist 2x3 two-tone eyes (Cyan top, White bottom)
      buf.fillRect(eyeLeftX, eyeTopY, 2, 1, eyeCyanTop);
      buf.fillRect(eyeLeftX, eyeTopY + 1, 2, 2, eyeWhiteBot);
      buf.fillRect(eyeRightX, eyeTopY, 2, 1, eyeCyanTop);
      buf.fillRect(eyeRightX, eyeTopY + 1, 2, 2, eyeWhiteBot);
    }

    // --- B. ROBED BODY, PULSING EMERALD CLASP, RIPPLING GOLD HEM & WALKING BOOTS ---
    final int robeTopY = hoodY + 15;
    final int robeBotY = hoodY + 26;
    final double clothPhase = tick * 0.52;

    for (int ry = robeTopY; ry <= robeBotY; ry++) {
      final double prog = (ry - robeTopY) / 11.0;
      final int halfW = (7 + prog * 3.8).round();
      final int clothRipple =
          (math.sin(clothPhase - prog * 2.2) * (isWalk ? 1.4 : 0.6)).round();
      final int rowCx = cx + (prog > 0.45 ? clothRipple : 0);

      for (int rx = rowCx - halfW; rx <= rowCx + halfW; rx++) {
        Color c = hoodOrange;
        if (rx <= rowCx - halfW + 1 && ry >= robeTopY + 3) {
          c = hoodHighlight; // Warm rim light from left
        } else if (rx <= rowCx - halfW + 2 && ry < robeTopY + 4) {
          c = hoodPurpleShadow;
        } else if (rx >= rowCx + halfW - 1) {
          c = hoodDeepPlum;
        } else if (rx >= rowCx + halfW - 3) {
          c = hoodPurpleShadow;
        } else if ((rx - faceCx).abs() <= 1) {
          c = hoodRedTop; // Central vertical robe pleat
        } else if (rx < faceCx - 3) {
          c = hoodRedTop;
        }
        // Rippling Bright Gold Bottom Hem with central split
        if (ry >= robeBotY - 1) {
          if (rx == faceCx + (clothRipple ~/ 2)) {
            c = goldShadow;
          } else if (rx >= rowCx + halfW - 2) {
            c = goldShadow;
          } else if (ry == robeBotY - 1 && rx <= faceCx - 2) {
            c = goldSpecular;
          } else {
            c = goldBright;
          }
        }
        buf.setPx(rx, ry, c);
      }
    }

    // Alternating Little Boots Peeking Under the Gold Hem During Walk!
    if (isWalk && !isSleep) {
      final int stride = tick % 12;
      final int leftLift = (stride < 6) ? -1 : 0;
      final int rightLift = (stride >= 6) ? -1 : 0;
      final int leftDx = ((math.sin(stride * math.pi / 6) * 2.0)).round();
      final int rightDx = -leftDx;
      buf.fillRect(faceCx - 5 + leftDx, robeBotY + 1 + leftLift, 3, 2, bootDark);
      buf.setPx(faceCx - 5 + leftDx, robeBotY + 1 + leftLift, goldMid);
      buf.fillRect(faceCx + 2 + rightDx, robeBotY + 1 + rightLift, 3, 2, bootDark);
      buf.setPx(faceCx + 2 + rightDx, robeBotY + 1 + rightLift, goldMid);
    }

    // Gold Collar Brooch with Pulsing Emerald-Green Gem
    final int broochX = faceCx - 2;
    final int broochY = robeTopY;
    final bool gemPulse = (tick % 8 < 4) || isListen || isFixing;
    buf.fillRect(broochX, broochY, 5, 4, goldBright);
    buf.fillRect(broochX, broochY + 3, 5, 1, goldMid);
    buf.fillRect(broochX + 1, broochY + 1, 3, 2, emeraldGem);
    if (gemPulse) {
      buf.setPx(broochX + 1, broochY + 1, emeraldGlow);
    }

    // Independent Floating Gold-Cuffed Sleeves & Expressive Void Hands
    final int leftHandDy = (isFixing || isRoar)
        ? -3 + (tick % 3)
        : (math.sin(tick * 0.38) * 1.4).round();
    final int rightHandDy = (isListen || isTyping || isFixing || isRoar)
        ? -3 + ((tick + 1) % 3)
        : (math.cos(tick * 0.38) * 1.4).round();

    // Left sleeve & hand
    buf.fillRect(cx - 10, robeTopY + 3 + leftHandDy, 3, 2, goldBright);
    buf.fillRect(cx - 10, robeTopY + 5 + leftHandDy, 3, 3, voidNavy);
    // Right sleeve & hand gesturing toward the grimoire
    buf.fillRect(cx + 5, robeTopY + 2 + rightHandDy, 5, 2, goldBright);
    buf.fillRect(cx + 5, robeTopY + 4 + rightHandDy, 5, 3, voidNavy);

    // --- C. FIGURE-8 LEVITATING GRIMOIRE WITH FLIPPING PAGES & QUILL/LENS ---
    final int bookDx = (math.cos(tick * 0.26) * 1.3).round();
    final int bookDy =
        (math.sin(tick * 0.52 - 0.7) * 1.8).round() + (isFixing ? -2 : 0);
    final int bookX = 37 + bookDx;
    final int bookY = 16 + bounceY + bookDy;

    // Dangling red & gold bookmark ribbon under the grimoire spine
    final int ribbonSway = (math.sin(tick * 0.48 - 1.2) * 1.5).round();
    buf.setPx(bookX + 5, bookY + 7, hoodRedTop);
    buf.setPx(bookX + 5 + ribbonSway, bookY + 8, hoodRedTop);
    buf.setPx(bookX + 5 + ribbonSway, bookY + 9, goldBright);

    // Leather cover, golden spine clasp & open parchment pages
    buf.fillRect(bookX, bookY + 2, 13, 5, bookCover);
    buf.fillRect(bookX + 5, bookY + 3, 3, 5, goldBright);
    buf.fillRect(bookX + 1, bookY, 11, 4, parchment);
    buf.fillRect(bookX + 6, bookY, 1, 4, parchmentShade); // Page center crease

    // Animated page-turning arc when active!
    if ((isListen || isTyping || isFixing) && (tick % 10 < 3)) {
      final int flipStage = tick % 10;
      final int flipX = bookX + 9 - flipStage * 3;
      buf.drawLine(bookX + 6, bookY + 2, flipX, bookY - 2, parchment);
      buf.setPx(flipX, bookY - 2, goldSpecular);
    }

    // Animated glowing rune lines being inscribed on the pages
    final int inkTick = tick % 8;
    buf.fillRect(bookX + 2, bookY + 1, 3, 1, hoodPurpleShadow);
    buf.fillRect(bookX + 7, bookY + 1, (inkTick % 4) + 1, 1, emeraldGem);
    buf.fillRect(bookX + 2, bookY + 2, ((inkTick + 2) % 3) + 1, 1, eyeCyanTop);

    // Enchanted Quill or Arcane Magnifying Lens
    if (isReviewerMode) {
      final int scanOffset = (math.sin(tick * 0.45) * 2.5).round();
      final int lensX = bookX + 5 + scanOffset;
      final int lensY = bookY - 3;
      // Soft inspection light beam onto book
      buf.setPx(lensX, lensY + 4, const Color(0x8880DEEA));
      buf.setPx(lensX - 1, lensY + 4, const Color(0x6680DEEA));
      // Golden Magnifying Glass Frame & Glinting Crystal Lens
      buf.drawOvalFilled(lensX, lensY, 4, 4, goldBright);
      buf.drawOvalFilled(lensX, lensY, 2, 2, eyeCyanTop);
      buf.setPx(lensX - 1, lensY - 1, eyeWhiteBot);
      buf.drawLine(lensX + 3, lensY + 3, lensX + 6, lensY + 6, goldMid);
    } else {
      final int scribbleX = (isListen || isTyping || isFixing || isCurious)
          ? (bookX + 2 + ((math.sin(tick * 0.85) + 1.0) * 3.5).round())
          : (bookX + 7);
      final int scribbleY =
          bookY - 1 - ((isListen || isTyping) && (tick % 2 == 0) ? 1 : 0);
      buf.setPx(scribbleX, scribbleY + 1, goldBright); // Gold nib
      buf.drawLine(
          scribbleX, scribbleY, scribbleX + 4, scribbleY - 5, quillCyan);
      buf.drawLine(scribbleX + 1, scribbleY - 1, scribbleX + 5, scribbleY - 5,
          eyeWhiteBot);
      // Tiny ink sparkle popping off the nib when writing
      if ((isListen || isTyping || isFixing) && tick % 3 == 0) {
        buf.setPx(scribbleX - 1, scribbleY - 2, goldSpecular);
      }
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
  // 2. TIER 2B: LUNATIC BEAK CULTIST (Terraria Royal Blue Plague-Mask Scribe)
  //    Swept-back cobalt hood with 4-segment cloth-whip tail, curved white
  //    plague-doctor beak mask with lavender bevels & glowing crescent eye,
  //    V-shaped gold mantle, billowing wizard sleeves, and rotating Arcane Seal!
  // =========================================================================
  static PixelBuffer _buildLunaticCultist(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy,
  ) {
    final buf = PixelBuffer(kGridW, kGridH);

    const Color outline = Color(0xFF100A20);
    const Color blueAbyss = Color(0xFF091347);
    const Color blueDeep = Color(0xFF0E1D66);
    const Color blueRoyal = Color(0xFF1C3B9E);
    const Color blueCobalt = Color(0xFF2E5CE6);
    const Color blueHighlight = Color(0xFF5C8AFF);
    const Color goldSpecular = Color(0xFFFFF9A6);
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
    final bool isCurious = animState == 'curious';
    final bool isTyping = animState == 'typing';
    final bool isListen =
        animState == 'listen' || isTyping || animState == 'target_wait';
    final bool isFixing = animState == 'fixing' || animState == 'happy';
    final bool isRoar = animState == 'roar';

    final int bounceY = isSleep
        ? 3
        : (isWalk
            ? _kWalkBob12[tick % 12]
            : (isFixing || isRoar
                ? _kHappyHop8[tick % 8]
                : _kIdleBreath16[tick % 16]));

    final int cx = 25;
    final int topY = 5 + bounceY;

    // --- A. SWEPT-BACK ROYAL BLUE HOOD WITH 4-SEGMENT WHIP TAIL ---
    for (int r = 0; r <= 12; r++) {
      final int y = topY + r;
      final int leftX = cx - 8 - (r <= 4 ? (4 - r) : 0) + (r ~/ 3);
      final int rightX = cx + 6 - (r > 8 ? (r - 8) : 0);
      for (int x = leftX; x <= rightX; x++) {
        Color c = blueRoyal;
        if (r == 0 && x >= cx - 3 && x <= cx + 2) {
          c = blueHighlight;
        } else if (r <= 2 || x >= rightX - 2) {
          c = blueCobalt;
        }
        if (x <= leftX + 3 && r >= 4) c = blueDeep;
        if (r <= 1 && x >= cx - 2) {
          c = (x == cx) ? goldSpecular : goldBright;
        }
        if (x >= rightX - 1 && r <= 10) {
          c = (r < 5) ? goldBright : goldMid;
        }
        buf.setPx(x, y, c);
      }
    }

    // 4-Segment Phase-Delayed Hood Tail Whip Wave (x = cx - 15 .. cx - 8)
    for (int tx = 0; tx <= 7; tx++) {
      final int px = cx - 8 - tx;
      final int segWave =
          (math.sin(tick * 0.48 - tx * 0.45) * 1.6).round();
      final int py = topY + 4 - (tx ~/ 2) + segWave;
      final int h = (4 - (tx ~/ 2)).clamp(1, 4);
      buf.fillRect(px, py, 2, h, blueRoyal);
      buf.setPx(px, py, (tx <= 3) ? blueHighlight : blueCobalt);
      if (h >= 2) buf.setPx(px, py + h - 1, blueDeep);
    }

    // --- B. ARTICULATED CURVED WHITE PLAGUE-DOCTOR BEAK MASK ---
    final int maskNod = isSleep
        ? 1
        : (isCurious
            ? -1
            : (isListen ? ((audioLevel * 1.8).round().clamp(0, 1)) : 0));
    final int beakBaseX = cx + 5;
    final int beakBaseY = topY + 3 + maskNod;

    buf.fillRect(beakBaseX - 2, beakBaseY, 3, 9, eyeVoid);
    for (int bx = 0; bx <= 9; bx++) {
      final int byTop = beakBaseY + 1 + ((bx * bx) ~/ 14);
      final int byBot = beakBaseY + 7 + (bx ~/ 3) - (bx > 6 ? (bx - 6) : 0);
      for (int by = byTop; by <= byBot; by++) {
        Color c = maskWhite;
        if (by == byBot) c = maskShadow;
        if (by == byBot - 1 && bx < 7) c = maskLavender;
        buf.setPx(beakBaseX + bx, by, c);
      }
    }
    // Expressive eye socket on mask + glowing cyan/gold pupil
    buf.fillRect(beakBaseX + 1, beakBaseY + 2, 2, 3, eyeVoid);
    if (isFixing || isRoar) {
      buf.setPx(beakBaseX + 1, beakBaseY + 2, goldBright);
      buf.setPx(beakBaseX + 2, beakBaseY + 3, eyeGlow);
    } else if (!isSleep && _eyeBlinkStage(tick, 40) < 2) {
      buf.setPx(
        beakBaseX + 2,
        beakBaseY + 3 + (lookDy > 0.3 ? 1 : 0),
        eyeGlow,
      );
    }

    // --- C. FLOWING 3-PLEAT ROYAL BLUE ROBE, V-MANTLE & BILLOWING SLEEVES ---
    final int robeTop = topY + 13;
    final int robeBot = topY + 28;
    final double clothPhase = tick * 0.50;

    for (int ry = robeTop; ry <= robeBot; ry++) {
      final double prog = (ry - robeTop) / 15.0;
      final int halfW = (6 + prog * 6.8).round();
      final int sway =
          (math.sin(clothPhase - prog * 2.4) * (isWalk ? 1.5 : 0.7)).round();
      final int rCx = cx + (prog > 0.4 ? sway : 0);
      for (int rx = rCx - halfW; rx <= rCx + halfW; rx++) {
        Color c = blueRoyal;
        if (rx <= rCx - halfW + 1) {
          c = blueAbyss;
        } else if (rx < rCx - 3) {
          c = blueDeep;
        } else if (rx >= rCx + 1 && rx <= rCx + 5) {
          c = (rx == rCx + 3 && prog > 0.3) ? blueHighlight : blueCobalt;
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

    // Independent Figure-8 Spell-Weaving Sleeves & Pale Gesturing Hands
    final int backArmDy = (isListen || isTyping || isFixing || isRoar)
        ? -2 + (tick % 3)
        : (math.sin(tick * 0.36) * 1.3).round();
    final int frontArmDy = (isListen || isTyping || isFixing || isRoar)
        ? -3 + ((tick + 2) % 3)
        : (math.cos(tick * 0.36) * 1.5).round();

    // Back/Left arm & gesturing hand
    buf.fillRect(cx - 10, robeTop + 4 + backArmDy, 4, 5, blueDeep);
    buf.fillRect(cx - 11, robeTop + 5 + backArmDy, 1, 4, goldMid);
    buf.fillRect(cx - 13, robeTop + 6 + backArmDy, 2, 3, maskLavender);

    // Front/Right arm & pointing spellcaster hand
    buf.fillRect(cx + 5, robeTop + 3 + frontArmDy, 5, 6, blueCobalt);
    buf.fillRect(cx + 10, robeTop + 4 + frontArmDy, 2, 5, goldBright);
    buf.fillRect(cx + 12, robeTop + 5 + frontArmDy, 4, 3, maskWhite);
    buf.setPx(cx + 16, robeTop + 5 + frontArmDy, maskWhite);

    // Rotating Celestial Arcane Mandala / Orb near the spellcasting hand!
    final int orbX = 46;
    final int orbY = 14 + bounceY + (math.sin(tick * 0.45) * 1.5).round();
    if (isListen || isTyping || isFixing || isRoar || isCurious) {
      buf.drawOvalFilled(orbX, orbY, 3, 3, goldBright);
      buf.drawOvalFilled(orbX, orbY, 2, 2, eyeGlow);
      buf.setPx(orbX, orbY, maskWhite);
      // 4 orbiting satellite rune points
      for (int p = 0; p < 4; p++) {
        final double a = tick * 0.45 + p * (math.pi / 2);
        final int sx = orbX + (math.cos(a) * 5.2).round();
        final int sy = orbY + (math.sin(a) * 5.2).round();
        buf.setPx(sx, sy, (p % 2 == 0) ? goldSpecular : eyeGlow);
      }
    } else if (!isSleep) {
      // Subtle idle arcane mote hovering at fingertip
      buf.setPx(orbX, orbY, eyeGlow);
      buf.setPx(orbX, orbY - 1, goldBright);
    }

    buf.applyPixelOutline(outline);
    _drawActivePropsAndParticles(
        buf, 'cultist_lunar', animState, tick, audioLevel);
    return buf;
  }

  // =========================================================================
  // 3. TIER 3: APEX GREEN JURASSIC T-REX (56x40 Heavyweight Powerhouse)
  //    12-frame articulated dinosaur stride, 18-segment S-curve whip tail,
  //    breathing ribcage, expressive brow ridge, wavy tongue & nostril steam!
  // =========================================================================
  static PixelBuffer _buildGreenTrex(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy,
  ) {
    final buf = PixelBuffer(kGridW, kGridH);

    const Color outline = Color(0xFF08160A);
    const Color deepShadowGreen = Color(0xFF124116);
    const Color darkGreen = Color(0xFF1B5E20);
    const Color midGreen = Color(0xFF2E7D32);
    const Color brightGreen = Color(0xFF43A047);
    const Color limeScale = Color(0xFF81C784);
    const Color specularScale = Color(0xFFB9F6CA);
    const Color bellyCream = Color(0xFFDCEDC8);
    const Color bellyShadow = Color(0xFFAED581);
    const Color eyeGold = Color(0xFFFFD54F);
    const Color pupilBlack = Color(0xFF111111);
    const Color toothWhite = Color(0xFFFFFFFF);
    const Color tongueRed = Color(0xFFE53935);
    const Color tonguePink = Color(0xFFFF8A80);

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
            ? _kWalkBob12[tick % 12]
            : (isFixing || isRoar
                ? _kHappyHop8[tick % 8]
                : _kIdleBreath16[tick % 16]));

    int jawOpen = 0;
    if (isRoar) {
      jawOpen = 5;
    } else if (isListen) {
      jawOpen = (1 + (audioLevel * 4.5).round()).clamp(1, 4);
      if (isTyping && tick % 2 == 0 && jawOpen < 2) jawOpen = 2;
    } else if (isFixing) {
      jawOpen = (tick % 4 < 2) ? 3 : 1;
    }

    // 1. 18-Segment Articulated Muscular Tail with Travelling S-Curve Wave (x=2..20)
    final double tailPhase = tick * (isFixing || isListen ? 0.65 : 0.42);
    for (int tx = 2; tx <= 20; tx++) {
      final double progress = (20 - tx) / 18.0;
      final int sway = isSleep
          ? 2
          : (math.sin(tailPhase - progress * 2.8) *
                      (isWalk || isFixing ? 2.6 : 1.5) +
                  math.cos(tailPhase * 0.5 - progress * 4.2) * 0.7)
              .round();
      final int thick = (1 + (1.0 - progress) * 4.6).round();
      final int cy = 21 + bodyBob + sway - (progress * 2).round();
      for (int dy = -thick; dy <= thick; dy++) {
        Color col = midGreen;
        if (dy == -thick) col = brightGreen;
        if (dy >= thick - 1) col = bellyShadow;
        if (dy == -thick && tx % 3 == 0) {
          col = (tx % 6 == 0) ? specularScale : limeScale;
        }
        if (dy == 0 && (tx + cy) % 4 == 0) col = darkGreen;
        buf.setPx(tx, cy + dy, col);
      }
    }

    // 2. Far/Back Leg (drawn behind torso for true 3D depth separation!)
    final int legCycle = tick % 12;
    const List<int> strideDx = [-3, -2, -1, 0, 1, 2, 3, 2, 1, 0, -1, -2];
    const List<int> strideDy = [0, -1, -2, -3, -2, -1, 0, 0, 0, 0, 0, -1];

    final int backLegX = 28 + (isWalk ? strideDx[(legCycle + 6) % 12] : 0);
    final int backLegY = 27 + (isWalk ? strideDy[(legCycle + 6) % 12] : 0);
    if (!isSleep) {
      buf.fillRect(backLegX, backLegY + bodyBob, 4, 5, deepShadowGreen);
      buf.fillRect(backLegX + 1, backLegY + 5 + bodyBob, 3, 3, deepShadowGreen);
      buf.fillRect(backLegX + 1, backLegY + 7 + bodyBob, 5, 2, darkGreen);
      buf.setPx(backLegX + 6, backLegY + 8 + bodyBob, toothWhite);
    }

    // 3. Muscular Torso, Dithered Scales & Breathing Ribcage (x=18..34, y=14..27)
    final int breathExpand = (tick % 16 >= 4 && tick % 16 <= 10) ? 1 : 0;
    buf.drawOvalFilled(26, 21 + bodyBob, 9, 6 + breathExpand, midGreen);
    buf.drawOvalFilled(25, 19 + bodyBob, 8, 4, brightGreen);
    buf.drawOvalFilled(28, 24 + bodyBob, 6, 3, bellyCream);
    for (int bx = 22; bx <= 32; bx += 2) {
      buf.setPx(bx, 25 + bodyBob, bellyShadow);
      if (bx % 4 == 0) buf.setPx(bx + 1, 23 + bodyBob, bellyShadow);
    }
    for (int sx = 18; sx <= 31; sx += 2) {
      buf.setPx(sx, 14 + bodyBob, (sx % 4 == 0) ? specularScale : limeScale);
      buf.setPx(sx, 15 + bodyBob, limeScale);
      buf.setPx(sx + 1, 16 + bodyBob, brightGreen);
      if (sx % 4 == 0) {
        buf.setPx(sx + 1, 19 + bodyBob, limeScale);
        buf.setPx(sx, 21 + bodyBob, darkGreen);
      }
    }

    // 4. Near/Foreground Hind Leg with Muscular Thigh, Knee & 3 Claws
    final int frontLegX = 22 + (isWalk ? strideDx[legCycle] : 0);
    final int frontLegY = 27 + (isWalk ? strideDy[legCycle] : 0);
    if (!isSleep) {
      buf.drawOvalFilled(22, 21 + bodyBob, 4, 4, darkGreen);
      buf.drawOvalFilled(
          frontLegX + 1, frontLegY + 1 + bodyBob, 3, 3, midGreen);
      buf.setPx(frontLegX + 1, frontLegY + bodyBob, brightGreen);
      buf.fillRect(frontLegX, frontLegY + 3 + bodyBob, 4, 4, midGreen);
      buf.fillRect(frontLegX + 1, frontLegY + 6 + bodyBob, 3, 2, brightGreen);
      buf.fillRect(frontLegX, frontLegY + 7 + bodyBob, 6, 2, midGreen);
      buf.setPx(frontLegX + 6, frontLegY + 8 + bodyBob, toothWhite);
      buf.setPx(frontLegX + 4, frontLegY + 8 + bodyBob, toothWhite);
    } else {
      buf.drawOvalFilled(25, 29, 6, 3, darkGreen);
      buf.setPx(31, 30, toothWhite);
      buf.setPx(29, 30, toothWhite);
    }

    // 5. Playful Articulated T-Rex Forearms
    final int armTap = (isTyping || isListen || isFixing)
        ? ((tick % 2 == 0) ? -1 : 1)
        : ((tick % 16 < 8) ? 0 : 1);
    buf.fillRect(32, 20 + bodyBob, 4, 2, brightGreen);
    buf.fillRect(35, 21 + bodyBob + armTap, 3, 2, midGreen);
    buf.setPx(38, 21 + bodyBob + armTap, toothWhite);
    buf.setPx(38, 22 + bodyBob + armTap, toothWhite);

    // 6. Phase-Delayed Counter-Balanced T-Rex Skull, Expressive Brow & Jaw
    final int headLag =
        isWalk ? (_kWalkBob12[(tick + 9) % 12] - bodyBob) : 0;
    final int headTilt = isCurious ? 3 : (isRoar ? -2 : headLag);
    final int headY = 7 + bodyBob + headTilt;

    buf.fillRect(28, headY + 5, 7, 6, midGreen);
    buf.fillRect(29, headY + 4, 6, 3, brightGreen);
    buf.fillRect(30, headY + 1, 16, 6, midGreen);
    buf.fillRect(31, headY, 14, 3, brightGreen);
    buf.fillRect(45, headY + 2, 3, 5, midGreen);
    buf.fillRect(32, headY - 1, 7, 2, limeScale);
    buf.setPx(33, headY - 1, specularScale);
    buf.setPx(30, headY, limeScale);
    buf.fillRect(44, headY + 2, 2, 1, darkGreen); // Nostril

    // Expressive Eye & Brow Ridge
    final int blinkStage = _eyeBlinkStage(tick, 38);
    if (isSleep || (!isListen && !isFixing && !isRoar && blinkStage == 2)) {
      buf.fillRect(34, headY + 1, 4, 3, darkGreen);
      buf.fillRect(34, headY + 2, 4, 1, outline);
    } else if (isFixing) {
      // Happy squinting eye arch (^)!
      buf.fillRect(34, headY + 1, 4, 3, darkGreen);
      buf.setPx(34, headY + 2, eyeGold);
      buf.fillRect(35, headY + 1, 2, 1, toothWhite);
      buf.setPx(37, headY + 2, eyeGold);
      buf.fillRect(33, headY - 1, 5, 1, specularScale);
    } else if (blinkStage == 1) {
      buf.fillRect(34, headY + 1, 4, 1, limeScale);
      buf.fillRect(34, headY + 2, 4, 2, eyeGold);
      final int pxOff = (lookDx >= 0) ? 2 : 0;
      buf.fillRect(34 + pxOff, headY + 2, 2, 1, pupilBlack);
    } else {
      buf.fillRect(34, headY + 1, 4, 3, eyeGold);
      final int pxOff = (lookDx >= 0) ? 2 : 0;
      final int pyOff = (lookDy > 0.3) ? 1 : 0;
      buf.fillRect(34 + pxOff, headY + 1 + pyOff, 2, 2, pupilBlack);
      buf.setPx(34 + (pxOff > 0 ? 1 : 0), headY + 1, toothWhite); // Eye shine!
      // Expressive brow ridge
      if (isRoar) {
        buf.drawLine(33, headY - 1, 38, headY + 1, darkGreen);
      } else if (isCurious) {
        buf.fillRect(33, headY - 2, 5, 1, specularScale);
      } else {
        buf.fillRect(33, headY, 5, 1, limeScale);
      }
    }

    // Nostril Steam Puffs & Roar Breath Sparks
    if (!isSleep && (isRoar || (tick % 20 >= 16))) {
      final int puffOff = (tick % 20) - 16;
      buf.setPx(
          48 + puffOff, headY + 1 - (puffOff ~/ 2), const Color(0xDDFFFFFF));
      buf.setPx(49 + puffOff, headY - (puffOff ~/ 2), const Color(0x99E0F7FA));
    }

    // Upper Jaw Teeth
    for (int tx = 35; tx <= 46; tx += 2) {
      buf.setPx(tx, headY + 7, toothWhite);
      if (tx >= 39) buf.setPx(tx, headY + 8, toothWhite);
    }

    // Articulated Lower Jaw & Wavy Tongue
    final int lowerY = headY + 8 + jawOpen;
    if (jawOpen > 0) {
      final int tongueWave = (tick % 4 < 2) ? 0 : 1;
      buf.fillRect(32, headY + 7 + tongueWave, 10, jawOpen, tongueRed);
      buf.fillRect(40, headY + 7 + tongueWave, 3, 1, tonguePink);
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
  // 4. TIER 1: SKY PTERODACTYL (56x40 Agile Aerodynamic Flyer)
  //    True figure-8 wingbeat with wrist-flick & elbow-tuck recovery stroke,
  //    swept amber-gold crest, rudder tail vane & wind-stream trails!
  // =========================================================================
  static PixelBuffer _buildPterodactyl(
    String animState,
    int tick,
    double audioLevel,
    double lookDx,
    double lookDy,
  ) {
    final buf = PixelBuffer(kGridW, kGridH);

    const Color outline = Color(0xFF06131C);
    const Color wingShadow = Color(0xFF006064);
    const Color wingTeal = Color(0xFF00ACC1);
    const Color wingSky = Color(0xFF26C6DA);
    const Color wingMembrane = Color(0xFF80DEEA);
    const Color wingHighlight = Color(0xFFB2EBF2);
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

    final bool isFastFlap = isListen || isFixing || isRoar || isCurious;
    final double flapSpeed = isFastFlap ? 0.88 : 0.44;
    final double flapPhase = tick * flapSpeed;

    // Aerodynamic lift: body rises on the downstroke (lagged by pi/3)
    final int hoverBob = isSleep
        ? 5
        : (math.sin(flapPhase - 1.0) * (isFastFlap ? 2.6 : 1.6)).round() -
            (isFastFlap ? 2 : 0);

    final int cx = 25;
    final int cy = 22 + hoverBob;

    // Figure-8 wing kinematics: elbow leads, wrist/tip follows with phase lag!
    final double elbowWave = isSleep ? -0.5 : math.sin(flapPhase);
    final double tipWave = isSleep ? -0.6 : math.sin(flapPhase - 0.65);

    // 1. Far Wing (drawn behind body)
    final int farWingTipY =
        (cy - 9 - (tipWave * (isFastFlap ? 8.5 : 6.0))).round().clamp(2, 33);
    final int farWingTipX = (cx - 13 + (elbowWave * 3.5)).round();
    buf.drawLine(cx - 2, cy - 2, farWingTipX, farWingTipY, wingShadow);
    for (int wx = farWingTipX; wx <= cx - 2; wx++) {
      final double t = (wx - farWingTipX) / ((cx - 2 - farWingTipX).abs() + 1);
      final int topY = (farWingTipY + (cy - 2 - farWingTipY) * t).round();
      final int botY = (topY + 4 + (t * 4)).round();
      for (int wy = topY; wy <= botY; wy++) {
        buf.setPx(wx, wy, (wy == topY) ? wingTeal : wingShadow);
      }
    }

    // 2. Rudder Tail Vane with Delayed Wave
    final int tailWave = (math.sin(flapPhase - 1.4) * 2.0).round();
    buf.drawLine(cx - 7, cy + 2, cx - 17, cy + 4 + tailWave, wingShadow);
    buf.drawOvalFilled(cx - 18, cy + 4 + tailWave, 3, 2, crestAmber);
    buf.setPx(cx - 18, cy + 4 + tailWave, crestGold);

    // 3. Streamlined Torso
    buf.drawOvalFilled(cx, cy, 7, 5, bodyAzure);
    buf.drawOvalFilled(cx + 1, cy - 1, 6, 4, wingSky);
    buf.drawOvalFilled(cx + 2, cy + 2, 5, 3, bellyCream);

    // 4. Near Wing with Articulated Elbow & Scalloped Membrane
    final int nearWingTipY =
        (cy - 11 - (tipWave * (isFastFlap ? 10.0 : 7.5))).round().clamp(2, 35);
    final int nearWingTipX =
        (cx - 18 - (elbowWave * 2.5)).round().clamp(2, 24);
    final int wingElbowX = cx - 6 + (elbowWave < 0 ? 1 : 0);
    final int wingElbowY = (cy - 5 - (elbowWave * 4.5)).round();

    for (int wx = nearWingTipX; wx <= cx + 1; wx++) {
      final double t =
          (wx - nearWingTipX) / ((cx + 1 - nearWingTipX).abs() + 1);
      final int sparY = (nearWingTipY + (cy - 1 - nearWingTipY) * t).round();
      final int scallop = ((wx % 4 == 0) ? 1 : 0);
      final int membraneBot = (sparY + 3 + (t * 6).round() - scallop);
      for (int wy = sparY; wy <= membraneBot; wy++) {
        Color c = wingMembrane;
        if (wy <= sparY + 1) c = (wx % 3 == 0) ? wingHighlight : wingSky;
        if (wy == sparY) c = crestGold;
        if (wy >= membraneBot - 1) c = wingTeal;
        buf.setPx(wx, wy, c);
      }
    }
    // Wing-elbow claws
    buf.setPx(wingElbowX, wingElbowY - 1, eyeWhite);
    buf.setPx(wingElbowX + 1, wingElbowY - 2, eyeWhite);

    // 5. Tucked or Striding Talons
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

    // 6. Aerodynamic Crest, Head & Long Pointed Beak
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

    // Expressive Eye
    final int blinkStage = _eyeBlinkStage(tick, 36);
    if (isSleep || (!isListen && !isFixing && !isRoar && blinkStage == 2)) {
      buf.fillRect(headX + 2, headY + 1, 3, 2, wingShadow);
      buf.fillRect(headX + 2, headY + 2, 3, 1, outline);
    } else if (isFixing) {
      buf.setPx(headX + 2, headY + 2, crestGold);
      buf.setPx(headX + 3, headY + 1, eyeWhite);
      buf.setPx(headX + 4, headY + 2, crestGold);
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
  // 5. HAND-CRAFTED GAME-FEEL PROPS, EMOTES & PARTICLE EFFECTS
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

    // A. Multi-Stage Expanding & Dissolving Footstep Dust Clouds during Walk
    if (animState == 'walk') {
      const Color dustBright = Color(0xEEFFF8E1);
      const Color dustMid = Color(0xBB90A4AE);
      const Color dustFade = Color(0x66607D8B);
      for (int p = 0; p < 2; p++) {
        final int age = (tick + p * 3) % 6;
        final int dx = 13 - age * 2;
        final int dy = 35 - (age ~/ 2);
        if (age <= 2) {
          buf.fillRect(dx, dy, 2, 2, dustBright);
          buf.setPx(dx - 1, dy + 1, dustMid);
        } else if (age <= 4) {
          buf.setPx(dx, dy, dustMid);
          buf.setPx(dx - 1, dy - 1, dustFade);
          buf.setPx(dx + 1, dy, dustFade);
        } else {
          buf.setPx(dx, dy - 1, dustFade);
        }
      }
    }

    // B. Sleeping Floating Pixel "Z z ." Runes + Cozy Dream Mote
    if (animState == 'sleep') {
      const Color zCol = Color(0xFF80D8FF);
      const Color zGlow = Color(0xFFE1F5FE);
      final int zRise = (tick ~/ 2) % 8;
      final int zx = 43 + ((math.sin(tick * 0.35)).round());
      final int zy = 12 - zRise;
      buf.fillRect(zx, zy, 4, 1, zGlow);
      buf.setPx(zx + 2, zy + 1, zCol);
      buf.setPx(zx + 1, zy + 2, zCol);
      buf.fillRect(zx, zy + 3, 4, 1, zCol);
      buf.fillRect(zx - 5, zy + 5, 3, 1, zCol);
      buf.setPx(zx - 4, zy + 6, zCol);
      buf.fillRect(zx - 5, zy + 7, 3, 1, zCol);
    }

    // C. Curious / Inspection Emotes (Orbiting Runes + Pixel '?' Emote or Dragonfly/Fern)
    if (animState == 'curious') {
      // Cute floating '?' pixel emote above head
      final int qBob = (math.sin(tick * 0.5) * 1.2).round();
      const Color qCol = Color(0xFFFFEE18);
      buf.fillRect(23, 1 + qBob, 3, 1, qCol);
      buf.setPx(25, 2 + qBob, qCol);
      buf.setPx(24, 3 + qBob, qCol);
      buf.setPx(24, 5 + qBob, const Color(0xFF00E5FF));

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

    // D. Active Typing Props: Floating Holographic Pixel Keyboard + Rising Key Sparks
    if (animState == 'typing') {
      const Color holoFrame = Color(0xFF00E5FF);
      const Color holoBg = Color(0xAA004D40);
      const Color keyLit = Color(0xFFFFF59D);
      final int hover = (math.sin(tick * 0.6) * 1.0).round();
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
        if (pressed) {
          buf.setPx(kx, 23 + hover - (tick % 3), keyLit);
        }
      }
    }

    // E. Listening Sonar Rings & Sound-Wave Ripple
    if (animState == 'listen' || animState == 'target_wait') {
      const Color waveCol = Color(0xFF00E676);
      const Color waveGlow = Color(0xFFB9F6CA);
      for (int ring = 0; ring < 2; ring++) {
        final int phase = (tick + ring * 2) % 5;
        final int arcX = 49 + phase;
        if (arcX < kGridW - 1) {
          for (int dy = -4; dy <= 4; dy++) {
            final int dx = (dy.abs() >= 3) ? -1 : 0;
            buf.setPx(
              arcX + dx,
              14 + dy,
              (dy.abs() <= 1) ? waveGlow : waveCol,
            );
          }
        }
      }
    }

    // F. Grammar Fix / Spellcast / Roar 4-Point Starburst & Rising Sparkles
    if (animState == 'fixing' || animState == 'happy' || animState == 'roar') {
      const Color starCyan = Color(0xFF00E5FF);
      const Color starGold = Color(0xFFFFEE18);
      const Color starEmerald = Color(0xFF00E84A);
      const Color starWhite = Color(0xFFFFFFFF);
      final List<List<int>> stars = [
        [8, 6 - (tick % 4)],
        [48, 5 - ((tick + 1) % 4)],
        [25, 3 - ((tick + 2) % 3)],
        [13, 5 - ((tick + 3) % 3)],
        [42, 10 - (tick % 3)],
      ];
      final List<Color> cols = [starCyan, starGold, starEmerald];
      for (int i = 0; i < stars.length; i++) {
        final int sx = stars[i][0];
        final int sy = stars[i][1];
        final Color c = cols[(i + tick) % cols.length];
        final bool fullCross = ((tick + i) % 2 == 0);
        buf.setPx(sx, sy, starWhite);
        if (fullCross) {
          buf.setPx(sx - 1, sy, c);
          buf.setPx(sx + 1, sy, c);
          buf.setPx(sx, sy - 1, c);
          buf.setPx(sx, sy + 1, c);
        } else {
          buf.setPx(sx, sy, c);
        }
      }
    }

    // G. Ambient Floating Game Fireflies / Arcane Embers with Soft Halo
    if (animState != 'sleep') {
      final Color moteCore = isCultist
          ? const Color(0xFFFFF59D)
          : (creature == 'trex'
              ? const Color(0xFFB9F6CA)
              : const Color(0xFFE0F7FA));
      final Color moteHalo = isCultist
          ? const Color(0x66FFEE18)
          : (creature == 'trex'
              ? const Color(0x6669F0AE)
              : const Color(0x6680DEEA));
      for (int m = 0; m < 2; m++) {
        final double ang = tick * 0.16 + m * 3.14;
        final int mx = (25 + math.cos(ang) * 20).round();
        final int my = (15 + math.sin(ang * 1.4) * 9).round();
        if (buf.getPx(mx, my) == null) {
          buf.setPx(mx, my, moteCore);
          if (buf.getPx(mx - 1, my) == null) buf.setPx(mx - 1, my, moteHalo);
          if (buf.getPx(mx + 1, my) == null) buf.setPx(mx + 1, my, moteHalo);
        }
      }
    }
  }

  // =========================================================================
  // 6. LIVING PIXEL TERRAIN FLOOR GENERATOR (110x10 Grid on Top of Floor Box)
  //    Features travelling wind waves across prehistoric grass + a strolling
  //    pixel ladybug, or beveled dungeon flagstones with pulsing runes &
  //    rising candle embers!
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
      const Color emberMote = Color(0x99FFAB00);

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
        // Travelling arcane rune wave across the stone altar!
        if (x % 16 == 8 && x > 10 && x < kFloorW - 10) {
          final double wave = math.sin(tick * 0.35 - x * 0.08);
          final Color rCol = (wave > 0.1 || isActive) ? runeCyan : runeGlow;
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
        final int flickerDx = ((tick + i * 2) % 4 == 0) ? 1 : 0;
        final int flickerDy = ((tick + i * 3) % 3 == 0) ? -1 : 0;
        buf.setPx(cx + flickerDx, 5 - h + flickerDy, flameGold);
        buf.setPx(cx + 1, 5 - h, flameOrange);
        // Rising candle ember spark
        final int sparkY = (4 - h) - ((tick + i * 2) % 3);
        if (sparkY >= 0) {
          buf.setPx(cx + flickerDx, sparkY, emberMote);
        }
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

      for (int x = 0; x < kFloorW; x++) {
        if (x % 4 == 0) buf.setPx(x, 7, turfBase);
        if (x % 7 == 0) buf.setPx(x, 8, soilLight);

        final int hash = (x * 37 + 13) % 7;
        final int bladeH = (hash % 4) + 1;
        // Travelling wind gust rolling smoothly from left to right across the grass!
        final int tipSway = (bladeH >= 3)
            ? (math.sin(tick * 0.36 - x * 0.09) * 1.35).round()
            : 0;

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
            x + tipSway,
            2,
            (creature == 'ptero' || creature == 'stego')
                ? flowerCyan
                : flowerAmber,
          );
        }
      }

      // Cute tiny pixel ladybug strolling along the grass blades!
      final int bugX = 18 + ((tick ~/ 2) % (kFloorW - 36));
      buf.setPx(bugX, 4, const Color(0xFFFF1744));
      buf.setPx(bugX + 1, 4, const Color(0xFF111111));
    }

    return buf;
  }
}

class PixelCreaturePainter extends CustomPainter {
  final PixelBuffer buffer;
  final bool flipHorizontal;
  final double shadowScale;

  PixelCreaturePainter({
    required this.buffer,
    required this.flipHorizontal,
    this.shadowScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int cols = buffer.width;
    final int rows = buffer.height;
    final double pixelSize = math.min(size.width / cols, size.height / rows);

    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Soft layered ground shadow that dynamically scales with creature height/squash
    final double sW = (cols - 22) * pixelSize * shadowScale;
    final double sX = (size.width - sW) / 2.0;
    final double sY = (rows - 2.6) * pixelSize;
    paint.color = const Color(0x38000000);
    canvas.drawOval(
      Rect.fromLTWH(sX - pixelSize * 1.5, sY - 1, sW + pixelSize * 3, pixelSize * 2.4),
      paint,
    );
    paint.color = const Color(0x66000000);
    canvas.drawOval(
      Rect.fromLTWH(sX, sY, sW, pixelSize * 1.7),
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
            pixelSize + 0.38,
            pixelSize + 0.38,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelCreaturePainter oldDelegate) {
    return oldDelegate.buffer != buffer ||
        oldDelegate.flipHorizontal != flipHorizontal ||
        oldDelegate.shadowScale != shadowScale;
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

    // Compute fluid sub-pixel squash-and-stretch, arc bounce & tilt (12 Principles of Animation)
    double scaleX = 1.0;
    double scaleY = 1.0;
    double subPixelDy = 0.0;
    double tiltRad = 0.0;
    double shadowScale = 1.0;

    if (animState == 'walk') {
      final double phase = (tick % 12) * (math.pi / 3.0);
      final double bounce = math.sin(phase);
      scaleY = 1.0 + 0.038 * bounce;
      scaleX = 1.0 - 0.032 * bounce;
      subPixelDy = -math.max(0.0, bounce) * (cellPx * 1.15);
      final double leanSign = flipHorizontal ? -1.0 : 1.0;
      tiltRad = leanSign * (0.024 + 0.015 * math.cos(phase));
      shadowScale = 1.0 - 0.12 * math.max(0.0, bounce);
    } else if (animState == 'fixing' ||
        animState == 'happy' ||
        animState == 'roar') {
      final double phase = (tick % 8) * (math.pi / 4.0);
      final double hop = math.sin(phase);
      scaleY = 1.0 + 0.065 * hop;
      scaleX = 1.0 - 0.052 * hop;
      subPixelDy = -math.max(0.0, hop) * (cellPx * 1.8);
      tiltRad = math.cos(phase) * 0.032;
      shadowScale = 1.0 - 0.18 * math.max(0.0, hop);
    } else if (animState == 'listen' || animState == 'typing') {
      final double pulse =
          math.sin(tick * 0.55) * (0.022 + audioLevel * 0.045);
      scaleY = 1.0 + pulse;
      scaleX = 1.0 - pulse * 0.75;
      subPixelDy = -audioLevel * cellPx * 1.2;
    } else if (animState == 'curious') {
      final double leanSign = flipHorizontal ? -1.0 : 1.0;
      tiltRad = leanSign * 0.048 + math.sin(tick * 0.35) * 0.018;
      scaleY = 1.0 + math.sin(tick * 0.35) * 0.022;
      scaleX = 1.0 - math.sin(tick * 0.35) * 0.018;
    } else if (animState == 'sleep') {
      final double breath = math.sin(tick * 0.22);
      scaleY = 0.96 + 0.025 * breath;
      scaleX = 1.03 - 0.020 * breath;
    } else {
      // Smooth idle breathing & subtle weight shift
      final double breath = math.sin(tick * 0.32);
      scaleY = 1.0 + 0.022 * breath;
      scaleX = 1.0 - 0.018 * breath;
      tiltRad = math.sin(tick * 0.16) * 0.010;
    }

    if (creature == 'custom' &&
        customSpritePath != null &&
        customSpritePath!.isNotEmpty &&
        File(customSpritePath!).existsSync()) {
      return Transform.translate(
        offset: Offset(0, subPixelDy),
        child: Transform.rotate(
          angle: tiltRad,
          alignment: Alignment.bottomCenter,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
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
      child: Transform.translate(
        offset: Offset(0, subPixelDy),
        child: Transform.rotate(
          angle: tiltRad,
          alignment: Alignment.bottomCenter,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
            child: CustomPaint(
              painter: PixelCreaturePainter(
                buffer: buffer,
                flipHorizontal: flipHorizontal,
                shadowScale: shadowScale,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
