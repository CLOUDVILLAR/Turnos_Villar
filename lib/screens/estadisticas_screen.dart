import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../utils/ip.dart';
import '../widgets/custom_drawer.dart';

import 'package:excel/excel.dart' as ex;
import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

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

  // ✅ Ahora el filtro es siempre un rango (por defecto: hoy → hoy)
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  bool _loading = false;

  int totalAtendidos = 0;
  double avgTotal = 0;
  double avgEspera = 0;
  double avgAtencion = 0;

  List<Map<String, dynamic>> clientes = [];

  Map<String, int> get conteoPorEdad {
  final counts = {
    '1-4': 0,
    '5-14': 0,
    '15-64': 0,
    '>64': 0,
  };

  for (final c in clientes) {
    final edad = int.tryParse((c['edad'] ?? '').toString());
    if (edad == null) continue;

    if (edad >= 1 && edad <= 4) {
      counts['1-4'] = counts['1-4']! + 1;
    } else if (edad >= 5 && edad <= 14) {
      counts['5-14'] = counts['5-14']! + 1;
    } else if (edad >= 15 && edad <= 64) {
      counts['15-64'] = counts['15-64']! + 1;
    } else if (edad > 64) {
      counts['>64'] = counts['>64']! + 1;
    }
  }

  return counts;
}

