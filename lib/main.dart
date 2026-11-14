import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pixel_sprites.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VttPixelAssistantApp());
}

class VttPixelAssistantApp extends StatelessWidget {
  const VttPixelAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VTT Pixel Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Consolas',
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const TransparentOverlayScreen(),
    );
  }
}

class TransparentOverlayScreen extends StatefulWidget {
  const TransparentOverlayScreen({super.key});

  @override
  State<TransparentOverlayScreen> createState() =>
      _TransparentOverlayScreenState();
}

class _TransparentOverlayScreenState extends State<TransparentOverlayScreen> {
  static const MethodChannel _windowChannel =
      MethodChannel('vtt_assistant/window');
  static const String _backendBaseUrl = 'http://127.0.0.1:8765';
  static const double _floorWidth = 412.0;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 600);
  Process? _backendProcess;

  // Floor platform & creature position state (creature stands ON the floor box)
  double _floorX = 310.0;
  double _petX = 420.0;
  double _petY = 190.0;
  bool _initializedPosition = false;
  double _pixelScale = 5.0;
  bool _roamingEnabled = true;
  bool _isDragging = false;
  bool _facingLeft = false;
  double _walkDirection = 1.0;
  String _autonomousAction = 'walk'; // 'walk', 'idle', 'curious', 'sleep'
  int _behaviorCounter = 0;
  int _idleTicksWithoutActivity = 0;

  // Real-time cursor tracking for creature eyes
  double _cursorX = 500.0;
  double _cursorY = 500.0;

  // Animation & Floor UI state
  int _animTick = 0;
  String _localTrickState = '';
  int _trickTicksRemaining = 0;
  bool _showContextMenu = false;
  final bool _showSpeechBubble = true;
  bool _isFloorExpanded = false; // Starts as a compact flat floor bar!
  bool _showScratchpad = false;
  bool _showCustomPathInput = false;
  String? _customSpritePath;
  final TextEditingController _spritePathController = TextEditingController();
  final TextEditingController _scratchpadController = TextEditingController();
  String _lastSyncedSessionTranscript = '';

  // Engine synchronized state
  bool _backendConnected = false;
  bool _modelLoading = false;
  String _activeCreature = 'cultist';
  String _cultistSkin = 'cultist'; // 'cultist' (Ember) or 'cultist_lunar' (Lunatic Beak)
  String _creatureName = 'Ember Cultist Scribe';
  int _creatureTier = 2;
  String _creatureVram = '~1.5 GB VRAM';
  String _modelName = 'medium.en';
  String _computeBackend = 'CUDA GPU';
  String _targetWindow = 'Active Window';
  String _writingTone = 'clear';
  int _totalWordsWritten = 0;
  int _totalFixesApplied = 0;
  bool _isListening = false;
  double _audioLevel = 0.0;
  String _rawLiveText = '';
  String _polishedLiveText = '';
  List<Map<String, String>> _recentFixes = [];
  int _writingScore = 100;
  String _detectedTone = 'Direct & Clear';
  Map<String, int> _pillarScores = {
    'correctness': 100,
    'clarity': 100,
    'engagement': 100,
    'delivery': 100,
  };
  List<Map<String, String>> _grammarlyRecommendations = [];
  List<Map<String, dynamic>> _wordExplorations = [];
  List<Map<String, String>> _sentenceVariants = [];
  int _selectedWordIndex = -1;

  String _statusMessage = 'Click creature to start transcribing (or press F8).';
  String _engineAnimState = 'idle';
  Map<String, bool> _grammarRules = {
    'homophones': true,
    'dyslexia_spelling': true,
    'speech_cleanup': true,
    'grammar_structure': true,
    'clarity_conciseness': true,
    'auto_punctuation': true,
  };

  Timer? _animTimer;
  Timer? _statusTimer;
  int _lastExecutedEditId = 0;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _setupWindowChannel();
    _ensureBackendStarted();

    // 55ms high-fluidity active game animation & AI behavior loop
    _animTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
      _onAnimationTick();
    });

    // 160ms local engine status & eye-tracking polling loop
    _statusTimer = Timer.periodic(const Duration(milliseconds: 160), (_) {
      _pollBackendStatus();
    });
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _statusTimer?.cancel();
    _backendProcess?.kill();
    _spritePathController.dispose();
    _scratchpadController.dispose();
    super.dispose();
  }

  void _setupWindowChannel() {
    _windowChannel.setMethodCallHandler((call) async {
      if (call.method == 'onExternalScreenClick') {
        final Map<dynamic, dynamic>? args =
            call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          final double lx = (args['x'] as num?)?.toDouble() ?? 0.0;
          final int physX = (args['physX'] as num?)?.toInt() ?? lx.toInt();
          final int physY = (args['physY'] as num?)?.toInt() ?? 0;

          if (_showContextMenu) {
            setState(() {
              _showContextMenu = false;
              _showCustomPathInput = false;
            });
            _updateFocusAllowance();
            _syncInteractiveRects();
          }

          setState(() {
            _facingLeft = lx < _petX;
            _idleTicksWithoutActivity = 0;
          });
          await _postBackend('/target_clicked', {'x': physX, 'y': physY});
        }
      }
    });
  }

  void _updateFocusAllowance() {
    final bool needsKeyboard = _showScratchpad || _showCustomPathInput;
    _windowChannel.invokeMethod('setAllowFocus', needsKeyboard);
  }

  String? _findBackendScript() {
    final List<String> roots = [
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
      File(Platform.resolvedExecutable).parent.parent.path,
      File(Platform.resolvedExecutable).parent.parent.parent.path,
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path,
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path,
      r'd:\New folder\Codeing\Vtt Assistant',
    ];
    for (final r in roots) {
      final candidate = File(
        '$r${Platform.pathSeparator}backend${Platform.pathSeparator}vtt_engine.py',
      );
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return null;
  }

  Future<void> _ensureBackendStarted() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final bool alive = await _pollBackendStatus(checkVersion: true);
    if (alive) return;

    final String? scriptPath = _findBackendScript();
    if (scriptPath != null) {
      try {
        _backendProcess = await Process.start(
          'python',
          [scriptPath],
          workingDirectory: File(scriptPath).parent.parent.path,
        );
      } catch (_) {}
    }
  }

  Future<bool> _pollBackendStatus({bool checkVersion = false}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    if (_isPolling && !checkVersion) return true;
    _isPolling = true;
    try {
      final request = await _http.getUrl(
        Uri.parse(
          '$_backendBaseUrl/status?ui=1&last_edit_id=$_lastExecutedEditId',
        ),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final String body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data =
            jsonDecode(body) as Map<String, dynamic>;

        if (checkVersion && data['engine_version'] != '3.3') {
          await _postBackend('/shutdown', {});
          await Future<void>.delayed(const Duration(milliseconds: 350));
          return false;
        }

        final int latestEditId =
            (data['latest_edit_id'] as num?)?.toInt() ?? 0;
        if (latestEditId < _lastExecutedEditId) {
          _lastExecutedEditId = 0;
        }

        final List<dynamic>? pendingEdits =
            data['pending_edits'] as List<dynamic>?;
        if (pendingEdits != null && pendingEdits.isNotEmpty) {
          for (final dynamic item in pendingEdits) {
            if (item is Map) {
              final int editId = (item['id'] as num?)?.toInt() ?? 0;
              if (editId > _lastExecutedEditId) {
                _lastExecutedEditId = editId;
                final int bs = (item['backspaces'] as num?)?.toInt() ?? 0;
                final String txt = (item['text'] as String?) ?? '';
                if (bs > 0 || txt.isNotEmpty) {
                  try {
                    await _windowChannel.invokeMethod(
                      'typeInPlace',
                      {'backspaces': bs, 'text': txt},
                    );
                  } catch (_) {}
                }
              }
            }
          }
        }

        if (!mounted) return true;
        final String sessionText =
            (data['session_transcript'] as String?) ?? '';
        final String livePolished =
            (data['polished_live_text'] as String?) ?? '';
        final bool wasListening = _isListening;
        final bool nowListening = (data['is_listening'] as bool?) ?? false;

        setState(() {
          _backendConnected = true;
          _modelLoading = (data['model_loading'] as bool?) ?? false;
          final String serverCreature =
              (data['creature'] as String?) ?? _activeCreature;
          _activeCreature = serverCreature;
          if (serverCreature == 'cultist' || serverCreature == 'cultist_lunar') {
            _cultistSkin = serverCreature;
          }
          _creatureName = (data['creature_name'] as String?) ?? _creatureName;
          _creatureTier =
              (data['creature_tier'] as num?)?.toInt() ?? _creatureTier;
          _creatureVram = (data['creature_vram'] as String?) ?? _creatureVram;
          _modelName = (data['model_name'] as String?) ?? _modelName;
          _computeBackend =
              (data['compute_backend'] as String?) ?? _computeBackend;
          _targetWindow = (data['target_window'] as String?) ?? _targetWindow;
          _writingTone = (data['writing_tone'] as String?) ?? _writingTone;
          _totalWordsWritten =
              (data['total_words_written'] as num?)?.toInt() ?? 0;
          _totalFixesApplied =
              (data['total_fixes_applied'] as num?)?.toInt() ?? 0;
          _cursorX = (data['cursor_x'] as num?)?.toDouble() ?? _cursorX;
          _cursorY = (data['cursor_y'] as num?)?.toDouble() ?? _cursorY;
          _isListening = nowListening;
          if (!wasListening && nowListening) {
            _setFloorExpanded(true);
          }
          _audioLevel = (data['audio_level'] as num?)?.toDouble() ?? 0.0;
          _rawLiveText = (data['raw_live_text'] as String?) ?? '';
          _polishedLiveText = livePolished;
          _statusMessage =
              (data['status_message'] as String?) ?? _statusMessage;
          _engineAnimState = (data['pet_anim_state'] as String?) ?? 'idle';

          if (_isListening || _audioLevel > 0.12) {
            _idleTicksWithoutActivity = 0;
          }

          final String combinedTranscript = [
            if (sessionText.isNotEmpty) sessionText,
            if (livePolished.isNotEmpty) livePolished,
          ].join(' ');

          if (combinedTranscript.isNotEmpty &&
              combinedTranscript != _lastSyncedSessionTranscript) {
            _lastSyncedSessionTranscript = combinedTranscript;
            _scratchpadController.text = combinedTranscript;
            _scratchpadController.selection = TextSelection.fromPosition(
              TextPosition(offset: _scratchpadController.text.length),
            );
          }

          final List<dynamic>? rawFixes =
              data['recent_fixes'] as List<dynamic>?;
          if (rawFixes != null) {
            _recentFixes = rawFixes
                .map((item) => Map<String, String>.from(
                    (item as Map).map((k, v) => MapEntry('$k', '$v'))))
                .toList();
          }

          final Map<String, dynamic>? grammarlyReport =
              data['grammarly_report'] as Map<String, dynamic>?;
          if (grammarlyReport != null) {
            _writingScore =
                (grammarlyReport['writing_score'] as num?)?.toInt() ?? 100;
            _detectedTone = (grammarlyReport['detected_tone'] as String?) ??
                'Direct & Clear';
            final Map<String, dynamic>? pScores =
                grammarlyReport['pillar_scores'] as Map<String, dynamic>?;
            if (pScores != null) {
              _pillarScores = pScores.map(
                (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 100),
              );
            }
            final List<dynamic>? recs =
                grammarlyReport['recommendations'] as List<dynamic>?;
            if (recs != null) {
              _grammarlyRecommendations = recs
                  .map((item) => Map<String, String>.from(
                      (item as Map).map((k, v) => MapEntry('$k', '$v'))))
                  .toList();
            }
            final List<dynamic>? explorations =
                grammarlyReport['word_explorations'] as List<dynamic>?;
            if (explorations != null) {
              _wordExplorations = explorations
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
            }
            final List<dynamic>? variants =
                grammarlyReport['sentence_variants'] as List<dynamic>?;
            if (variants != null) {
              _sentenceVariants = variants
                  .map((item) => Map<String, String>.from(
                      (item as Map).map((k, v) => MapEntry('$k', '$v'))))
                  .toList();
            }
          }

          final Map<String, dynamic>? rawRules =
              data['rules'] as Map<String, dynamic>?;
          if (rawRules != null) {
            _grammarRules = rawRules.map((k, v) => MapEntry(k, v == true));
          }
        });
        _syncInteractiveRects();
        return true;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _backendConnected = false;
        });
      }
    } finally {
      _isPolling = false;
    }
    return false;
  }

  Future<void> _postBackend(String path, Map<String, dynamic> payload) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final request = await _http.postUrl(Uri.parse('$_backendBaseUrl$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close();
      if (response.statusCode == 200) {
        final String body = await response.transform(utf8.decoder).join();
        if (path == '/analyze_text') {
          final Map<String, dynamic> res =
              jsonDecode(body) as Map<String, dynamic>;
          final String? corr = res['corrected'] as String?;
          if (corr != null && corr.isNotEmpty && mounted) {
            setState(() {
              _scratchpadController.text = corr;
              _scratchpadController.selection = TextSelection.fromPosition(
                TextPosition(offset: corr.length),
              );
            });
          }
        }
        await _pollBackendStatus();
      }
    } catch (_) {}
  }

  double get _petWidth => HighResPixelGenerator.kGridW * (_pixelScale * 0.52);
  double get _petHeight => HighResPixelGenerator.kGridH * (_pixelScale * 0.52);

  double get _currentFloorHeight {
    if (!_isFloorExpanded) {
      return 52.0; // Compact flat floor bar + 18px grass/stone top
    }
    return 295.0; // Expanded live transcription + interactive word explorer + Grammarly drawer
  }

  void _setFloorExpanded(bool expanded) {
    _isFloorExpanded = expanded;
    if (!mounted) return;
    final Size screen = MediaQuery.of(context).size;
    if (screen.height > 260) {
      final double maxPetY =
          screen.height - _petHeight - _currentFloorHeight - 12.0;
      if (_petY > maxPetY) {
        _petY = math.max(24.0, maxPetY);
      }
    }
  }

  void _moveSanctuaryBy(double dx, double dy) {
    final Size screen = MediaQuery.of(context).size;
    _floorX += dx;
    _petX += dx;
    _petY += dy;

    if (screen.width > _floorWidth + 24) {
      final double clampedFloorX =
          _floorX.clamp(12.0, screen.width - _floorWidth - 12.0);
      final double adjustX = clampedFloorX - _floorX;
      _floorX = clampedFloorX;
      _petX += adjustX;
    }
    if (screen.height > 260) {
      final double maxPetY =
          screen.height - _petHeight - _currentFloorHeight - 8.0;
      _petY = _petY.clamp(28.0, math.max(36.0, maxPetY));
    }
  }

  void _onAnimationTick() {
    if (!mounted) return;
    final Size screenSize = MediaQuery.of(context).size;
    if (screenSize.width > 100 && !_initializedPosition) {
      _floorX = (screenSize.width - _floorWidth - 36.0)
          .clamp(16.0, math.max(20.0, screenSize.width - _floorWidth - 16.0));
      _petX = _floorX + (_floorWidth - _petWidth) / 2;
      _petY = (screenSize.height - _petHeight - 190.0)
          .clamp(40.0, math.max(60.0, screenSize.height - 260.0));
      _initializedPosition = true;
    }

    setState(() {
      _animTick++;
      _idleTicksWithoutActivity++;

      if (_trickTicksRemaining > 0) {
        _trickTicksRemaining--;
        if (_trickTicksRemaining == 0) {
          _localTrickState = '';
        }
      }

      final bool canActAutonomously = _roamingEnabled &&
          !_isDragging &&
          !_isListening &&
          !_showContextMenu &&
          !_showScratchpad &&
          _trickTicksRemaining == 0;

      if (canActAutonomously && screenSize.width > 200) {
        _behaviorCounter++;

        final double distToCursor =
            ((_cursorX - (_petX + _petWidth / 2)).abs() +
                (_cursorY - (_petY + _petHeight / 2)).abs());
        if (_autonomousAction == 'sleep' && distToCursor < 180) {
          _idleTicksWithoutActivity = 0;
          _autonomousAction = 'curious';
          _behaviorCounter = 0;
        }

        if (_idleTicksWithoutActivity > 820) {
          _autonomousAction = 'sleep';
        } else if (_behaviorCounter > 65 && _autonomousAction == 'walk') {
          _autonomousAction =
              (math.Random().nextInt(3) == 0) ? 'curious' : 'idle';
          _behaviorCounter = 0;
        } else if (_behaviorCounter > 42 &&
            (_autonomousAction == 'idle' || _autonomousAction == 'curious')) {
          _autonomousAction = 'walk';
          _behaviorCounter = 0;
          if (math.Random().nextInt(3) == 0) {
            _walkDirection = -_walkDirection;
          }
        }

        if (_autonomousAction == 'walk') {
          // Creature walks back and forth ON TOP of its terrain floor box!
          final double step = 1.85 * _walkDirection;
          _petX += step;
          _facingLeft = _walkDirection < 0;

          final double minX = _floorX + 10.0;
          final double maxX =
              math.max(minX + 10.0, _floorX + _floorWidth - _petWidth - 10.0);
          if (_petX <= minX) {
            _petX = minX;
            _walkDirection = 1.0;
            _facingLeft = false;
          } else if (_petX >= maxX) {
            _petX = maxX;
            _walkDirection = -1.0;
            _facingLeft = true;
          }
        }
      } else if (!_roamingEnabled) {
        _autonomousAction = 'idle';
      }
    });

    _syncInteractiveRects();
  }

  void _syncInteractiveRects() {
    final double petW = _petWidth;
    final double petH = _petHeight;
    final Offset floorPos = _computeFloorPosition(petH);

    final List<List<double>> rects = [
      [_petX - 10, _petY - 8, petW + 20, petH + 16],
    ];

    if (_showSpeechBubble || _isListening) {
      rects.add([
        floorPos.dx - 8,
        floorPos.dy - 6,
        _floorWidth + 16,
        _currentFloorHeight + 16,
      ]);
    }

    if (_showScratchpad) {
      final Offset padPos = _computeScratchpadPosition();
      rects.add([padPos.dx - 8, padPos.dy - 8, _floorWidth + 16, 240.0]);
    }

    if (_showContextMenu) {
      final Offset menuPos = _computeMenuPosition(petW, petH);
      rects.add([menuPos.dx - 8, menuPos.dy - 8, 348.0, 520.0]);
    }

    _windowChannel.invokeMethod('setInteractiveRects', rects);
  }

  Offset _computeFloorPosition(double petH) {
    final double fy = _petY + petH - 8.0;
    return Offset(_floorX, fy);
  }

  Offset _computeScratchpadPosition() {
    final double py = math.max(12.0, _petY - 224.0);
    return Offset(_floorX, py);
  }

  Offset _computeMenuPosition(double petW, double petH) {
    final Size screen = MediaQuery.of(context).size;
    double mx = _floorX + _floorWidth + 12;
    if (screen.width > 0 && mx + 340 > screen.width) {
      mx = math.max(12.0, _floorX - 344);
    }
    double my = _petY - 120;
    if (screen.height > 0 && my + 520 > screen.height) {
      my = screen.height - 525;
    }
    my = math.max(12.0, my);
    return Offset(mx, my);
  }

  String _effectiveAnimState() {
    if (_trickTicksRemaining > 0 && _localTrickState.isNotEmpty) {
      return _localTrickState;
    }
    if (_isListening) {
      return _engineAnimState == 'idle' ? 'listen' : _engineAnimState;
    }
    if (_roamingEnabled && !_isDragging && !_showContextMenu) {
      return _autonomousAction;
    }
    return _engineAnimState;
  }

  bool get _isCultistCreature =>
      _activeCreature == 'cultist' ||
      _activeCreature == 'cultist_lunar' ||
      _activeCreature == 'monster';

  bool get _isPteroCreature =>
      _activeCreature == 'ptero' || _activeCreature == 'stego';

  Color _creatureAccentColor() {
    if (_activeCreature == 'trex') {
      return const Color(0xFF66BB6A); // Tier 3: Jurassic Emerald Green
    } else if (_activeCreature == 'cultist_lunar') {
      return const Color(0xFFFFF038); // Tier 2B: Lunatic Cultist Royal Gold
    } else if (_isCultistCreature) {
      return const Color(0xFFFFB300); // Tier 2A: Gungeon Ember Gold
    } else if (_activeCreature == 'custom') {
      return const Color(0xFF4DD0E1);
    } else {
      return const Color(0xFF26C6DA); // Tier 1: Pterodactyl Sky Cyan
    }
  }

  Color _fixCategoryColor(String? cat) {
    switch (cat) {
      case 'homophone':
        return const Color(0xFF00E5FF);
      case 'spelling':
        return const Color(0xFF69F0AE);
      case 'clarity':
        return const Color(0xFFFFD740);
      case 'grammar':
        return const Color(0xFFEA80FC);
      default:
        return const Color(0xFFFFAB40);
    }
  }

  void _switchCreatureTier(String creatureKey) {
    setState(() {
      _activeCreature = creatureKey;
      if (creatureKey == 'ptero') {
        _creatureName = 'Sky Pterodactyl';
        _creatureTier = 1;
        _creatureVram = '~0.5 GB VRAM';
        _modelName = 'small.en';
      } else if (creatureKey == 'cultist' || creatureKey == 'cultist_lunar') {
        _cultistSkin = creatureKey;
        _creatureName = creatureKey == 'cultist_lunar'
            ? 'Lunatic Beak Cultist'
            : 'Ember Cultist Scribe';
        _creatureTier = 2;
        _creatureVram = '~1.5 GB VRAM';
        _modelName = 'medium.en';
      } else if (creatureKey == 'trex') {
        _creatureName = 'Apex Green T-Rex';
        _creatureTier = 3;
        _creatureVram = '~2.0 GB VRAM';
        _modelName = 'large-v3-turbo';
      }
      _showCustomPathInput = creatureKey == 'custom';
    });
    _updateFocusAllowance();
    _postBackend('/switch_creature', {'creature': creatureKey});
  }

  void _toggleCultistSkin() {
    final String nextSkin =
        (_activeCreature == 'cultist_lunar') ? 'cultist' : 'cultist_lunar';
    _switchCreatureTier(nextSkin);
  }

  void _applyWordChoice({
    required int wordIndex,
    required String originalWord,
    required String replacement,
  }) {
    setState(() {
      _localTrickState = 'fixing';
      _trickTicksRemaining = 18;
      if (_polishedLiveText.isNotEmpty) {
        final List<String> toks = _polishedLiveText.split(' ');
        if (wordIndex >= 0 && wordIndex < toks.length) {
          if (replacement == '[DROP]') {
            toks.removeAt(wordIndex);
          } else {
            final RegExp m =
                RegExp(r"^([^A-Za-z']*)([A-Za-z']+)([^A-Za-z']*)$");
            final RegExpMatch? match = m.firstMatch(toks[wordIndex]);
            if (match != null) {
              toks[wordIndex] =
                  '${match.group(1)}$replacement${match.group(3)}';
            } else {
              toks[wordIndex] = replacement;
            }
          }
          _polishedLiveText = toks.join(' ');
        }
      }
      _writingScore = (_writingScore + 3).clamp(0, 100);
    });
    _windowChannel.invokeMethod('restoreExternalFocus');
    _postBackend('/apply_recommendation', {
      'original': originalWord,
      'replacement': replacement,
      'word_index': wordIndex,
      'replace_all': false,
    });
  }

  void _applyFullSentenceVariant(String newSentence) {
    if (newSentence.isEmpty) return;
    final String old = _polishedLiveText;
    setState(() {
      _localTrickState = 'fixing';
      _trickTicksRemaining = 20;
      _polishedLiveText = newSentence;
      _writingScore = 100;
    });
    _windowChannel.invokeMethod('restoreExternalFocus');
    _postBackend('/apply_recommendation', {
      'original': old,
      'replacement': newSentence,
      'word_index': -1,
      'replace_all': true,
    });
  }

  void _applyGrammarlyRecommendation(Map<String, String> rec) {
    final String orig = rec['original'] ?? '';
    final String repl = rec['replacement'] ?? '';
    if (orig.isEmpty || repl.isEmpty) return;

    setState(() {
      _localTrickState = 'fixing';
      _trickTicksRemaining = 18;
      if (_polishedLiveText.isNotEmpty) {
        _polishedLiveText = _polishedLiveText.replaceFirst(
          RegExp(RegExp.escape(orig), caseSensitive: false),
          repl,
        );
      }
      _grammarlyRecommendations
          .removeWhere((item) => item['original'] == orig);
      _writingScore = (_writingScore + 4).clamp(0, 100);
    });
    _windowChannel.invokeMethod('restoreExternalFocus');
    _postBackend('/apply_recommendation', {
      'original': orig,
      'replacement': repl,
    });
  }

  @override
  Widget build(BuildContext context) {
    final double petW = _petWidth;
    final double petH = _petHeight;
    final Offset floorPos = _computeFloorPosition(petH);
    final Offset padPos = _computeScratchpadPosition();
    final Offset menuPos = _computeMenuPosition(petW, petH);
    final String animState = _effectiveAnimState();
    final Color accent = _creatureAccentColor();

    final double lookDx =
        ((_cursorX - (_petX + petW / 2)) / 240.0).clamp(-1.0, 1.0);
    final double lookDy =
        ((_cursorY - (_petY + petH / 2)) / 200.0).clamp(-1.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Dyslexia Live Scratchpad & Rewriting Studio (opens above creature when requested)
          if (_showScratchpad)
            Positioned(
              left: padPos.dx,
              top: padPos.dy,
              child: _buildScratchpadDrawer(accent),
            ),

          // 2. UNDER-CREATURE LIVING TERRAIN FLOOR BOX (Flat by default, expands on click!)
          if (_showSpeechBubble || _isListening)
            Positioned(
              left: floorPos.dx,
              top: floorPos.dy,
              child: GestureDetector(
                onPanStart: (_) {
                  setState(() {
                    _isDragging = true;
                    _idleTicksWithoutActivity = 0;
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _moveSanctuaryBy(details.delta.dx, details.delta.dy);
                  });
                  _syncInteractiveRects();
                },
                onPanEnd: (_) {
                  setState(() {
                    _isDragging = false;
                  });
                  _syncInteractiveRects();
                },
                child: _buildTerrainFloorPlatform(accent),
              ),
            ),

          // 3. The Active 56x40 Pixel Creature Standing ON TOP of the Terrain Floor
          Positioned(
            left: _petX,
            top: _petY,
            child: Listener(
              onPointerDown: (PointerDownEvent event) {
                _idleTicksWithoutActivity = 0;
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons == kSecondaryMouseButton) {
                  setState(() {
                    _showContextMenu = !_showContextMenu;
                  });
                  _updateFocusAllowance();
                  _syncInteractiveRects();
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _idleTicksWithoutActivity = 0;
                  setState(() {
                    _setFloorExpanded(true);
                  });
                  _syncInteractiveRects();
                  _windowChannel.invokeMethod('restoreExternalFocus');
                  _postBackend('/toggle_listen', {});
                },
                onDoubleTap: () {
                  setState(() {
                    _localTrickState = 'roar';
                    _trickTicksRemaining = 24;
                  });
                },
                onPanStart: (_) {
                  setState(() {
                    _isDragging = true;
                    _idleTicksWithoutActivity = 0;
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _moveSanctuaryBy(details.delta.dx, details.delta.dy);
                    if (details.delta.dx.abs() > 0.5) {
                      _facingLeft = details.delta.dx < 0;
                    }
                  });
                  _syncInteractiveRects();
                },
                onPanEnd: (_) {
                  setState(() {
                    _isDragging = false;
                  });
                  _syncInteractiveRects();
                },
                child: PixelCreatureWidget(
                  creature: _activeCreature,
                  animState: animState,
                  tick: _animTick,
                  flipHorizontal: _facingLeft,
                  pixelScale: _pixelScale,
                  audioLevel: _audioLevel,
                  lookDx: lookDx,
                  lookDy: lookDy,
                  customSpritePath: _customSpritePath,
                ),
              ),
            ),
          ),

          // 4. Right-Click Retro Pixel Context Menu
          if (_showContextMenu)
            Positioned(
              left: menuPos.dx,
              top: menuPos.dy,
              child: _buildPixelContextMenu(accent),
            ),
        ],
      ),
    );
  }

  Widget _buildTerrainFloorPlatform(Color accent) {
    final Color borderCol = _isListening
        ? const Color(0xFF00E676)
        : (_isCultistCreature
            ? const Color(0xFFFFD54F)
            : const Color(0xFF43A047));
    final Color groundBg = _isCultistCreature
        ? const Color(0xF6110B1A)
        : const Color(0xF60F1712);

    return SizedBox(
      width: _floorWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Living Pixel-Art Terrain Growing on Top of the Floor Box!
          PixelTerrainFloorWidget(
            creature: _activeCreature,
            tick: _animTick,
            isActive: _isListening,
            width: _floorWidth,
            height: 18.0,
          ),

          // 2. Compact Flat Bar OR Expanded Live Dictation & Word-Choice Sanctuary
          if (!_isFloorExpanded)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _setFloorExpanded(true);
                });
                _syncInteractiveRects();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: groundBg,
                  border: Border.all(color: borderCol, width: 2.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xAA000000),
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 5),
                      color: _backendConnected
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252),
                    ),
                    _miniPixelButton(
                      label: _isListening ? '■ STOP' : '● REC',
                      color: _isListening
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF00E676),
                      tooltip: 'Start/stop live voice transcription (F8)',
                      onTap: () {
                        setState(() {
                          _setFloorExpanded(true);
                        });
                        _syncInteractiveRects();
                        _windowChannel.invokeMethod('restoreExternalFocus');
                        _postBackend('/toggle_listen', {});
                      },
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _polishedLiveText.isNotEmpty
                            ? '"$_polishedLiveText"'
                            : 'TIER $_creatureTier: ${_creatureName.toUpperCase()} • Click creature to transcribe',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _polishedLiveText.isNotEmpty
                              ? const Color(0xFFFFF59D)
                              : const Color(0xFFE0F2F1),
                          fontSize: 10.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        border: Border.all(color: accent, width: 1),
                      ),
                      child: Text(
                        '$_writingScore★',
                        style: TextStyle(
                          color: accent,
                          fontSize: 9.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '[▼ EXPAND]',
                      style: TextStyle(
                        color: accent,
                        fontSize: 9.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildExpandedFloorBox(accent, borderCol, groundBg),
        ],
      ),
    );
  }

  Widget _buildExpandedFloorBox(
    Color accent,
    Color borderCol,
    Color groundBg,
  ) {
    final Map<String, String>? latestFix =
        _recentFixes.isNotEmpty ? _recentFixes.last : null;

    // Pick active word exploration (either user-selected word index or first word with alternatives)
    Map<String, dynamic>? activeWordExp;
    if (_wordExplorations.isNotEmpty) {
      if (_selectedWordIndex >= 0 &&
          _selectedWordIndex < _wordExplorations.length) {
        final cand = _wordExplorations[_selectedWordIndex];
        if ((cand['alternatives'] as List?)?.isNotEmpty ?? false) {
          activeWordExp = cand;
        }
      }
      activeWordExp ??= _wordExplorations.cast<Map<String, dynamic>?>().firstWhere(
            (w) =>
                w != null &&
                ((w['alternatives'] as List?)?.isNotEmpty ?? false),
            orElse: () => null,
          );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: groundBg,
        border: Border.all(color: borderCol, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0xBB000000),
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A. 3-Tier Creature & Whisper Progression Selector + Cultist Skin Toggle + Collapse
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _tierPillButton(
                      tierNumber: 1,
                      title: 'PTERO',
                      subtitle: 'Light 0.5G',
                      creatureKey: 'ptero',
                      selected: _isPteroCreature,
                      color: const Color(0xFF26C6DA),
                    ),
                    const SizedBox(width: 4),
                    _tierPillButton(
                      tierNumber: 2,
                      title: 'CULTIST',
                      subtitle: _activeCreature == 'cultist_lunar'
                          ? 'Lunar 1.5G'
                          : 'Ember 1.5G',
                      creatureKey: _cultistSkin,
                      selected: _isCultistCreature,
                      color: const Color(0xFFFFD54F),
                    ),
                    const SizedBox(width: 4),
                    _tierPillButton(
                      tierNumber: 3,
                      title: 'T-REX',
                      subtitle: 'Apex 2.0G',
                      creatureKey: 'trex',
                      selected: _activeCreature == 'trex',
                      color: const Color(0xFF66BB6A),
                    ),
                  ],
                ),
              ),
              if (_isCultistCreature) ...[
                const SizedBox(width: 4),
                _miniPixelButton(
                  label: _activeCreature == 'cultist_lunar' ? 'ROBE: BLUE' : 'ROBE: RED',
                  color: _activeCreature == 'cultist_lunar'
                      ? const Color(0xFF42A5F5)
                      : const Color(0xFFFF7043),
                  tooltip:
                      'Swap Cultist outfit between Gungeon Ember Robe and Terraria Lunatic Beak Mask!',
                  onTap: _toggleCultistSkin,
                ),
              ],
              const SizedBox(width: 4),
              _miniPixelButton(
                label: '▲ FLAT',
                color: const Color(0xFF90A4AE),
                tooltip: 'Collapse floor into a flat terrain strip',
                onTap: () {
                  setState(() {
                    _setFloorExpanded(false);
                  });
                  _syncInteractiveRects();
                },
              ),
            ],
          ),

          const SizedBox(height: 6),

          // B. Main Dictation Controls & Target Window Indicator
          Row(
            children: [
              _miniPixelButton(
                label: _isListening ? '■ STOP' : '● REC',
                color: _isListening
                    ? const Color(0xFFFF5252)
                    : const Color(0xFF00E676),
                tooltip: 'Start or stop live voice dictation (or press F8)',
                onTap: () {
                  _windowChannel.invokeMethod('restoreExternalFocus');
                  _postBackend('/toggle_listen', {});
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TARGET: $_targetWindow',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF80D8FF),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _modelLoading
                          ? 'Loading $_modelName ($_creatureVram)...'
                          : 'Tier $_creatureTier: $_modelName ($_creatureVram) • $_computeBackend',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF90A4AE),
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ),
              _miniPixelButton(
                label: 'FIX',
                color: const Color(0xFF00E5FF),
                tooltip: 'Fix highlighted text on page (F9)',
                onTap: () {
                  _windowChannel.invokeMethod('restoreExternalFocus');
                  _postBackend('/review_selection', {});
                },
              ),
              const SizedBox(width: 4),
              _miniPixelButton(
                label: 'READ',
                color: const Color(0xFFFFD740),
                tooltip: 'Read text aloud (Dyslexia TTS)',
                onTap: () =>
                    _postBackend('/speak', {'text': _polishedLiveText}),
              ),
              const SizedBox(width: 4),
              _miniPixelButton(
                label: 'PAD',
                color: _showScratchpad
                    ? const Color(0xFF69F0AE)
                    : const Color(0xFFB388FF),
                tooltip: 'Open Dyslexia & Grammarly Writing Studio',
                onTap: () {
                  setState(() {
                    _showScratchpad = !_showScratchpad;
                  });
                  _updateFocusAllowance();
                  _syncInteractiveRects();
                },
              ),
            ],
          ),

          const SizedBox(height: 5),

          // C. Live Pixel Audio Meter + Status Message
          Row(
            children: [
              _buildPixelAudioMeter(),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _statusMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE0F2F1),
                    fontSize: 10.0,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          // D. Interactive Live Dictation Stream Box (Click ANY word to see alternatives!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF17202E),
              border: Border.all(color: const Color(0xFF2E3B4E)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _polishedLiveText.isEmpty
                      ? const Text(
                          'Click your companion above (or ● REC) and speak — words appear live here and you can click any word to swap synonyms or sound-alikes!',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF78909C),
                            fontSize: 9.5,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_rawLiveText.isNotEmpty &&
                                _rawLiveText.trim() !=
                                    _polishedLiveText.trim())
                              Text(
                                'Heard: $_rawLiveText',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF90A4AE),
                                  fontSize: 9.0,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            _buildInteractiveWordStream(),
                          ],
                        ),
                ),
                if (_polishedLiveText.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _miniPixelButton(
                    label: 'INSERT',
                    color: const Color(0xFF69F0AE),
                    tooltip: 'Insert this text directly into the target window',
                    onTap: () {
                      _windowChannel.invokeMethod(
                        'typeInPlace',
                        {'backspaces': 0, 'text': '$_polishedLiveText '},
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 5),

          // E. Next-Gen Word Explorer, 1-Click Sentence Rewrites & Grammarly 4-Pillar Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF181224),
              border: Border.all(color: const Color(0xFF6A1B9A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'GRAMMARLY SCORE: $_writingScore/100',
                      style: const TextStyle(
                        color: Color(0xFFFFEE18),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Tone: $_detectedTone • Corr ${_pillarScores['correctness'] ?? 100} • Clar ${_pillarScores['clarity'] ?? 100}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCE93D8),
                          fontSize: 8.5,
                        ),
                      ),
                    ),
                    // 1-Click Full Sentence Rewrite Variant Buttons
                    for (final variant in _sentenceVariants.take(2))
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: _miniPixelButton(
                          label: '✨ ${variant['label']}',
                          color: const Color(0xFF00E5FF),
                          tooltip:
                              '${variant['description']}: "${variant['text']}"',
                          onTap: () =>
                              _applyFullSentenceVariant(variant['text'] ?? ''),
                        ),
                      ),
                  ],
                ),

                // Interactive Word-Choice Alternatives ("Did you mean?" / Synonyms / Drop Hedge)
                if (activeWordExp != null) ...[
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          activeWordExp['kind'] == 'confusable'
                              ? '🔍 SOUND-ALIKE "${activeWordExp['word']}": '
                              : (activeWordExp['kind'] == 'hedging'
                                  ? '✂ HEDGE "${activeWordExp['word']}": '
                                  : '💡 SWAP "${activeWordExp['word']}": '),
                          style: const TextStyle(
                            color: Color(0xFF80D8FF),
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ...(activeWordExp['alternatives'] as List)
                            .take(4)
                            .map((dynamic altObj) {
                          final String alt = '$altObj';
                          final bool isDrop = alt == '[DROP]';
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _miniPixelButton(
                              label: isDrop ? '✖ DROP WORD' : alt,
                              color: isDrop
                                  ? const Color(0xFFFF8A80)
                                  : const Color(0xFF69F0AE),
                              tooltip: isDrop
                                  ? 'Remove "${activeWordExp!['word']}" from the sentence'
                                  : 'Replace "${activeWordExp!['word']}" with "$alt" on page',
                              onTap: () => _applyWordChoice(
                                wordIndex:
                                    (activeWordExp!['index'] as num?)?.toInt() ??
                                        0,
                                originalWord: '${activeWordExp['word']}',
                                replacement: alt,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],

                // Phrase-level Grammarly Recommendations or Recent Fix Badge
                if (_grammarlyRecommendations.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  ..._grammarlyRecommendations.take(1).map((rec) {
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            '✦ [${(rec['pillar'] ?? 'style').toUpperCase()}] "${rec['original']}" → "${rec['replacement']}" (${rec['reason']})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFF59D),
                              fontSize: 9.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _miniPixelButton(
                          label: 'HELPER FIX',
                          color: const Color(0xFF00E676),
                          tooltip:
                              'Let your helper replace this phrase on the page',
                          onTap: () => _applyGrammarlyRecommendation(rec),
                        ),
                      ],
                    );
                  }),
                ] else if (latestFix != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '★ Auto-Fixed [${(latestFix['category'] ?? 'fix').toUpperCase()}]: "${latestFix['original']}" → "${latestFix['replacement']}" (${latestFix['reason']})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _fixCategoryColor(latestFix['category']),
                      fontSize: 8.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the live polished text as clickable word tokens so the user can
  /// tap ANY word that has sound-alike or vocabulary suggestions!
  Widget _buildInteractiveWordStream() {
    if (_wordExplorations.isEmpty) {
      return Text(
        '"$_polishedLiveText"',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFFFF59D),
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: List.generate(_wordExplorations.length, (i) {
        final Map<String, dynamic> exp = _wordExplorations[i];
        final String display = '${exp['display'] ?? exp['word'] ?? ''}';
        final String kind = '${exp['kind'] ?? 'normal'}';
        final List<dynamic> alts =
            (exp['alternatives'] as List<dynamic>?) ?? const [];
        final bool hasAlts = alts.isNotEmpty;
        final bool isSelected = _selectedWordIndex == i;

        Color underlineCol = Colors.transparent;
        if (kind == 'confusable') {
          underlineCol = const Color(0xFF00E5FF);
        } else if (kind == 'hedging') {
          underlineCol = const Color(0xFFFF8A80);
        } else if (kind == 'upgrade') {
          underlineCol = const Color(0xFFFFEE18);
        }

        return GestureDetector(
          onTap: hasAlts
              ? () {
                  setState(() {
                    _selectedWordIndex = i;
                  });
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF283593)
                  : (hasAlts ? const Color(0xFF1E293B) : Colors.transparent),
              border: Border(
                bottom: BorderSide(
                  color: underlineCol,
                  width: hasAlts ? 2.0 : 0.0,
                ),
              ),
            ),
            child: Text(
              display,
              style: TextStyle(
                color: hasAlts
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFFFFF59D),
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _tierPillButton({
    required int tierNumber,
    required String title,
    required String subtitle,
    required String creatureKey,
    required bool selected,
    required Color color,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchCreatureTier(creatureKey),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1F2D3D) : const Color(0xFF121822),
            border: Border.all(
              color: selected ? color : const Color(0xFF37474F),
              width: selected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'T$tierNumber: $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? color : const Color(0xFFB0BEC5),
                  fontSize: 9.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFECEFF1)
                      : const Color(0xFF78909C),
                  fontSize: 8.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPixelAudioMeter() {
    const int totalBars = 10;
    final int activeBars =
        (_audioLevel * totalBars).round().clamp(0, totalBars);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalBars, (i) {
        final bool on = i < activeBars;
        Color barCol = const Color(0xFF263238);
        if (on) {
          if (i >= 7) {
            barCol = const Color(0xFFFF5252);
          } else if (i >= 4) {
            barCol = const Color(0xFFFFD740);
          } else {
            barCol = const Color(0xFF00E676);
          }
        }
        return Container(
          width: 4,
          height: 11,
          margin: const EdgeInsets.only(right: 2),
          color: barCol,
        );
      }),
    );
  }

  Widget _buildScratchpadDrawer(Color accent) {
    return Container(
      width: _floorWidth,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xF7111622),
        border: Border.all(color: const Color(0xFFB388FF), width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA000000),
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DYSLEXIA & GRAMMARLY WRITING STUDIO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFB388FF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'Words: $_totalWordsWritten • Auto-Fixes: $_totalFixesApplied • Score: $_writingScore/100',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF90A4AE),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showScratchpad = false;
                  });
                  _updateFocusAllowance();
                  _syncInteractiveRects();
                },
                child: const Text(
                  ' [X]',
                  style: TextStyle(
                    color: Color(0xFFFF5252),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _miniPixelButton(
                label: 'POLISH & FIX',
                color: const Color(0xFF00E5FF),
                tooltip: 'Fix spelling, homophones, clarity & grammar in pad',
                onTap: () {
                  _postBackend(
                    '/analyze_text',
                    {'text': _scratchpadController.text},
                  );
                },
              ),
              _miniPixelButton(
                label: 'TYPE TO APP',
                color: const Color(0xFF00E676),
                tooltip: 'Polishes and types this text into your active window',
                onTap: () {
                  _windowChannel.invokeMethod('setAllowFocus', false);
                  _postBackend(
                    '/type_text',
                    {'text': _scratchpadController.text},
                  );
                },
              ),
              _miniPixelButton(
                label: 'CLEAR',
                color: const Color(0xFFFF8A80),
                tooltip: 'Clear scratchpad',
                onTap: () {
                  _scratchpadController.clear();
                  _lastSyncedSessionTranscript = '';
                  _postBackend('/clear_history', {});
                },
              ),
              for (final tone in ['clear', 'formal', 'casual'])
                _miniPixelButton(
                  label: tone.toUpperCase(),
                  color: _writingTone == tone
                      ? const Color(0xFF69F0AE)
                      : const Color(0xFF546E7A),
                  tooltip: 'Set writing tone to $tone',
                  onTap: () {
                    setState(() {
                      _writingTone = tone;
                    });
                    _postBackend('/set_tone', {'tone': tone});
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 115,
            child: TextField(
              controller: _scratchpadController,
              maxLines: 5,
              style: const TextStyle(
                color: Color(0xFFFFF9C4),
                fontSize: 13.0,
                height: 1.45,
                letterSpacing: 0.5,
              ),
              decoration: const InputDecoration(
                hintText:
                    'Speak or type here... Words stream live and get auto-fixed for dyslexia, homophones & Grammarly clarity!',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                filled: true,
                fillColor: Color(0xFF141B29),
                contentPadding: EdgeInsets.all(8),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF37474F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniPixelButton({
    required String label,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF1D2432),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPixelContextMenu(Color accent) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xF711151E),
        border: Border.all(color: accent, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA000000),
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PIXEL ASSISTANT & TIER MENU',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showContextMenu = false;
                    _showCustomPathInput = false;
                  });
                  _updateFocusAllowance();
                  _syncInteractiveRects();
                },
                child: const Text(
                  '[X]',
                  style: TextStyle(
                    color: Color(0xFFFF5252),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF37474F), height: 10),

          const Text(
            '3-TIER MODEL & CREATURE PROGRESSION:',
            style: TextStyle(
              color: Color(0xFF90A4AE),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _creatureOptionTile(
            keyId: 'ptero',
            selected: _isPteroCreature,
            label: 'Tier 1: Sky Pterodactyl (small.en • 0.5GB Fast)',
            color: const Color(0xFF26C6DA),
          ),
          _creatureOptionTile(
            keyId: 'cultist',
            selected: _activeCreature == 'cultist' || _activeCreature == 'monster',
            label: 'Tier 2A: Ember Cultist (Gungeon Robe • 1.5GB Grammarly)',
            color: const Color(0xFFFFB300),
          ),
          _creatureOptionTile(
            keyId: 'cultist_lunar',
            selected: _activeCreature == 'cultist_lunar',
            label: 'Tier 2B: Lunatic Beak Cultist (Terraria • 1.5GB Grammarly)',
            color: const Color(0xFF42A5F5),
          ),
          _creatureOptionTile(
            keyId: 'trex',
            selected: _activeCreature == 'trex',
            label: 'Tier 3: Green T-Rex (large-v3-turbo • 2.0GB Max)',
            color: const Color(0xFF66BB6A),
          ),
          _creatureOptionTile(
            keyId: 'custom',
            selected: _activeCreature == 'custom',
            label: 'Custom Pixel Avatar (.png/.gif)',
            color: const Color(0xFF4DD0E1),
          ),

          if (_showCustomPathInput || _activeCreature == 'custom') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 26,
                    child: TextField(
                      controller: _spritePathController,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      decoration: const InputDecoration(
                        hintText: 'Path to pixel sprite .png/.gif...',
                        hintStyle:
                            TextStyle(color: Colors.white38, fontSize: 10),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4DD0E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF00E5FF)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _miniPixelButton(
                  label: 'LOAD',
                  color: const Color(0xFF4DD0E1),
                  tooltip: 'Load custom sprite image',
                  onTap: () {
                    setState(() {
                      _customSpritePath = _spritePathController.text.trim();
                    });
                  },
                ),
              ],
            ),
          ],

          const Divider(color: Color(0xFF37474F), height: 12),

          const Text(
            'LOCAL GRAMMARLY & DYSLEXIA PILLARS:',
            style: TextStyle(
              color: Color(0xFF90A4AE),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _ruleToggleTile(
            ruleKey: 'homophones',
            label: 'Homophones (their/they\'re, to/too)',
          ),
          _ruleToggleTile(
            ruleKey: 'dyslexia_spelling',
            label: 'Dyslexia Spelling & Phonetic Fixes',
          ),
          _ruleToggleTile(
            ruleKey: 'clarity_conciseness',
            label: 'Grammarly Clarity & Conciseness',
          ),
          _ruleToggleTile(
            ruleKey: 'speech_cleanup',
            label: 'Strip Fillers (um/uh) & Stutters',
          ),
          _ruleToggleTile(
            ruleKey: 'grammar_structure',
            label: 'Auto-Capitalize & Verb Agreement',
          ),

          const Divider(color: Color(0xFF37474F), height: 12),

          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _miniPixelButton(
                label: _roamingEnabled ? 'WALK: ON' : 'WALK: OFF',
                color: _roamingEnabled
                    ? const Color(0xFF69F0AE)
                    : const Color(0xFFB0BEC5),
                tooltip: 'Toggle pacing along the terrain floor',
                onTap: () {
                  setState(() {
                    _roamingEnabled = !_roamingEnabled;
                  });
                },
              ),
              _miniPixelButton(
                label: _isFloorExpanded ? 'FLOOR: FULL' : 'FLOOR: FLAT',
                color: const Color(0xFFFFD740),
                tooltip: 'Toggle between flat terrain bar and expanded HUD',
                onTap: () {
                  setState(() {
                    _setFloorExpanded(!_isFloorExpanded);
                  });
                  _syncInteractiveRects();
                },
              ),
              _miniPixelButton(
                label: 'ACTION!',
                color: const Color(0xFFFF80AB),
                tooltip: 'Play special creature animation',
                onTap: () {
                  setState(() {
                    _localTrickState = 'roar';
                    _trickTicksRemaining = 24;
                  });
                },
              ),
              _miniPixelButton(
                label: 'SIZE',
                color: const Color(0xFF80D8FF),
                tooltip: 'Cycle pixel art scale',
                onTap: () {
                  setState(() {
                    _pixelScale =
                        _pixelScale >= 6.5 ? 4.0 : (_pixelScale + 1.0);
                  });
                  _syncInteractiveRects();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                _postBackend('/shutdown', {});
                _backendProcess?.kill();
                _windowChannel.invokeMethod('quitApp');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E1818),
                  border:
                      Border.all(color: const Color(0xFFFF5252), width: 1.5),
                ),
                child: const Center(
                  child: Text(
                    'QUIT PIXEL ASSISTANT',
                    style: TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _creatureOptionTile({
    required String keyId,
    required bool selected,
    required String label,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () => _switchCreatureTier(keyId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E2B38) : Colors.transparent,
          border: Border.all(
            color: selected ? color : const Color(0xFF263238),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(
              selected ? '▶ ' : '  ',
              style: TextStyle(color: color, fontSize: 10),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? color : const Color(0xFFCFD8DC),
                  fontSize: 10.0,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleToggleTile({
    required String ruleKey,
    required String label,
  }) {
    final bool enabled = _grammarRules[ruleKey] ?? true;
    return GestureDetector(
      onTap: () {
        final Map<String, bool> updated = Map<String, bool>.from(_grammarRules);
        updated[ruleKey] = !enabled;
        setState(() {
          _grammarRules = updated;
        });
        _postBackend('/update_rules', {'rules': updated});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          children: [
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFF00E676)
                    : const Color(0xFF263238),
                border: Border.all(color: Colors.white70, width: 1),
              ),
              child: enabled
                  ? const Center(
                      child: Text(
                        '✓',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFFECEFF1)
                      : const Color(0xFF78909C),
                  fontSize: 10.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
