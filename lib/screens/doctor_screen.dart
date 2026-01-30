import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/ip.dart';
import '../widgets/custom_drawer.dart';

class DoctorScreen extends StatefulWidget {
  final int sucursalId;
  final String sucursalNombre;

  const DoctorScreen({
    super.key,
    required this.sucursalId,
    required this.sucursalNombre,
  });

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  static const Color brandRed = Color(0xFFE5361B);

  WebSocketChannel? channel;
  Map<String, dynamic>? turnoActual;

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int? _lastStartedTurnoId;
bool _starting = false;

  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _fetchTurnoActual();
  }

  void _connectWebSocket() {
    // evita duplicados al reconectar
    try {
      channel?.sink.close();
    } catch (_) {}

    channel = WebSocketChannel.connect(Uri.parse(wsUrl(widget.sucursalId)));

    channel!.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw);
          final event = (decoded is String) ? jsonDecode(decoded) : decoded;

          if (!mounted) return;

          if (event is Map && event['type'] == 'turno_actual') {
            setState(() => turnoActual = (event['turno'] as Map?)?.cast<String, dynamic>());
            _iniciarTurnoSiHaceFalta();
          } else {
            _fetchTurnoActual();
          }
        } catch (_) {
          _fetchTurnoActual();
        }
      },
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

  Future<void> _fetchTurnoActual() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/turno-actual/${widget.sucursalId}'));
      if (!mounted) return;

      if (res.statusCode == 200 && res.body != "null") {
        setState(() => turnoActual = (jsonDecode(res.body) as Map).cast<String, dynamic>());
        _iniciarTurnoSiHaceFalta();
      } else {
        setState(() => turnoActual = null);
      }
    } catch (_) {}
  }

  Future<void> _iniciarTurnoSiHaceFalta() async {
  if (_starting) return;
  if (turnoActual == null) return;

  final id = turnoActual!['id'];
  final estado = (turnoActual!['estado'] ?? 'espera').toString();
  final inicio = turnoActual!['inicio_atencion'];

  // Solo si está en espera y aún no tiene inicio_atencion
  if (estado != 'espera') return;
  if (inicio != null) return;
  if (_lastStartedTurnoId == id) return;

  _starting = true;
  _lastStartedTurnoId = id;

  try {
    await http.post(
      Uri.parse('$baseUrl/iniciar-turno'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'turno_id': id}),
    );
  } catch (_) {
    // ignore
  } finally {
    _starting = false;
  }
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

  Future<bool> _confirmFinalizar() async {
    if (turnoActual == null) return false;

    final nombre = (turnoActual!['nombre'] ?? '').toString();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: const [
              Icon(Icons.check_circle_outline, color: brandRed),
              SizedBox(width: 10),
              Text("Finalizar turno", style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          content: Text(
            "¿Confirmas finalizar el turno de:\n\n$nombre?",
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
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
              child: const Text("Sí, finalizar", style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _finalizarTurno() async {
    if (turnoActual == null || _finishing) return;

    final ok = await _confirmFinalizar();
    if (!ok) return;

    setState(() => _finishing = true);

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/finalizar-turno'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'turno_id': turnoActual!['id']}),
      );

      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Refresco inmediato (y además llegará WS)
        await _fetchTurnoActual();
      } else {
        _toast("No se pudo finalizar el turno");
      }
    } catch (_) {
      _toast("Error de conexión");
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      channel?.sink.close();
    } catch (_) {}
    super.dispose();
  }

 Widget _currentCard() {
    if (turnoActual == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: const [
            Icon(Icons.event_available, color: Colors.black38),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "No hay turnos en espera",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    final nombre = (turnoActual!['nombre'] ?? '').toString();
    final edad = (turnoActual!['edad'] ?? '').toString();
    final tel = (turnoActual!['telefono'] ?? 'N/A').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: brandRed,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.visibility_outlined, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "EXAMEN EN CURSO",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                
                // --- AQUÍ ESTÁ EL CAMBIO ---
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nombre.isEmpty ? "Sin nombre" : nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Botón grande para copiar
                    IconButton(
                      icon: const Icon(Icons.copy_all_rounded, color: Colors.white),
                      iconSize: 32, // Tamaño aumentado para que sea "grande" y fácil de tocar
                      tooltip: "Copiar Nombre",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(), // Reduce el padding extra para ajustar mejor
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: nombre));
                        _toast("Nombre copiado al portapapeles");
                      },
                    ),
                    const SizedBox(width: 8), // Un pequeño espacio extra
                  ],
                ),
                // ---------------------------

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              "ACTUAL",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

















  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: brandRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text("${widget.sucursalNombre} • Doctor"),
      ),
      drawer: CustomDrawer(
        sucursalId: widget.sucursalId,
        sucursalNombre: widget.sucursalNombre,
        currentRoute: 'doctor',
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _currentCard(),
              const SizedBox(height: 14),

              if (turnoActual != null)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _finishing ? null : _finalizarTurno,
                    icon: _finishing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _finishing ? "Finalizando..." : "Finalizar turno",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),

              if (turnoActual == null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Text(
                    "Cuando llegue un cliente, aparecerá aquí automáticamente.",
                    style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
