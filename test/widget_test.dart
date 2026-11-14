import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_assistant/main.dart';
import 'package:vtt_assistant/pixel_sprites.dart';
import 'package:vtt_assistant/pixel_ui.dart';

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
      // let the drawer finish sliding open
      await tester.pump(const Duration(milliseconds: 300));

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
      // let the drawer finish sliding open
      await tester.pump(const Duration(milliseconds: 300));

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

  group('Clean-as-you-go feedback', () {
    Map<String, dynamic> status({
      required int fixEventId,
      bool liveClean = false,
      Map<String, dynamic>? latestFix,
    }) {
      return <String, dynamic>{
        'creature': 'review',
        'is_listening': false,
        'live_clean': liveClean,
        'smart_typos_available': true,
        'fix_event_id': fixEventId,
        'latest_fix': latestFix ?? <String, dynamic>{},
        'raw_live_text': 'the wron cnt',
        'polished_live_text': 'The wrong cnt',
        'recent_fixes': [
          {
            'original': 'wron',
            'replacement': 'wrong',
            'reason': 'Typo fix',
            'category': 'spelling',
          },
        ],
        'grammarly_report': {
          'writing_score': 91,
          'detected_tone': 'Direct & Clear',
          'pillar_scores': {
            'correctness': 98,
            'clarity': 100,
            'engagement': 80,
            'delivery': 100,
          },
          'recommendations': <dynamic>[],
          'sentence_variants': <dynamic>[],
          'word_explorations': [
            {'index': 0, 'word': 'The', 'display': 'The', 'kind': 'normal', 'alternatives': <String>[]},
            {'index': 1, 'word': 'wrong', 'display': 'wrong', 'kind': 'normal', 'alternatives': <String>[]},
            {'index': 2, 'word': 'cnt', 'display': 'cnt', 'kind': 'spelling', 'alternatives': ['cut', 'cant', 'cent']},
          ],
        },
      };
    }

    testWidgets('A new fix pops a toast and unsure spellings offer choices + KEEP',
        (WidgetTester tester) async {
      await tester.pumpWidget(const VttPixelAssistantApp());
      await tester.tap(find.text('[▼ EXPAND]'));
      await tester.pump();
      // let the drawer finish sliding open
      await tester.pump(const Duration(milliseconds: 300));

      final dynamic state = tester.state(find.byType(TransparentOverlayScreen));

      // First status only sets the baseline: no toast for old fixes.
      state.applyEngineStatus(status(fixEventId: 4));
      await tester.pump();
      expect(find.byType(FixToast), findsNothing);
      expect(find.text('⚡ LIVE CLEAN: OFF'), findsOneWidget);

      // The unsure word is offered as choices, with a KEEP (learn) button.
      expect(find.textContaining('DID YOU MEAN ("cnt")'), findsOneWidget);
      expect(find.text('cut'), findsOneWidget);
      expect(find.text('✓ KEEP'), findsOneWidget);

      // A newer fix event pops the toast and reflects Live Clean being on.
      state.applyEngineStatus(status(
        fixEventId: 5,
        liveClean: true,
        latestFix: {
          'original': 'teh',
          'replacement': 'the',
          'category': 'spelling',
          'count': '1',
        },
      ));
      await tester.pump();
      expect(find.byType(FixToast), findsOneWidget);
      expect(find.text('teh'), findsOneWidget);
      expect(find.text('⚡ LIVE CLEAN: ON'), findsOneWidget);

      // The toast removes itself once its animation finishes.
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pump();
      expect(find.byType(FixToast), findsNothing);
    });

    testWidgets('Pixel buttons fire onTap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PixelButton(
              label: 'GO',
              color: const Color(0xFF00E676),
              tooltip: 'go',
              onTap: () => taps++,
            ),
          ),
        ),
      ));
      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(taps, 1);
    });
  });
}
