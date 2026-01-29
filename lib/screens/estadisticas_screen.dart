import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../utils/ip.dart';
import '../widgets/custom_drawer.dart';

class EstadisticasScreen extends StatefulWidget {
  final int sucursalId;
  final String sucursalNombre;

  const EstadisticasScreen({
    super.key,
    required this.sucursalId,
    required this.sucursalNombre,
  });

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  static const Color brandRed = Color(0xFFE5361B);

  DateTime _selectedDate = DateTime.now();
  bool _loading = false;

  int totalAtendidos = 0;
  double avgTotal = 0;
  double avgEspera = 0;
  double avgAtencion = 0;

  List<Map<String, dynamic>> clientes = [];


  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String _fmtDateApi(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return "${d.year}-$mm-$dd";
  }

  String _fmtDateUi(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return "$dd/$mm/${d.year}";
  }

  String _fmtDuration(double seconds) {
    final s = seconds.isNaN ? 0 : seconds.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final r = s % 60;

    String two(int x) => x.toString().padLeft(2, '0');
    if (h > 0) return "${two(h)}:${two(m)}:${two(r)}";
    return "${two(m)}:${two(r)}";
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: brandRed,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _fetch();
  }

  Future<void> _fetch() async {
  setState(() => _loading = true);
  try {
    final fecha = _fmtDateApi(_selectedDate);
    final res = await http.get(Uri.parse('$baseUrl/estadisticas/${widget.sucursalId}?fecha=$fecha'));

    if (!mounted) return;

    if (res.statusCode == 200) {
      final data = (jsonDecode(res.body) as Map).cast<String, dynamic>();

      final list = (data['clientes'] as List<dynamic>)
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

      // ✅ AQUÍ VA EL SORT (ANTES DEL setState)
      list.sort((a, b) {
        final aT = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bT = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bT.compareTo(aT); // DESC: últimos primero
      });

      setState(() {
        totalAtendidos = (data['total_atendidos'] ?? 0) as int;
        avgTotal = (data['promedio_total_seg'] ?? 0).toDouble();
        avgEspera = (data['promedio_espera_seg'] ?? 0).toDouble();
        avgAtencion = (data['promedio_atencion_seg'] ?? 0).toDouble();
        clientes = list; // <- ya ordenada
      });
    }
  } catch (_) {
    // ignore
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}


  Widget _kpi(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brandRed,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _clientTile(int index, Map<String, dynamic> c) {
  final nombre = (c['nombre'] ?? '').toString();
  final edad = (c['edad'] ?? '').toString();
  final tel = (c['telefono'] ?? 'N/A').toString();

  final espera = (c['espera_seg'] ?? 0).toDouble();
  final atencion = (c['atencion_seg'] ?? 0).toDouble();
  final total = (c['total_seg'] ?? 0).toDouble();

  final pos = index + 1;

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black12),
      color: Colors.white,
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: brandRed.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: brandRed.withOpacity(0.35)),
        ),
        child: Center(
          child: Text(
            "$pos",
            style: const TextStyle(fontWeight: FontWeight.w900, color: brandRed),
          ),
        ),
      ),
      title: Text(
        nombre.isEmpty ? "Sin nombre" : nombre,
        style: const TextStyle(fontWeight: FontWeight.w900),
        overflow: TextOverflow.ellipsis,
      ),

      // ✅ aquí mostramos edad + teléfono
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _pill("Edad", "$edad"),
                _pill("Tel", tel),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _pill("Espera", _fmtDuration(espera)),
                _pill("Atención", _fmtDuration(atencion)),
                _pill("Total", _fmtDuration(total), strong: true),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}







  Widget _pill(String label, String value, {bool strong = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
        color: strong ? brandRed.withOpacity(0.08) : Colors.transparent,
      ),
      child: Text(
        "$label: $value",
        style: TextStyle(
          fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          color: Colors.black87,
          fontSize: 12.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fechaUi = _fmtDateUi(_selectedDate);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: brandRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text("${widget.sucursalNombre} • Estadísticas"),
        actions: [
  IconButton(
    onPressed: _loading ? null : _fetch,
    icon: const Icon(Icons.refresh),
    tooltip: "Recargar",
  ),
  IconButton(
    onPressed: _pickDate,
    icon: const Icon(Icons.calendar_month),
    tooltip: "Seleccionar fecha",
  ),
],
      ),
      drawer: CustomDrawer(
        sucursalId: widget.sucursalId,
        sucursalNombre: widget.sucursalNombre,
        currentRoute: 'estadisticas',
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fecha seleccionada + botón
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Fecha seleccionada: $fechaUi",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: brandRed,
                          side: const BorderSide(color: brandRed),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.tune),
                        label: const Text("Cambiar"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // KPIs (centrados por ancho max y en Wrap para responsive)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(width: 220, child: _kpi("Total atendidos", "$totalAtendidos")),
                      SizedBox(width: 220, child: _kpi("Promedio total", _fmtDuration(avgTotal))),
                      SizedBox(width: 220, child: _kpi("Promedio espera", _fmtDuration(avgEspera))),
                      SizedBox(width: 220, child: _kpi("Promedio atención", _fmtDuration(avgAtencion))),
                    ],
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Clientes atendidos",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87),
                        ),
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: clientes.isEmpty && !_loading
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: const Text(
                              "No hay clientes atendidos en esa fecha.",
                              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: clientes.length,
                            itemBuilder: (context, i) => _clientTile(i, clientes[i]),
                          ),
                          
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
