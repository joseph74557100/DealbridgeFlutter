import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../deals/deals_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}
class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _pages = const [
    _PlaceholderPage(title: 'Home', icon: Icons.home_outlined, description: 'Your business opportunities at a glance.'),
    _PlaceholderPage(title: 'Discover', icon: Icons.explore_outlined, description: 'Business discovery is queued for migration.'),
    DealsScreen(),
    _PlaceholderPage(title: 'Messages', icon: Icons.chat_bubble_outline, description: 'Business and personal messaging is queued for migration.'),
    _PlaceholderPage(title: 'Profile', icon: Icons.person_outline, description: 'Profile, agreements and settings are queued for migration.'),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(selectedIndex: _index, onDestinationSelected: (v) => setState(() => _index = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
      NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'Deals'),
      NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'Messages'),
      NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
    ]),
  );
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.icon, required this.description});
  final String title, description; final IconData icon;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title), actions: [
    if (title == 'Profile') IconButton(tooltip: 'Sign out', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
  ]), body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), Text(title, style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8), Text(description, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]))));
}
