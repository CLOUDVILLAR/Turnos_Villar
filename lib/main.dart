import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'utils/ip.dart';
import 'widgets/staging_badge.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema de Turnos',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
      },
      builder: (context, child) {
        if (child == null || !isStaging) return child ?? const SizedBox.shrink();
        return Stack(
          children: [
            child,
            const Positioned(
              top: 12,
              left: 12,
              child: SafeArea(child: StagingBadge()),
            ),
          ],
        );
      },
    );
  }
}