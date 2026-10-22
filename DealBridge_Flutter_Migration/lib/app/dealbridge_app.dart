import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/auth_gate.dart';

class DealBridgeApp extends StatelessWidget {
  const DealBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DealBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}
