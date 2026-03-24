// lib/main.dart
// VoiceBridge Flutter — entry point and app shell.
// No Google services. Full on-device AI pipeline.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/translator_screen.dart';
import 'screens/model_setup_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for consistent UX
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Init app state (loads prefs + model dirs)
  await AppState.instance.init();

  runApp(
    ChangeNotifierProvider.value(
      value: AppState.instance,
      child: const VoiceBridgeApp(),
    ),
  );
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
      theme:      AppTheme.light,
      darkTheme:  AppTheme.dark,
      themeMode:  isDark ? ThemeMode.dark : ThemeMode.light,
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

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;

  static const _tabs = [
    _Tab(label: 'Translate',  icon: Icons.translate,        screen: TranslatorScreen()),
    _Tab(label: 'AI Models',  icon: Icons.model_training,   screen: ModelSetupScreen()),
    _Tab(label: 'Settings',   icon: Icons.settings,         screen: SettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('🌐 ', style: TextStyle(fontSize: 22)),
          const Text('VoiceBridge', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          // Model status dot
          _ModelDot(state: state),
          const SizedBox(width: 4),
          // Theme toggle
          IconButton(
            icon: Icon(state.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round),
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
        destinations: _tabs.map((t) => NavigationDestination(
          icon:  Icon(t.icon),
          label: t.label,
        )).toList(),
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
    final marianOk  = state.isMarianReady;
    final whisperOk = state.isWhisperReady;
    final allOk     = marianOk && whisperOk;

    final color = allOk
        ? AppTheme.accent
        : (marianOk || whisperOk ? AppTheme.warning : AppTheme.danger);

    final tooltip = allOk
        ? '✅ All models ready'
        : '${marianOk ? '✅' : '❌'} Marian  |  ${whisperOk ? '✅' : '❌'} Whisper';

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)],
        ),
      ),
    );
  }
}
