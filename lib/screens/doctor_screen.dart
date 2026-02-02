import 'dart:async';
import 'dart:convert';

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
  static const Color brandGreen = Color(0xFF2E7D32);

  WebSocketChannel? channel;

  Map<String, dynamic>? turnoActual;
  List<Map<String, dynamic>> cola = [];

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
    _fetchTurnosEspera();
  }

  void _connectWebSocket() {
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
            _fetchTurnosEspera();
          } else {
            _fetchTurnoActual();
            _fetchTurnosEspera();
          }
        } catch (_) {
          _fetchTurnoActual();
          _fetchTurnosEspera();
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

  Future<void> _fetchTurnosEspera() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/turnos-espera/${widget.sucursalId}'));
      if (!mounted) return;

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        final rawList = list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

        final currentId = turnoActual?['id'];

        setState(() {
          if (currentId != null) {
            cola = rawList.where((t) => t['id'] != currentId).toList();
          } else {
            cola = rawList;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchTurnoActual() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/turno-actual/${widget.sucursalId}'));
      if (!mounted) return;

      if (res.statusCode == 200 && res.body != "null") {
        setState(() => turnoActual = (jsonDecode(res.body) as Map).cast<String, dynamic>());
        _iniciarTurnoSiHaceFalta();
        _fetchTurnosEspera();
      } else {
        setState(() => turnoActual = null);
        _fetchTurnosEspera();
      }
    } catch (_) {}
  }

  Future<void> _iniciarTurnoSiHaceFalta() async {
    if (_starting) return;
    if (turnoActual == null) return;

    final id = turnoActual!['id'];
    final estado = (turnoActual!['estado'] ?? 'espera').toString();
    final inicio = turnoActual!['inicio_atencion'];

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
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ✅ Diálogo para copiar manualmente (sin Clipboard API)
  void _showManualCopyDialog({
  required String nombre,
  required String telefono,
}) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Copiar datos", style: TextStyle(fontWeight: FontWeight.w900)),
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
              nombre.isEmpty ? "Sin nombre" : nombre,
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
              telefono.isEmpty ? "N/A" : telefono,
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

  // --- MODAL DEL CLIENTE EN COLA ---
  void _showTurnoDetails(Map<String, dynamic> turno) {
  final nombre = (turno['nombre'] ?? 'Sin nombre').toString();
  final edad = (turno['edad'] ?? 'N/A').toString();
  final tel = (turno['telefono'] ?? 'N/A').toString();

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              CircleAvatar(
                backgroundColor: brandRed.withOpacity(0.1),
                radius: 24,
                child: const Icon(Icons.person, color: brandRed),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "DETALLE DEL PACIENTE",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    // ✅ Nombre seleccionable
                    SelectableText(
                      nombre,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              // ✅ Botón: abre diálogo para copiar manualmente nombre + teléfono
              IconButton(
                icon: const Icon(Icons.copy_all_rounded, color: brandRed),
                tooltip: "Copiar Nombre y Teléfono (Manual)",
                onPressed: () {
                  _showManualCopyDialog(nombre: nombre, telefono: tel);
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Edad",
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54)),
                    Text("$edad años", style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Teléfono",
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54)),
                    // ✅ Tel también seleccionable aquí
                    SelectableText(
                      tel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: brandRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text("Cerrar", style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          )
        ],
      ),
    ),
  );
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
                Row(
                  children: [
                    Expanded(
                      // ✅ Nombre seleccionable también aquí
                      child: SelectableText(
                        nombre.isEmpty ? "Sin nombre" : nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    // ✅ Botón: abre diálogo para copiar manualmente
                    IconButton(
                      icon: const Icon(Icons.copy_all_rounded, color: Colors.white),
                      iconSize: 32,
                      tooltip: "Copiar Nombre (Manual)",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _showManualCopyDialog(nombre: nombre, telefono: tel);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
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

  Widget _listaDeEspera() {
    if (cola.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0),
          child: Text(
            "SIGUIENTES EN FILA",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black45,
              letterSpacing: 1,
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cola.length,
            itemBuilder: (context, index) {
              final item = cola[index];
              final nombre = (item['nombre'] ?? '').toString();

              final isNext = index == 0;

              return GestureDetector(
                onTap: () => _showTurnoDetails(item),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isNext ? brandGreen : Colors.white,
                    border: Border.all(
                      color: isNext ? brandGreen : Colors.black12,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      Container(
                        padding: isNext
                            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                            : const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isNext ? Colors.white.withOpacity(0.2) : brandRed.withOpacity(0.1),
                          shape: isNext ? BoxShape.rectangle : BoxShape.circle,
                          borderRadius: isNext ? BorderRadius.circular(6) : null,
                        ),
                        child: Text(
                          isNext ? "SIGUE" : "${index + 1}",
                          style: TextStyle(
                            color: isNext ? Colors.white : brandRed,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isNext ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
            crossAxisAlignment: CrossAxisAlignment.start,
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

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _listaDeEspera(),
                      if (turnoActual == null && cola.isEmpty) ...[
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
            ],
          ),
        ),
      ),
    );
  }
}
