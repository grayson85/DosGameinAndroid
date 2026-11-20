import 'package:flutter/material.dart';

import 'features/library/library_page.dart';
import 'features/settings/settings_page.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DosboxCnApp());
}

class DosboxCnApp extends StatelessWidget {
  const DosboxCnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DosBox CN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00ACC1),
        scaffoldBackgroundColor: const Color(0xFF12141A),
      ),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _tabIndex = 0;
  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    StorageService.instance.loadSettings().then((s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          LibraryPage(settings: _settings),
          SettingsPage(
            settings: _settings,
            onSettingsChanged: (next) => setState(() => _settings = next),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.videogame_asset_outlined),
            selectedIcon: Icon(Icons.videogame_asset),
            label: '游戏库',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
