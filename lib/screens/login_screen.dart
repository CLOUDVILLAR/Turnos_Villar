import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/ip.dart';
import 'empleado_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color brandRed = Color(0xFFE5361B);

  final _userController = TextEditingController();
  final _passController = TextEditingController();

  bool _isLoading = false;
  bool _checkingSession = true;
  bool _showPass = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt('sucursalId');
      final nombre = prefs.getString('sucursalNombre');

      if (!mounted) return;

      if (id != null && nombre != null && nombre.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmpleadoScreen(
              sucursalId: id,
              sucursalNombre: nombre,
            ),
          ),
        );
        return;
      }
    } catch (_) {
      // si falla, mostramos login normal
    } finally {
      if (mounted) setState(() => _checkingSession = false);
    }
  }

  Future<void> _saveSession({required int sucursalId, required String sucursalNombre}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sucursalId', sucursalId);
    await prefs.setString('sucursalNombre', sucursalNombre);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: brandRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _login() async {
    final user = _userController.text.trim();
    final pass = _passController.text;

    if (user.isEmpty || pass.isEmpty) {
      _toast("Completa usuario y contraseña");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass}),
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final int id = data['id'];
        final String nombre = data['nombre'];

        await _saveSession(sucursalId: id, sucursalNombre: nombre);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmpleadoScreen(
              sucursalId: id,
              sucursalNombre: nombre,
            ),
          ),
        );
      } else {
        _toast("Credenciales incorrectas");
      }
    } catch (_) {
      if (!mounted) return;
      _toast("Error de conexión");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: brandRed) : null,
      labelStyle: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: brandRed, width: 2),
      ),
    );
  }

  Widget _logoOnWhite({double height = 46}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white, // <-- clave para que el logo se vea perfecto
        borderRadius: BorderRadius.circular(18),
      ),
      child: Image.asset(
        'assets/optica_villar_logo.png',
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return const Text(
            "Óptica Villar",
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header (rojo, logo sobre blanco)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: brandRed,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _logoOnWhite(height: 44),
                        const SizedBox(height: 12),
                        const Text(
                          "Sistema de turnos",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Examen de la vista y atención al cliente",
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  TextField(
                    controller: _userController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration("Usuario", icon: Icons.person_outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passController,
                    obscureText: !_showPass,
                    onSubmitted: (_) => _login(),
                    decoration: _fieldDecoration("Contraseña", icon: Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _showPass = !_showPass),
                        icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility, color: Colors.black45),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: 52,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brandRed,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _login,
                            child: const Text(
                              "Iniciar sesión",
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                          ),
                  ),

                  const SizedBox(height: 10),
                  const Text(
                    "La sesión queda guardada en este dispositivo.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
