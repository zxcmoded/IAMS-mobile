import 'package:flutter/material.dart';

/// Placeholder for the Audit tab. Full audit functionality is out of scope
/// for the bottom-navigation-bar task — this just gives the nav bar
/// somewhere real to route to.
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}
