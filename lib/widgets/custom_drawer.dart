import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/empleado_screen.dart';
import '../screens/doctor_screen.dart';
import '../screens/login_screen.dart';
import '../screens/estadisticas_screen.dart';


class CustomDrawer extends StatelessWidget {
  static const Color brandRed = Color(0xFFE5361B);

  final int sucursalId;
  final String sucursalNombre;
  final String currentRoute;

  const CustomDrawer({
    super.key,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.currentRoute,
  });

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sucursalId');
    await prefs.remove('sucursalNombre');

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _logoOnWhite({double height = 34}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white, // <-- clave para ver el logo
        borderRadius: BorderRadius.circular(16),
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

  Widget _item({
    required BuildContext context,
    required bool selected,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? brandRed.withOpacity(0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? brandRed.withOpacity(0.35) : Colors.black12,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: selected ? brandRed : Colors.black54),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        trailing: selected
            ? const Icon(Icons.check_circle, color: brandRed, size: 20)
            : const Icon(Icons.chevron_right, color: Colors.black26),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header rojo con logo sobre blanco
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: brandRed,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _logoOnWhite(height: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Sistema de turnos",
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sucursalNombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 6),
                  _item(
                    context: context,
                    selected: currentRoute == 'empleado',
                    icon: Icons.people_alt_outlined,
                    title: 'Recepción',
                    onTap: () {
                      if (currentRoute == 'empleado') {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmpleadoScreen(
                              sucursalId: sucursalId,
                              sucursalNombre: sucursalNombre,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  _item(
                    context: context,
                    selected: currentRoute == 'doctor',
                    icon: Icons.visibility_outlined, // óptica vibe 👓
                    title: 'Doctor / Examen',
                    onTap: () {
                      if (currentRoute == 'doctor') {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DoctorScreen(
                              sucursalId: sucursalId,
                              sucursalNombre: sucursalNombre,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  _item(
                    context: context,
                    selected: currentRoute == 'estadisticas',
                    icon: Icons.bar_chart_rounded,
                    title: 'Estadísticas',
                    onTap: () {
                        if (currentRoute == 'estadisticas') {
                        Navigator.pop(context);
                        } else {
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                            builder: (_) => EstadisticasScreen(
                                sucursalId: sucursalId,
                                sucursalNombre: sucursalNombre,
                            ),
                            ),
                        );
                        }
                    },
                    ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: brandRed),
                      title: const Text('Cerrar sesión', style: TextStyle(fontWeight: FontWeight.w900)),
                      onTap: () => _logout(context),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                "Óptica Villar",
                style: TextStyle(
                  color: Colors.black.withOpacity(0.35),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
