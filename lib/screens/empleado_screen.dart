import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/ip.dart';
import '../widgets/custom_drawer.dart';


import '../utils/turno_sound.dart';


/// =======================
///  Dialogs (GLOBAL)
///  (Reciben BuildContext para no depender de variables del State)
/// =======================

/// =======================
///  Dialogs (GLOBAL)
///  (Reciben BuildContext para no depender de variables del State)
/// =======================

void _showManualCopyDialog(
  BuildContext context, {
  required String nombre,
  required String telefono,
}) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        "Copiar datos",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Selecciona el texto y cópialo con Ctrl+C (o clic derecho → Copiar).",
            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text("Nombre", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              nombre,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          const Text("Teléfono", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              telefono,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cerrar"),
        ),
      ],
    ),
  );
}

Future<bool> _showTelefonoYaAsignadoDialog(
  BuildContext context, {
  required String telefono,
  required String nombreExistente,
  required Color brandRed,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        "Teléfono ya registrado",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Este número de teléfono ya está asignado al cliente:",
            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              nombreExistente,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              telefono,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () {
              _showManualCopyDialog(
                context,
                nombre: nombreExistente,
                telefono: telefono,
              );
            },
            icon: Icon(Icons.copy_all_rounded, color: brandRed),
            label: Text(
              "Copiar manualmente",
              style: TextStyle(fontWeight: FontWeight.w900, color: brandRed),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: Colors.black54),
          child: const Text("Cancelar"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: brandRed,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text(
            "Usar cliente existente",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );

  return result ?? false;
}

Future<String?> _showPosibleDuplicadoPorNombreDialog(
  BuildContext context, {
  required String nombreExistente,
  required String telefonoExistente,
  required Color brandRed,
}) async {
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        "Posible cliente duplicado",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Ya existe un cliente con este nombre. Verifica si es la misma persona antes de crear otro registro.",
            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text("Nombre", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              nombreExistente,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          const Text("Teléfono actual en Odoo", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              telefonoExistente.trim().isEmpty ? "Sin teléfono" : telefonoExistente,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          style: TextButton.styleFrom(foregroundColor: Colors.black54),
          child: const Text("Cancelar"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'create_new'),
          style: TextButton.styleFrom(foregroundColor: brandRed),
          child: const Text(
            "No, crear nuevo",
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, 'same'),
          style: ElevatedButton.styleFrom(
            backgroundColor: brandRed,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text(
            "Sí, es el mismo",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );

  return result;
}

Future<String?> _showActualizarTelefonoExistenteDialog(
  BuildContext context, {
  required String nombreExistente,
  required String telefonoActual,
  required String telefonoNuevo,
  required Color brandRed,
}) async {
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        "Actualizar teléfono",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "El cliente $nombreExistente ya existe. ¿Deseas actualizar su teléfono en Odoo?",
            style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text("Teléfono actual", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              telefonoActual.trim().isEmpty ? "Sin teléfono" : telefonoActual,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          const Text("Nuevo teléfono", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              telefonoNuevo,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          style: TextButton.styleFrom(foregroundColor: Colors.black54),
          child: const Text("Cancelar"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'keep'),
          style: TextButton.styleFrom(foregroundColor: brandRed),
          child: const Text(
            "No actualizar",
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, 'update'),
          style: ElevatedButton.styleFrom(
            backgroundColor: brandRed,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text(
            "Sí, actualizar",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );

  return result;
}






/// =======================
///  Helpers (GLOBAL)
/// =======================

Future<List<Map<String, dynamic>>> _buscarClientesPorTelefono(String telefono) async {
  final t = telefono.trim();
  if (t.isEmpty) return [];
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/odoo/clientes/buscar-por-telefono?telefono=${Uri.encodeQueryComponent(t)}'),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    }
  } catch (_) {}
  return [];
}

String _soloDigitos(String input) => input.replaceAll(RegExp(r'\D+'), '');

/// Un teléfono se considera "completo" (listo para buscar/enviar) con un
/// mínimo genérico de dígitos, sin asumir el patrón de ningún país en particular.
bool telefonoEstaCompleto(String input) {
  final d = _soloDigitos(input);
  return d.length >= 8;
}

/// No reagrupa los dígitos por su cuenta (eso rompía números al mezclar el
/// código de país con el resto). Solo garantiza el "+" inicial y deja que
/// el empleado escriba libremente espacios y guiones donde quiera.
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(RegExp(r'[^\d\+\-\s]'), '');

    final tieneDigitos = RegExp(r'\d').hasMatch(texto);
    final resto = texto.replaceAll('+', '');
    texto = tieneDigitos ? '+$resto' : resto;

    if (texto.length > 20) texto = texto.substring(0, 20);

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

String? normalizePhone(String? input) {
  if (input == null) return null;
  final t = input.trim();
  if (t.isEmpty) return null;

  final hasPlus = t.startsWith('+');
  final digits = t.replaceAll(RegExp(r'\D+'), '');

  if (digits.isEmpty) return null;

  return hasPlus ? '+$digits' : digits;
}


String normalizeFullName(String input) {
  return input.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool hasNombreYApellido(String input) {
  final n = normalizeFullName(input);
  if (n.isEmpty) return false;

  final parts = n.split(' ').where((p) => p.trim().isNotEmpty).toList();
  if (parts.length < 2) return false;

  // exige al menos 2 “palabras” con 2+ letras (evita "Juan P")
  final strongParts = parts.where((p) => p.length >= 2).length;
  return strongParts >= 2;
}

/// =======================
///  Screen
/// =======================

class EmpleadoScreen extends StatefulWidget {
  final int sucursalId;
  final String sucursalNombre;

  const EmpleadoScreen({
    super.key,
    required this.sucursalId,
    required this.sucursalNombre,
  });

  @override
  State<EmpleadoScreen> createState() => _EmpleadoScreenState();
}

class _QueueItem {
  final Map<String, dynamic> turno;
  final int pos;
  const _QueueItem(this.turno, this.pos);
}

class _EmpleadoScreenState extends State<EmpleadoScreen> {
  static const Color brandRed = Color(0xFFE5361B);

  late final TurnoSound _turnoSound; // ✅ solo una vez

  WebSocketChannel? channel;

  Map<String, dynamic>? turnoActual;
  List<Map<String, dynamic>> cola = [];

  Timer? _pingTimer;
  Timer? _reconnectTimer;



 @override
void initState() {
  super.initState();

  _turnoSound = makeTurnoSound();
  _turnoSound.init();

  _connectWebSocket();
  _fetchTurnosEspera();


}





String? _turnoActualKey;
bool _didInitialFetch = false;

String? _keyFromTurno(Map<String, dynamic>? t) {
  if (t == null) return null;

  // usa el id si existe
  final id = t['id'] ?? t['turno_id'] ?? t['numero'];
  if (id != null) return id.toString();

  // fallback si no hay id
  final nombre = (t['nombre'] ?? '').toString();
  final tel = (t['telefono'] ?? '').toString();
  final edad = (t['edad'] ?? '').toString();
  return '$nombre|$tel|$edad';
}












  // ----------------- Realtime -----------------

  void _connectWebSocket() {
    try {
      channel?.sink.close();
    } catch (_) {}

    channel = WebSocketChannel.connect(Uri.parse(wsUrl(widget.sucursalId)));

    channel!.stream.listen(
      (_) => _fetchTurnosEspera(),
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
    );

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      try {
        channel?.sink.add('ping');
      } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();

    try {
      channel?.sink.close();
    } catch (_) {}

    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _connectWebSocket();
    });
  }

  // ----------------- Data -----------------

Future<void> _fetchTurnosEspera() async {
  try {
    final res = await http.get(Uri.parse('$baseUrl/turnos-espera/${widget.sucursalId}'));
    if (!mounted) return;

    if (res.statusCode == 200) {
      final rawList = jsonDecode(res.body) as List<dynamic>;
      final turnos = rawList
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

      final newActual = turnos.isNotEmpty ? turnos.first : null;
      final newKey = _keyFromTurno(newActual);

      // Compara contra el anterior (pero no suenes en el primer fetch)
      final shouldPlay =
          _didInitialFetch && newKey != null && newKey != _turnoActualKey;

      setState(() {
        turnoActual = newActual;
        cola = turnos.length > 1 ? turnos.sublist(1) : <Map<String, dynamic>>[];
      });

      _didInitialFetch = true;
      _turnoActualKey = newKey;

      // 🔔 EXACTAMENTE AQUÍ
      if (shouldPlay) {
  _turnoSound.play();
}
    }
  } catch (_) {}
}



Future<void> _crearTurno(String nombre, int edad, String? tel, {bool requireApellido = true}) async {
  final cleanName = nombre.trim();

  if (cleanName.isEmpty) {
    _toast("El nombre es obligatorio.");
    return;
  }
  if (requireApellido && !hasNombreYApellido(cleanName)) {
    _toast("Debes ingresar nombre y apellido. (OBLIGATORIO PONER EL APELLIDO)");
    return;
  }
  if (edad <= 0 || edad > 120) {
    _toast("Edad inválida.");
    return;
  }

  final telNormalized = normalizePhone(tel);
  if (telNormalized == null) {
    _toast("El teléfono es obligatorio.");
    return;
  }

  await http.post(
    Uri.parse('$baseUrl/crear-turno'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'sucursal_id': widget.sucursalId,
      'nombre': cleanName,
      'edad': edad,
      'telefono': telNormalized,
    }),
  );

  await _fetchTurnosEspera();
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

 @override
void dispose() {
  _turnoSound.dispose();
  _pingTimer?.cancel();
  _reconnectTimer?.cancel();
  try { channel?.sink.close(); } catch (_) {}
  super.dispose();
}


  // ----------------- UI helpers -----------------

  void _showTurnoDetails(Map<String, dynamic> turno, {required bool isNext, int? pos}) {
    final nombre = (turno['nombre'] ?? '').toString();
    final edad = (turno['edad'] ?? '').toString();
    final tel = (turno['telefono'] ?? 'N/A').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: brandRed,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isNext ? "SIGUIENTE" : "DETALLE",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              nombre.isEmpty ? "Sin nombre" : nombre,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (pos != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            "#$pos",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _detailRow(Icons.cake_outlined, "Edad", "$edad años"),
                const SizedBox(height: 8),
                _detailRow(Icons.phone_outlined, "Teléfono", tel),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: brandRed),
                    child: const Text("Cerrar"),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, color: brandRed),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentCard() {
    if (turnoActual == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: const [
            Icon(Icons.event_busy, color: Colors.black38),
            SizedBox(width: 10),
            Text(
              "No hay cliente actual",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    final nombre = (turnoActual!['nombre'] ?? '').toString();
    final edad = (turnoActual!['edad'] ?? '').toString();
    final tel = (turnoActual!['telefono'] ?? 'N/A').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showTurnoDetails(turnoActual!, isNext: false, pos: null),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: brandRed,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "CLIENTE ACTUAL",
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nombre.isEmpty ? "Sin nombre" : nombre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Edad: $edad  •  Tel: $tel",
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                "EN CURSO",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _queueCell(_QueueItem item) {
    final isNext = item.pos == 1;
    final nombre = (item.turno['nombre'] ?? '').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showTurnoDetails(item.turno, isNext: isNext, pos: item.pos),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isNext ? brandRed : Colors.black12,
            width: isNext ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isNext ? brandRed : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isNext ? brandRed : Colors.black12),
              ),
              child: Center(
                child: Text(
                  "${item.pos}",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isNext ? Colors.white : brandRed,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                nombre.isEmpty ? "Sin nombre" : nombre,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: isNext ? FontWeight.w900 : FontWeight.w700,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isNext)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: brandRed,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  "SIGUE",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_QueueItem?> _columnMajor(List<_QueueItem> items, int rowsPerCol, int cols) {
    final totalCells = rowsPerCol * cols;
    final out = List<_QueueItem?>.filled(totalCells, null);

    for (var j = 0; j < items.length; j++) {
      final r = j % rowsPerCol;
      final c = j ~/ rowsPerCol;
      if (c >= cols) break;
      final i = r * cols + c;
      out[i] = items[j];
    }
    return out;
  }

  Widget _queueTable() {
    if (cola.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: const Text(
          "No hay turnos en cola",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black54),
        ),
      );
    }

    final items = List<_QueueItem>.generate(
      cola.length,
      (i) => _QueueItem(cola[i], i + 1),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableH = constraints.maxHeight;
        final rowHeight = 62.0;
        final rowsPerCol = max(1, (availableH / rowHeight).floor());
        final colsNeeded = (items.length / rowsPerCol).ceil();

        const colWidth = 320.0;
        final gridWidth = colsNeeded * colWidth;

        final arranged = _columnMajor(items, rowsPerCol, colsNeeded);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 6),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: colsNeeded,
                mainAxisExtent: rowHeight,
              ),
              itemCount: arranged.length,
              itemBuilder: (context, index) {
                final item = arranged[index];
                if (item == null) return const SizedBox.shrink();
                return _queueCell(item);
              },
            ),
          ),
        );
      },
    );
  }

  // ----------------- Dialog Nuevo Turno -----------------

  void _showAddTurnoDialog() {
    final dialogMessengerKey = GlobalKey<ScaffoldMessengerState>();

    void dialogToast(String msg) {
      dialogMessengerKey.currentState?.clearSnackBars();
      dialogMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: brandRed,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }

    final telCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    final edadCtrl = TextEditingController();

    Map<String, dynamic>? selectedCliente;
    List<Map<String, dynamic>> multiMatches = [];
    bool loadingSearch = false;
    bool hasSearched = false;
    bool isSubmitting = false;

    Timer? localDebounce;
    bool dialogAlive = true;

    void safeSetLocal(StateSetter setLocal, VoidCallback fn) {
      if (!dialogAlive) return;
      setLocal(fn);
    }

    final nameFormatter = FilteringTextInputFormatter.allow(
      RegExp(r"[a-zA-Z0-9áéíóúÁÉÍÓÚñÑ\s\-\']"),
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return ScaffoldMessenger(
          key: dialogMessengerKey,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: StatefulBuilder(
                builder: (context, setLocal) {
                  void onTelChanged(String value) {
                    localDebounce?.cancel();
                    final digits = _soloDigitos(value);

                    setLocal(() {
                      selectedCliente = null;
                      multiMatches = [];
                      hasSearched = false;
                      nombreCtrl.clear();
                    });

                    if (digits.length < 7) {
                      safeSetLocal(setLocal, () => loadingSearch = false);
                      return;
                    }

                    // Se marca "buscando" de inmediato (antes del debounce) para
                    // que nunca se llegue a mostrar "no existe" antes de buscar de verdad.
                    safeSetLocal(setLocal, () => loadingSearch = true);

                    localDebounce = Timer(const Duration(milliseconds: 350), () async {
                      final res = await _buscarClientesPorTelefono(value);
                      safeSetLocal(setLocal, () {
                        loadingSearch = false;
                        hasSearched = true;
                        if (res.length == 1) {
                          selectedCliente = res.first;
                          nombreCtrl.text = (res.first['name'] ?? '').toString();
                          multiMatches = [];
                        } else if (res.length > 1) {
                          multiMatches = res;
                          selectedCliente = null;
                        } else {
                          selectedCliente = null;
                          multiMatches = [];
                        }
                      });
                    });
                  }

                  void selectFromMulti(Map<String, dynamic> c) {
                    setLocal(() {
                      selectedCliente = c;
                      nombreCtrl.text = (c['name'] ?? '').toString();
                      multiMatches = [];
                    });
                  }

                  final telefonoCompleto = telefonoEstaCompleto(telCtrl.text);
                  final mostrarComoExistente = selectedCliente != null;
                  final mostrarComoNuevo = hasSearched &&
                      telefonoCompleto &&
                      selectedCliente == null &&
                      multiMatches.isEmpty;
                  final mostrarEdad = mostrarComoExistente || mostrarComoNuevo;

                  final nombreValido = mostrarComoExistente ||
                      (mostrarComoNuevo && hasNombreYApellido(nombreCtrl.text));
                  final edadValida = (int.tryParse(edadCtrl.text.trim()) ?? 0) > 0;
                  final puedeAgregar =
                      mostrarEdad && nombreValido && edadValida && !isSubmitting;

                  final screenW = MediaQuery.of(context).size.width;
                  final maxW = screenW > 560 ? 560.0 : screenW - 32;

                  return Dialog(
                    backgroundColor: Colors.white,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_add_alt_1, color: brandRed),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    "Nuevo Cliente",
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                                  ),
                                ),
                                if (selectedCliente != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: brandRed.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: brandRed.withOpacity(0.35)),
                                    ),
                                    child: const Text(
                                      "Cliente existente",
                                      style: TextStyle(
                                        color: brandRed,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // -------- TELÉFONO (único campo al abrir: es la clave de búsqueda) --------
                                  TextField(
                                    controller: telCtrl,
                                    autofocus: true,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      _PhoneInputFormatter(),
                                      LengthLimitingTextInputFormatter(20),
                                    ],
                                    onChanged: onTelChanged,
                                    decoration: InputDecoration(
                                      labelText: "Teléfono (OBLIGATORIO)",
                                      hintText: "+1 809-555-1234",
                                      suffixIcon: loadingSearch
                                          ? const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            )
                                          : (mostrarComoExistente
                                              ? const Icon(Icons.check_circle, color: brandRed)
                                              : null),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: brandRed, width: 2),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Colors.black12),
                                      ),
                                    ),
                                  ),

                                  if (loadingSearch)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            "Buscando cliente…",
                                            style: TextStyle(color: Colors.black54, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (!loadingSearch && multiMatches.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.black12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: SizedBox(
                                        height: 180,
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          itemCount: multiMatches.length,
                                          shrinkWrap: true,
                                          physics: const ClampingScrollPhysics(),
                                          itemBuilder: (_, i) {
                                            final c = multiMatches[i];
                                            final name = (c['name'] ?? '').toString();
                                            final sub = ((c['phone'] ?? c['mobile']) ?? '').toString();
                                            return ListTile(
                                              dense: true,
                                              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                              subtitle: Text(
                                                sub.isEmpty ? "Sin teléfono" : sub,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              trailing: const Icon(Icons.chevron_right),
                                              onTap: () => selectFromMulti(c),
                                            );
                                          },
                                        ),
                                      ),
                                    ),

                                  if (mostrarComoExistente) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: brandRed.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: brandRed.withOpacity(0.25)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle, color: brandRed),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              nombreCtrl.text,
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  if (mostrarComoNuevo) ...[
                                    const SizedBox(height: 12),
                                    const Text(
                                      "No existe ningún cliente con este teléfono. Se creará uno nuevo.",
                                      style: TextStyle(color: Colors.black54, fontSize: 12),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: nombreCtrl,
                                      inputFormatters: [nameFormatter],
                                      onChanged: (_) => setLocal(() {}),
                                      decoration: InputDecoration(
                                        labelText: "Nombre y Apellido (Obligatorio poner el apellido)",
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(color: brandRed, width: 2),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(color: Colors.black12),
                                        ),
                                      ),
                                    ),
                                  ],

                                  if (mostrarEdad) ...[
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: edadCtrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(3),
                                      ],
                                      onChanged: (_) => setLocal(() {}),
                                      decoration: InputDecoration(
                                        labelText: "Edad",
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(color: brandRed, width: 2),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(color: Colors.black12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () {
                                      dialogAlive = false;
                                      localDebounce?.cancel();
                                      Navigator.pop(context);
                                    },
                                    style: TextButton.styleFrom(foregroundColor: Colors.black54),
                                    child: const Text("Cancelar", style: TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: brandRed,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    onPressed: (!puedeAgregar)
                                        ? null
                                        : () async {
                                            setLocal(() => isSubmitting = true);

                                            try {
                                              final nombre = nombreCtrl.text.trim();
                                              final edad = int.tryParse(edadCtrl.text.trim()) ?? 0;
                                              final telNorm = normalizePhone(telCtrl.text);

                                              if (telNorm == null) {
                                                dialogToast("El teléfono es obligatorio.");
                                                return;
                                              }

                                              // Ya sabemos exactamente qué cliente es (se eligió de la
                                              // búsqueda por teléfono): no hace falta volver a tocar Odoo.
                                              if (selectedCliente != null) {
                                                await _crearTurno(
                                                  nombre,
                                                  edad,
                                                  telCtrl.text.trim(),
                                                  requireApellido: false,
                                                );

                                                dialogAlive = false;
                                                localDebounce?.cancel();
                                                if (mounted) Navigator.pop(context);
                                                return;
                                              }

                                              // -------- No existe por teléfono: crear (o resolver duplicado por nombre) --------
                                              Future<Map<String, dynamic>> callSelectOrCreate({bool forzarCreacion = false}) async {
                                                final res = await http.post(
                                                  Uri.parse('$baseUrl/odoo/clientes/seleccionar-o-crear'),
                                                  headers: {'Content-Type': 'application/json'},
                                                  body: jsonEncode({
                                                    "nombre": nombre,
                                                    "edad": edad,
                                                    "telefono": telNorm,
                                                    if (forzarCreacion) "forzar_creacion": true,
                                                  }),
                                                );

                                                if (res.statusCode < 200 || res.statusCode >= 300) {
                                                  throw Exception("Error Odoo (${res.statusCode})");
                                                }

                                                return (jsonDecode(res.body) as Map).cast<String, dynamic>();
                                              }

                                              Map<String, dynamic> data;
                                              try {
                                                data = await callSelectOrCreate();
                                              } catch (e) {
                                                dialogToast(e.toString().replaceFirst("Exception: ", ""));
                                                return;
                                              }

                                              final status = (data["status"] ?? "").toString();
                                              final created = data["created"] == true;
                                              final possibleDuplicate = data["possible_duplicate"] == true;

                                              final partnerRaw = data["partner"];
                                              final partner = partnerRaw is Map
                                                  ? partnerRaw.cast<String, dynamic>()
                                                  : <String, dynamic>{};

                                              String nombreFinal = nombre;
                                              String telFinal = telCtrl.text.trim();

                                              // 1) Ya existía por teléfono (respaldo: nuestra búsqueda previa no debería haberlo dejado pasar)
                                              if (status == "existing_phone") {
                                                final existingName = (partner["name"] ?? "Cliente").toString();
                                                final existingPhone =
                                                    ((partner["phone"] ?? partner["mobile"]) ?? telNorm).toString();

                                                final usarExistente = await _showTelefonoYaAsignadoDialog(
                                                  context,
                                                  telefono: existingPhone,
                                                  nombreExistente: existingName,
                                                  brandRed: brandRed,
                                                );

                                                if (!usarExistente) return;

                                                nombreFinal = (partner["name"] ?? nombre).toString();
                                                telFinal = existingPhone;
                                                dialogToast("Usando cliente existente ♻️");
                                              }

                                              // 2) Posible duplicado por nombre
                                              else if (possibleDuplicate || status == "possible_duplicate_by_name") {
                                                final existingName = (partner["name"] ?? nombre).toString();
                                                final existingPhone = ((partner["phone"] ?? partner["mobile"]) ?? '').toString();

                                                final duplicateDecision = await _showPosibleDuplicadoPorNombreDialog(
                                                  context,
                                                  nombreExistente: existingName,
                                                  telefonoExistente: existingPhone,
                                                  brandRed: brandRed,
                                                );

                                                if (duplicateDecision == null || duplicateDecision == 'cancel') return;

                                                // 2A) No es la misma persona -> crear nuevo forzado
                                                if (duplicateDecision == 'create_new') {
                                                  Map<String, dynamic> forcedData;
                                                  try {
                                                    forcedData = await callSelectOrCreate(forzarCreacion: true);
                                                  } catch (e) {
                                                    dialogToast(e.toString().replaceFirst("Exception: ", ""));
                                                    return;
                                                  }

                                                  final forcedPartnerRaw = forcedData["partner"];
                                                  final forcedPartner = forcedPartnerRaw is Map
                                                      ? forcedPartnerRaw.cast<String, dynamic>()
                                                      : <String, dynamic>{};

                                                  nombreFinal = (forcedPartner["name"] ?? nombre).toString();
                                                  telFinal =
                                                      ((forcedPartner["phone"] ?? forcedPartner["mobile"]) ?? telFinal).toString();

                                                  dialogToast("Cliente nuevo creado ✅");
                                                }
                                                // 2B) Sí es la misma persona -> usar el cliente existente
                                                else if (duplicateDecision == 'same') {
                                                  final existingPhoneNorm = normalizePhone(existingPhone);

                                                  nombreFinal = (partner["name"] ?? nombre).toString();

                                                  if (existingPhone.trim().isEmpty) {
                                                    // Cliente existente sin teléfono guardado: usamos el escrito.
                                                    telFinal = telCtrl.text.trim();
                                                    await http.post(
                                                      Uri.parse('$baseUrl/odoo/clientes/${partner["id"]}/telefono'),
                                                      headers: {'Content-Type': 'application/json'},
                                                      body: jsonEncode({"telefono": telNorm}),
                                                    );
                                                    dialogToast("Cliente existente encontrado. Se guardó el nuevo teléfono ✅");
                                                  } else if (existingPhoneNorm != telNorm) {
                                                    final updateDecision = await _showActualizarTelefonoExistenteDialog(
                                                      context,
                                                      nombreExistente: existingName,
                                                      telefonoActual: existingPhone,
                                                      telefonoNuevo: telCtrl.text.trim(),
                                                      brandRed: brandRed,
                                                    );

                                                    if (updateDecision == null || updateDecision == 'cancel') return;

                                                    if (updateDecision == 'update') {
                                                      telFinal = telCtrl.text.trim();
                                                      await http.post(
                                                        Uri.parse('$baseUrl/odoo/clientes/${partner["id"]}/telefono'),
                                                        headers: {'Content-Type': 'application/json'},
                                                        body: jsonEncode({"telefono": telNorm}),
                                                      );
                                                      dialogToast("Se usará el cliente existente y se actualizó su teléfono ✅");
                                                    } else {
                                                      telFinal = existingPhone;
                                                      dialogToast("Usando cliente existente con su teléfono actual ♻️");
                                                    }
                                                  } else {
                                                    telFinal = existingPhone;
                                                    dialogToast("Usando cliente existente ♻️");
                                                  }
                                                }
                                              }

                                              // 3) Cliente nuevo creado normalmente
                                              else if (created) {
                                                nombreFinal = (partner["name"] ?? nombre).toString();
                                                telFinal = ((partner["phone"] ?? partner["mobile"]) ?? telFinal).toString();
                                                dialogToast("Cliente creado ✅");
                                              }

                                              // 4) Respuesta inesperada
                                              else {
                                                dialogToast("Respuesta inesperada de Odoo.");
                                                return;
                                              }

                                              await _crearTurno(
                                                nombreFinal,
                                                edad,
                                                telFinal,
                                                requireApellido: false,
                                              );

                                              dialogAlive = false;
                                              localDebounce?.cancel();
                                              if (mounted) Navigator.pop(context);
                                            } finally {
                                              if (dialogAlive) {
                                                setLocal(() => isSubmitting = false);
                                              }
                                            }
                                          },
                                    child: isSubmitting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            "Agregar",
                                            style: TextStyle(fontWeight: FontWeight.w900),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    ).then((_) {
      dialogAlive = false;
      localDebounce?.cancel();
    });
  }

  // ----------------- Build -----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
  backgroundColor: brandRed,
  foregroundColor: Colors.white,
  elevation: 0,
  title: Text("${widget.sucursalNombre} • Recepción"),
  actions: [
    IconButton(
      tooltip: _turnoSound.enabled ? "Sonido activado" : "Activar sonido",
      icon: Icon(_turnoSound.enabled ? Icons.notifications_active : Icons.notifications_off),
      onPressed: () async {
        await _turnoSound.enable();
        if (mounted) {
          _toast(_turnoSound.enabled
              ? "Sonido activado 🔔"
              : "El navegador bloqueó el audio. Toca de nuevo.");
        }
      },
    ),
  ],
),
      drawer: CustomDrawer(
        sucursalId: widget.sucursalId,
        sucursalNombre: widget.sucursalNombre,
        currentRoute: 'empleado',
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _currentCard(),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "COLA",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text(
                      "En espera: ${cola.length}",
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 10),
              Expanded(child: _queueTable()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: brandRed,
        foregroundColor: Colors.white,
        elevation: 0,
        onPressed: _showAddTurnoDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
