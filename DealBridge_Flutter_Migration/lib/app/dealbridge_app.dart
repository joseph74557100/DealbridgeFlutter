import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';

class DealBridgeApp extends StatelessWidget {
  const DealBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF101827);
    const blue = Color(0xFF4F8CFF);
    return MaterialApp(
      title: 'DealBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.dark),
        cardTheme: CardThemeData(color: const Color(0xFF1A2435), elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF1A2435),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
