import 'package:flutter/material.dart';

/// Placeholder for the Settings tab. Full settings functionality is out of
/// scope for the bottom-navigation-bar task — this just gives the nav bar
/// somewhere real to route to.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}
