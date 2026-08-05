import 'package:flutter/material.dart';

/// Insignia flotante que marca visualmente que la app corre en el
/// ambiente de staging (no producción), con los datos del Odoo de pruebas
/// al que está conectada la API.
class StagingBadge extends StatelessWidget {
  const StagingBadge({super.key});

  static const Color _amber = Color(0xFFFFC400);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _amber, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AMBIENTE DE PRUEBAS — STAGING',
              style: TextStyle(
                color: _amber,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.warning_amber_rounded, color: _amber, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Odoo: ovillar-staging-35513974.dev.odoo.com\n(asistp@opticavillar.com)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