Future<void> _exportarExcel() async {
  final data = conteoPorEdad;
  final excel = ex.Excel.createExcel();
  final sheet = excel['Resumen'];

  final encoded = excel.encode();

  final titleStyle = ex.CellStyle(
    bold: true,
    fontSize: 20,
    fontColorHex: ex.ExcelColor.white,
    backgroundColorHex: ex.ExcelColor.orange,
    horizontalAlign: ex.HorizontalAlign.Center,
    verticalAlign: ex.VerticalAlign.Center,
  );

  final headerStyle = ex.CellStyle(
    bold: true,
    fontSize: 12,
    fontColorHex: ex.ExcelColor.white,
    backgroundColorHex: ex.ExcelColor.fromHexString('#F97316'),
    horizontalAlign: ex.HorizontalAlign.Center,
    verticalAlign: ex.VerticalAlign.Center,
  );

  final valueStyle = ex.CellStyle(
    bold: true,
    fontSize: 14,
    fontColorHex: ex.ExcelColor.fromHexString('#111827'),
    backgroundColorHex: ex.ExcelColor.fromHexString('#FFF7ED'),
    horizontalAlign: ex.HorizontalAlign.Center,
    verticalAlign: ex.VerticalAlign.Center,
  );

  final subtitleStyle = ex.CellStyle(
    bold: true,
    fontSize: 11,
    fontColorHex: ex.ExcelColor.fromHexString('#7C2D12'),
    backgroundColorHex: ex.ExcelColor.fromHexString('#FFEDD5'),
    horizontalAlign: ex.HorizontalAlign.Center,
    verticalAlign: ex.VerticalAlign.Center,
  );

  sheet.merge(
    ex.CellIndex.indexByString('A1'),
    ex.CellIndex.indexByString('E1'),
  );

  final titleCell = sheet.cell(ex.CellIndex.indexByString('A1'));
  titleCell.value = ex.TextCellValue('CLIENTES ATENDIDOS');
  titleCell.cellStyle = titleStyle;

  sheet.merge(
    ex.CellIndex.indexByString('A2'),
    ex.CellIndex.indexByString('E2'),
  );

  final rangeCell = sheet.cell(ex.CellIndex.indexByString('A2'));
  rangeCell.value = ex.TextCellValue(
    'Rango: ${_fmtDateUi(_startDate)} - ${_fmtDateUi(_endDate)}',
  );
  rangeCell.cellStyle = subtitleStyle;

  sheet.appendRow([
    ex.TextCellValue('Total atendido'),
    ex.TextCellValue('1 - 4 años'),
    ex.TextCellValue('5 - 14 años'),
    ex.TextCellValue('15 - 64 años'),
    ex.TextCellValue('Mayor a 64'),
  ]);

  sheet.appendRow([
    ex.IntCellValue(totalAtendidos),
    ex.IntCellValue(data['1-4'] ?? 0),
    ex.IntCellValue(data['5-14'] ?? 0),
    ex.IntCellValue(data['15-64'] ?? 0),
    ex.IntCellValue(data['>64'] ?? 0),
  ]);

  for (final cell in ['A3', 'B3', 'C3', 'D3', 'E3']) {
    sheet.cell(ex.CellIndex.indexByString(cell)).cellStyle = headerStyle;
  }

  for (final cell in ['A4', 'B4', 'C4', 'D4', 'E4']) {
    sheet.cell(ex.CellIndex.indexByString(cell)).cellStyle = valueStyle;
  }

  sheet.setColumnWidth(0, 22);
  sheet.setColumnWidth(1, 18);
  sheet.setColumnWidth(2, 18);
  sheet.setColumnWidth(3, 18);
  sheet.setColumnWidth(4, 18);

  excel.delete('Sheet1');

  final bytesRaw = excel.encode();
  if (bytesRaw == null) {
    _toast('No se pudo generar el Excel');
    return;
  }

  final bytes = Uint8List.fromList(bytesRaw);

  final fileName =
      'estadisticas_${widget.sucursalNombre}_${_fmtDateApi(_startDate)}_${_fmtDateApi(_endDate)}';

  if (kIsWeb) {
    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  } else {
    final location = await getSaveLocation(
      suggestedName: '$fileName.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );

    if (location == null) return;

    final file = XFile.fromData(
      bytes,
      name: '$fileName.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    await file.saveTo(location.path);
  }

  _toast('Excel exportado');
}



  @override
  void initState() {
    super.initState();
    // ✅ Inicializa a “hoy”
    final today = _dateOnly(DateTime.now());
    _startDate = today;
    _endDate = today;
    _fetchRange(_startDate, _endDate);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

  Theme _pickerTheme(Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: brandRed,
          onPrimary: Colors.white,
          onSurface: Colors.black87,
        ),
      ),
      child: child,
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: brandRed,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==========================
  // ✅ Solo botón "Filtro"
  // Inicio → Fin (dos calendarios)
  // ==========================
  Future<void> _pickRangeTwoSteps() async {
    if (_loading) return;

    final today = _dateOnly(DateTime.now());

    // 1) Elegir inicio
    final startPicked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: today.add(const Duration(days: 365)),
      builder: (context, child) => _pickerTheme(child!),
      helpText: "Selecciona día de inicio",
    );

    if (startPicked == null) return;
    final start = _dateOnly(startPicked);

    // 2) Elegir fin (no puede ser antes del inicio)
    final endPicked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(start) ? start : _endDate,
      firstDate: start,
      lastDate: today.add(const Duration(days: 365)),
      builder: (context, child) => _pickerTheme(child!),
      helpText: "Selecciona día de cierre",
    );

    if (endPicked == null) return;
    final end = _dateOnly(endPicked);

    setState(() {
      _startDate = start;
      _endDate = end;
    });

    await _fetchRange(start, end);
  }

  // ==========================
  // ✅ Fetch por día (reusa tu endpoint)
  // ==========================
  Future<Map<String, dynamic>?> _fetchDay(DateTime day) async {
    try {
      final fecha = _fmtDateApi(day);
      final res = await http.get(
        Uri.parse('$baseUrl/estadisticas/${widget.sucursalId}?fecha=$fecha'),
      );
      if (res.statusCode == 200) {
        return (jsonDecode(res.body) as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchRange(DateTime start, DateTime end) async {
    if (_loading) return;

    setState(() => _loading = true);

    try {
      final s = _dateOnly(start);
      final e = _dateOnly(end);

      final days = e.difference(s).inDays + 1;
      if (days <= 0) {
        _toast("Rango inválido");
        return;
      }

      // ✅ límite para no hacer demasiadas llamadas
      if (days > 62) {
        _toast("Rango muy grande (máx 62 días).");
        return;
      }

      final allClientes = <Map<String, dynamic>>[];

      for (int i = 0; i < days; i++) {
        final day = s.add(Duration(days: i));
        final data = await _fetchDay(day);
        if (data == null) continue;

        final list = (data['clientes'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();

        allClientes.addAll(list);
      }

      // ✅ Recalcular KPIs desde los clientes reales
      final count = allClientes.length;

      double sumTotal = 0;
      double sumEspera = 0;
      double sumAtencion = 0;

      for (final c in allClientes) {
        sumTotal += (c['total_seg'] ?? 0).toDouble();
        sumEspera += (c['espera_seg'] ?? 0).toDouble();
        sumAtencion += (c['atencion_seg'] ?? 0).toDouble();
      }

      // ✅ Orden por created_at desc
      allClientes.sort((a, b) {
        final aT = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bT = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bT.compareTo(aT);
      });

      if (!mounted) return;
      setState(() {
        totalAtendidos = count;
        avgTotal = count == 0 ? 0 : (sumTotal / count);
        avgEspera = count == 0 ? 0 : (sumEspera / count);
        avgAtencion = count == 0 ? 0 : (sumAtencion / count);
        clientes = allClientes;
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================
  // UI
  // ==========================


  Widget _edadRangeTable() {
  final data = conteoPorEdad;

  Widget cell(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
          color: Colors.white,
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: brandRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Personas por rango de edad",
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          cell("1 - 4", "${data['1-4']}"),
          const SizedBox(width: 8),
          cell("5 - 14", "${data['5-14']}"),
          const SizedBox(width: 8),
          cell("15 - 64", "${data['15-64']}"),
          const SizedBox(width: 8),
          cell("> 64", "${data['>64']}"),
        ],
      ),
    ],
  );
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
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
          ),
        ],
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

 String get _rangeUiText {
  final a = _fmtDateUi(_startDate);
  final b = _fmtDateUi(_endDate);
  return "Rango: $a → $b";
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: brandRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text("${widget.sucursalNombre} • Estadísticas"),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _fetchRange(_startDate, _endDate),
            icon: const Icon(Icons.refresh),
            tooltip: "Recargar",
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
                  // Texto de rango + botón único Filtro
                  Row(
                    children: [
                      Expanded(
                        child: Text(
  _rangeUiText,
  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
),
                      ),
                      OutlinedButton.icon(
  onPressed: _loading ? null : _pickRangeTwoSteps,
  style: OutlinedButton.styleFrom(
    foregroundColor: brandRed,
    side: const BorderSide(color: brandRed),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  icon: const Icon(Icons.tune),
  label: const Text("Filtro"),
),

const SizedBox(width: 8),

ElevatedButton.icon(
  onPressed: _loading ? null : _exportarExcel,
  style: ElevatedButton.styleFrom(
    backgroundColor: brandRed,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  icon: const Icon(Icons.download),
  label: const Text("Exportar"),
),
                    ],
                  ),

                  const SizedBox(height: 12),

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

                  _edadRangeTable(),

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
                              "No hay clientes atendidos en ese rango.",
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
