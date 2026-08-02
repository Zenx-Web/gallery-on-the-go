import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_background.dart';
import 'flashcards_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'planner_screen.dart';
import 'scanner_screen.dart';
import 'status_screen.dart';

/// Root scaffold — holds the StudyVault bottom nav and keeps all tabs alive
/// via [IndexedStack]. The Gallery tab renders [StatusScreen] unchanged;
/// the existing permission flow and background service are untouched.
class StudyVaultShell extends StatefulWidget {
  const StudyVaultShell({super.key});

  @override
  State<StudyVaultShell> createState() => _StudyVaultShellState();
}

class _StudyVaultShellState extends State<StudyVaultShell> {
  int _selectedIndex = 0;

  void _switchTab(int index) => setState(() => _selectedIndex = index);

  // Rebuilt on every tab switch (not cached) so ScannerScreen's isActive flag
  // stays in sync — its camera should only run while its tab is shown, even
  // though IndexedStack keeps every tab mounted underneath.
  List<Widget> get _pages => [
    HomeScreen(onNavigate: _switchTab),
    const LibraryScreen(),
    ScannerScreen(isActive: _selectedIndex == 2),
    const PlannerScreen(),
    const FlashcardsScreen(),
    const StatusScreen(), // gallery — untouched
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          IndexedStack(index: _selectedIndex, children: _pages),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: GlassContainer(
          borderRadius: AppRadius.lg,
          color: AppColors.surfaceElevated,
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            indicatorColor: AppColors.accent.withOpacity(0.25),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_books_outlined),
                selectedIcon: Icon(Icons.library_books),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.document_scanner_outlined),
                selectedIcon: Icon(Icons.document_scanner),
                label: 'Scanner',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note),
                label: 'Planner',
              ),
              NavigationDestination(
                icon: Icon(Icons.style_outlined),
                selectedIcon: Icon(Icons.style),
                label: 'Cards',
              ),
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: 'Gallery',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
