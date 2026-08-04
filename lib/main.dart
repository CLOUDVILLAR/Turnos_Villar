import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'utils/ip.dart';


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
        return Banner(
          message: 'AMBIENTE DE PRUEBA',
          location: BannerLocation.topEnd,
          color: Colors.redAccent,
          child: child,
        );
      },
    );
  }
}