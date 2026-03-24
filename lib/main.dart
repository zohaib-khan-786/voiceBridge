// lib/main.dart
// VoiceBridge Flutter — entry point and app shell.
// No Google services. Full on-device AI pipeline.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/overlay_channel.dart';
import 'package:voicebridge/services/model_manager.dart';
import 'providers/app_state.dart';
import 'screens/translator_screen.dart';
import 'screens/model_setup_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/overlay_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for consistent UX
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Show splash screen while initializing
  runApp(const SplashScreen());

  // Initialize app state in background
  await AppState.instance.init();

  // Run main app
  runApp(
    ChangeNotifierProvider.value(
      value: AppState.instance,
      child: const VoiceBridgeApp(),
    ),
  );
}

// ── Splash Screen ───────────────────────────────────────────────────────────

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.translate,
                  size: 50,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'VoiceBridge',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Loading models...',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'This may take a few seconds on first launch',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Root app ──────────────────────────────────────────────────────────────────

class VoiceBridgeApp extends StatelessWidget {
  const VoiceBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<AppState, bool>((s) => s.isDarkMode);

    return MaterialApp(
      title: 'VoiceBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const _AppShell(),
    );
  }
}

// ── App shell (bottom navigation) ─────────────────────────────────────────────

class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final OverlayChannel _overlay = OverlayChannel();
  bool _overlayRunning = false;
  bool _isInitializing = true;
  String _initMessage = 'Checking models...';

  static const _tabs = [
    _Tab(label: 'Translate', icon: Icons.translate, screen: TranslatorScreen()),
    _Tab(
        label: 'AI Models',
        icon: Icons.model_training,
        screen: ModelSetupScreen()),
    _Tab(label: 'Settings', icon: Icons.settings, screen: SettingsScreen()),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForBubbleTap();
    _initializeModels();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle if needed
    if (state == AppLifecycleState.resumed) {
      // Refresh model status when app resumes
      context.read<AppState>().refreshModelStatus();
    }
  }

// lib/main.dart - Updated _initializeModels method

  Future<void> _initializeModels() async {
    setState(() {
      _isInitializing = true;
      _initMessage = 'Checking model files...';
    });

    try {
      final appState = context.read<AppState>();

      // Small delay to ensure UI is rendered
      await Future.delayed(const Duration(milliseconds: 100));

      // Refresh all model statuses
      setState(() {
        _initMessage = 'Checking all models...';
      });
      await appState.refreshModelStatus();

      // Get status
      final marianOk = appState.isMarianReady;
      final whisperOk = appState.isWhisperReady;
      final sttOk = appState.modelStatus.stt == ModelStatus.ready;

      // Update message based on status
      if (marianOk && whisperOk) {
        setState(() {
          _initMessage = '✅ All models ready!';
        });
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        List<dynamic> missing = [];
        if (!marianOk) missing.add('Marian');
        if (!whisperOk) missing.add('Whisper');
        setState(() {
          _initMessage =
              '⚠️ Missing: ${missing.join(", ")} models. Go to AI Models tab to download.';
        });
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      print('Error during model initialization: $e');
      setState(() {
        _initMessage = 'Error loading models: $e';
      });
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  /// Listen for "show_drawer" event from the native bubble tap.
  void _listenForBubbleTap() {
    _overlay.events.listen((event) {
      if (event == 'show_drawer' && mounted) {
        OverlayScreen.show(context);
      }
    });
  }

  // ── Bubble toggle ─────────────────────────────────────────────────────

  Future<void> _toggleBubble() async {
    if (_overlayRunning) {
      await _overlay.stopOverlayService();
      setState(() => _overlayRunning = false);
      return;
    }

    final hasPerm = await _overlay.checkOverlayPermission();
    if (!hasPerm) {
      _showPermissionDialog();
      return;
    }

    final started = await _overlay.startOverlayService();
    if (started && mounted) {
      setState(() => _overlayRunning = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🌐 Bubble is active — switch to WhatsApp!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Overlay Permission Required'),
        content: const Text(
          'VoiceBridge needs "Display over other apps" permission '
          'to show the floating bubble over WhatsApp.\n\n'
          'Tap OK to open Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _overlay.requestOverlayPermission();
            },
            child: const Text('OK — Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    // Show loading screen while initializing
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _initMessage,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait...',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('🌐 ', style: TextStyle(fontSize: 22)),
          const Text('VoiceBridge',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          // Model status dot
          _ModelDot(state: state),
          const SizedBox(width: 4),
          // Theme toggle
          IconButton(
            icon: Icon(
                state.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round),
            tooltip: 'Toggle theme',
            onPressed: () => context.read<AppState>().toggleTheme(),
          ),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.dividerColor),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  label: t.label,
                ))
            .toList(),
      ),
      // ── Floating bubble toggle FAB ───────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleBubble,
        backgroundColor: _overlayRunning ? AppTheme.danger : AppTheme.accent,
        icon: Icon(_overlayRunning ? Icons.stop : Icons.bubble_chart),
        label: Text(
          _overlayRunning ? 'Stop Bubble' : 'Start Bubble',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final Widget screen;
  const _Tab({required this.label, required this.icon, required this.screen});
}

// ── Model status indicator dot ────────────────────────────────────────────────

class _ModelDot extends StatelessWidget {
  final AppState state;
  const _ModelDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final marianOk = state.isMarianReady;
    final whisperOk = state.isWhisperReady;
    final allOk = marianOk && whisperOk;

    final color = allOk
        ? AppTheme.accent
        : (marianOk || whisperOk ? AppTheme.warning : AppTheme.danger);

    final tooltip = allOk
        ? '✅ All models ready'
        : '${marianOk ? '✅' : '❌'} Marian  |  ${whisperOk ? '✅' : '❌'} Whisper';

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)],
        ),
      ),
    );
  }
}
