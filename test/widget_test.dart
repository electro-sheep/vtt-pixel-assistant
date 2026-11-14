import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_assistant/main.dart';
import 'package:vtt_assistant/pixel_sprites.dart';

void main() {
  group('HighResPixelGenerator 3-Tier Sprite & Terrain Floor Tests', () {
    const List<String> creatures = [
      'review',
      'ptero',
      'cultist',
      'cultist_lunar',
      'trex',
    ];
    const List<String> states = [
      'idle',
      'walk',
      'curious',
      'sleep',
      'listen',
      'typing',
      'fixing',
      'roar',
    ];

    test('Generates valid 56x40 pixel buffers for Pterodactyl, Cultist, and T-Rex', () {
      for (final creature in creatures) {
        for (final state in states) {
          final buf = HighResPixelGenerator.buildFrame(
            creature: creature,
            animState: state,
            tick: 4,
            audioLevel: 0.65,
            lookDx: 0.8,
            lookDy: -0.4,
          );
          expect(buf.width, equals(56));
          expect(buf.height, equals(40));
          final int nonNullPixels =
              buf.pixels.where((Color? c) => c != null).length;
          expect(
            nonNullPixels,
            greaterThan(140),
            reason: '$creature in $state should render substantial pixel art',
          );
        }
      }
    });

    test('Generates living pixel terrain floors (Prehistoric Grass vs Cultist Cobblestone)', () {
      final grassFloor = HighResPixelGenerator.buildTerrainFloor(
        creature: 'trex',
        tick: 2,
        isActive: true,
      );
      final stoneFloor = HighResPixelGenerator.buildTerrainFloor(
        creature: 'cultist',
        tick: 2,
        isActive: true,
      );
      expect(grassFloor.width, equals(110));
      expect(grassFloor.height, equals(10));
      expect(stoneFloor.width, equals(110));
      expect(stoneFloor.height, equals(10));

      int diff = 0;
      for (int i = 0; i < grassFloor.pixels.length; i++) {
        if (grassFloor.pixels[i] != stoneFloor.pixels[i]) diff++;
      }
      expect(diff, greaterThan(400));
    });

    test('Cultist eyes beneath hood track cursor direction lookDx', () {
      final lookLeft = HighResPixelGenerator.buildFrame(
        creature: 'cultist',
        animState: 'idle',
        tick: 1,
        audioLevel: 0.0,
        lookDx: -1.0,
      );
      final lookRight = HighResPixelGenerator.buildFrame(
        creature: 'cultist',
        animState: 'idle',
        tick: 1,
        audioLevel: 0.0,
        lookDx: 1.0,
      );

      int diff = 0;
      for (int i = 0; i < lookLeft.pixels.length; i++) {
        if (lookLeft.pixels[i] != lookRight.pixels[i]) diff++;
      }
      expect(diff, greaterThan(3));
    });
  });

  group('VTT Pixel Assistant Under-Creature Floor & 3-Tier Progression Tests', () {
    testWidgets('Starts as a compact flat terrain floor underneath the creature and expands on click',
        (WidgetTester tester) async {
      await tester.pumpWidget(const VttPixelAssistantApp());

      // Starts in compact flat floor mode underneath the creature
      expect(find.byType(PixelTerrainFloorWidget), findsOneWidget);
      expect(find.textContaining('Click creature to transcribe'), findsOneWidget);
      expect(find.text('[▼ EXPAND]'), findsOneWidget);

      // Clicking the flat floor bar expands it to reveal the 4-Option Mode & Tier Progression HUD
      await tester.tap(find.text('[▼ EXPAND]'));
      await tester.pump();

      expect(find.text('T0: REVIEW'), findsOneWidget);
      expect(find.text('T1: PTERO'), findsOneWidget);
      expect(find.text('T2: CULTIST'), findsOneWidget);
      expect(find.text('T3: T-REX'), findsOneWidget);
      expect(find.textContaining('GRAMMARLY SCORE:'), findsOneWidget);
      expect(find.text('▲ FLAT'), findsOneWidget);
    });

    testWidgets('Switches across Tier 0 (Pure Text Review) and Tiers 1-3, and opens Writing Studio',
        (WidgetTester tester) async {
      await tester.pumpWidget(const VttPixelAssistantApp());

      // Expand floor box
      await tester.tap(find.text('[▼ EXPAND]'));
      await tester.pump();

      // Switch to Tier 0: Pure Text Reviewer (No VTT)
      await tester.tap(find.text('T0: REVIEW'));
      await tester.pump();
      expect(find.textContaining('No-VTT (Review Only)'), findsOneWidget);
      expect(find.text('🔍 REVIEW TEXT'), findsOneWidget);

      // Switch to Tier 1: Pterodactyl
      await tester.tap(find.text('T1: PTERO'));
      await tester.pump();
      expect(find.textContaining('small.en'), findsOneWidget);

      // Switch to Tier 2: Cultist Scribe
      await tester.tap(find.text('T2: CULTIST'));
      await tester.pump();
      expect(find.textContaining('medium.en'), findsOneWidget);

      // Open Writing Studio (PAD)
      await tester.tap(find.text('PAD'));
      await tester.pump();

      expect(find.text('DYSLEXIA & GRAMMARLY WRITING STUDIO'), findsOneWidget);
      expect(find.text('POLISH & FIX'), findsOneWidget);
      expect(find.text('TYPE TO APP'), findsOneWidget);
    });

    testWidgets('Right-click opens Pixel Assistant & Tier Menu',
        (WidgetTester tester) async {
      await tester.pumpWidget(const VttPixelAssistantApp());

      final Offset petCenter = tester.getCenter(find.byType(PixelCreatureWidget));
      final TestGesture gesture = await tester.startGesture(
        petCenter,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();

      expect(find.text('PIXEL ASSISTANT & TIER MENU'), findsOneWidget);
      expect(find.textContaining('Ember Cultist'), findsOneWidget);
      expect(find.textContaining('Lunatic Beak Cultist'), findsOneWidget);
      expect(find.textContaining('Sky Pterodactyl'), findsOneWidget);
    });
  });
}
