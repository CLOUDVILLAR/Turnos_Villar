import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/ip.dart';
import '../widgets/custom_drawer.dart';



Future<List<Map<String, dynamic>>> _buscarClientes(String q) async {
  if (q.trim().length < 2) return [];
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/odoo/clientes/buscar?q=${Uri.encodeQueryComponent(q.trim())}'),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    }
  } catch (_) {}
  return [];
}

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
  final int pos; // 1 = siguiente, 2 = después...
  const _QueueItem(this.turno, this.pos);
}

class _EmpleadoScreenState extends State<EmpleadoScreen> {
  // Brand
  static const Color brandRed = Color(0xFFE5361B);

  WebSocketChannel? channel;

  Map<String, dynamic>? turnoActual;
  List<Map<String, dynamic>> cola = []; // turnos después del actual

  Timer? _pingTimer;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _fetchTurnosEspera();
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
        final turnos = rawList.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

        setState(() {
          turnoActual = turnos.isNotEmpty ? turnos.first : null;
          cola = turnos.length > 1 ? turnos.sublist(1) : <Map<String, dynamic>>[];
        });
      }
    } catch (_) {}
  }

  Future<void> _crearTurno(String nombre, int edad, String? tel) async {
    final cleanName = nombre.trim();
    if (cleanName.isEmpty) {
      _toast("El nombre es obligatorio.");
      return;
    }
    if (RegExp(r'\d').hasMatch(cleanName)) {
      _toast("El nombre no puede contener números.");
      return;
    }
    if (edad <= 0 || edad > 120) {
      _toast("Edad inválida.");
      return;
    }
    if (tel != null && tel.isNotEmpty && !RegExp(r'^\d+$').hasMatch(tel)) {
      _toast("El teléfono solo puede contener números.");
      return;
    }

    await http.post(
      Uri.parse('$baseUrl/crear-turno'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sucursal_id': widget.sucursalId,
        'nombre': cleanName,
        'edad': edad,
        'telefono': tel,
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
  _pingTimer?.cancel();
  _reconnectTimer?.cancel();
  try {
    channel?.sink.close();
  } catch (_) {}
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

  // llenar hacia abajo y al tocar el fondo crear otra columna
  List<_QueueItem?> _columnMajor(List<_QueueItem> items, int rowsPerCol, int cols) {
    final totalCells = rowsPerCol * cols;
    final out = List<_QueueItem?>.filled(totalCells, null);

    for (var j = 0; j < items.length; j++) {
      final r = j % rowsPerCol;
      final c = j ~/ rowsPerCol;
      if (c >= cols) break;
      final i = r * cols + c; // row-major index
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

  // ----------------- Dialog Nuevo Turno (buscador Odoo estable) -----------------

void _showAddTurnoDialog() {
  final nombreCtrl = TextEditingController();
  final edadCtrl = TextEditingController();
  final telCtrl = TextEditingController();

  Map<String, dynamic>? selectedCliente;
  List<Map<String, dynamic>> sugerencias = [];
  bool loadingSearch = false;

  Timer? _localDebounce;
  bool _dialogAlive = true;

  void safeSetLocal(StateSetter setLocal, VoidCallback fn) {
    if (!_dialogAlive) return;
    setLocal(fn);
  }

  // Nombre: letras + espacios + acentos + guión + apóstrofe, sin números
  final nameFormatter = FilteringTextInputFormatter.allow(
    RegExp(r"[a-zA-ZáéíóúÁÉÍÓÚñÑ\s\-\']"),
  );

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      // ✅ DECLARA ESTO JUSTO ANTES DEL return StatefulBuilder(...)
bool editingTel = false;
bool savingTel = false;
String originalTel = '';

return StatefulBuilder(
  builder: (context, setLocal) {
    void onNombreChanged(String value) {
      selectedCliente = null;

      _localDebounce?.cancel();
      _localDebounce = Timer(const Duration(milliseconds: 300), () async {
        final q = value.trim();

        if (q.length < 2) {
          safeSetLocal(setLocal, () {
            sugerencias = [];
            loadingSearch = false;
          });
          return;
        }

        safeSetLocal(setLocal, () => loadingSearch = true);
        final res = await _buscarClientes(q);

        safeSetLocal(setLocal, () {
          sugerencias = res;
          loadingSearch = false;
        });
      });
    }

    void selectCliente(Map<String, dynamic> c) {
      setLocal(() {
        selectedCliente = c;
        nombreCtrl.text = (c['name'] ?? '').toString();

        final tel = ((c['phone'] ?? c['mobile']) ?? '').toString();
        telCtrl.text = tel;

        originalTel = tel;     // ✅
        editingTel = false;    // ✅
        savingTel = false;     // ✅

        sugerencias = [];
        loadingSearch = false;
      });
    }

    void clearSelected() {
      safeSetLocal(setLocal, () {
        selectedCliente = null;
        nombreCtrl.clear();
        edadCtrl.clear();
        telCtrl.clear();
        sugerencias = [];
        loadingSearch = false;

        // ✅ reset
        originalTel = '';
        editingTel = false;
        savingTel = false;
      });
    }

    final screenW = MediaQuery.of(context).size.width;
    final maxW = screenW > 560 ? 560.0 : screenW - 32;
    final telFocus = FocusNode();
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
              // --------- Header ----------
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

              // --------- Form ----------
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedCliente != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: clearSelected,
                          style: TextButton.styleFrom(foregroundColor: brandRed),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text("Quitar selección"),
                        ),
                      ),

                    TextField(
                      controller: nombreCtrl,
                      inputFormatters: [nameFormatter],
                      enabled: selectedCliente == null,
                      onChanged: onNombreChanged,
                      decoration: InputDecoration(
                        labelText: "Nombre y Apellido",
                        suffixIcon: loadingSearch
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : (selectedCliente != null
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

                    // ✅ SUGERENCIAS con alto fijo (sin IntrinsicWidth crash)
                    if (selectedCliente == null && sugerencias.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SizedBox(
                          height: 220,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: sugerencias.length,
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemBuilder: (_, i) {
                              final c = sugerencias[i];
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
                                onTap: () => selectCliente(c),
                              );
                            },
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: edadCtrl,
                      enabled: true, // ✅ siempre habilitada
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
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
                    const SizedBox(height: 12),

                    TextField(
  controller: telCtrl,
  focusNode: telFocus,

  // ✅ siempre habilitado para que el suffixIcon sea clickable
  enabled: !savingTel,

  // ✅ bloquea escritura si es cliente existente y aún no activaste el lápiz
  readOnly: (selectedCliente != null) && !editingTel,

  showCursor: (selectedCliente == null) || editingTel,
  keyboardType: TextInputType.phone,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(15),
  ],
  decoration: InputDecoration(
    labelText: "Teléfono (opcional)",
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: brandRed, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.black12),
    ),
    suffixIcon: (selectedCliente != null)
    ? IconButton(
        tooltip: editingTel ? "Bloquear edición" : "Editar teléfono",
        icon: Icon(editingTel ? Icons.edit_off : Icons.edit, color: brandRed),
        onPressed: () {
          setLocal(() => editingTel = !editingTel);
          if (editingTel) {
            Future.microtask(() => telFocus.requestFocus());
          }
        },
      )
    : null,
  ),
)
,
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // --------- Actions ----------
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        _dialogAlive = false;
                        _localDebounce?.cancel();
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
                      onPressed: () async {
                        final nombre = nombreCtrl.text.trim();
                        final edad = int.tryParse(edadCtrl.text.trim()) ?? 0;
                        final tel = telCtrl.text.trim().isEmpty ? null : telCtrl.text.trim();

                        if (nombre.isEmpty) {
                          _toast("El nombre es obligatorio");
                          return;
                        }

                        if (edad <= 0 || edad > 120) {
                          _toast("Edad inválida.");
                          return;
                        }

                        // ✅ Crear en Odoo solo si NO seleccionó existente
                        if (selectedCliente == null) {
                          await http.post(
                            Uri.parse('$baseUrl/odoo/clientes/seleccionar-o-crear'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({
                              "nombre": nombre,
                              "edad": edad,
                              "telefono": tel,
                            }),
                          );
                        }

                        // ✅ Si seleccionó y cambió el tel, actualiza en Odoo
                        if (selectedCliente != null) {
  final newTel = telCtrl.text.trim();
  if (newTel != originalTel) {
    final partnerId = selectedCliente!['id'];
    await http.post(
      Uri.parse('$baseUrl/odoo/clientes/$partnerId/telefono'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"telefono": newTel.isEmpty ? null : newTel}),
    );
  }
}

                        await _crearTurno(nombre, edad, tel);

                        _dialogAlive = false;
                        _localDebounce?.cancel();
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text("Agregar", style: TextStyle(fontWeight: FontWeight.w900)),
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
);















    },
  ).then((_) {
    // Si cierran tocando afuera o back: igual cancelamos debounce
    _dialogAlive = false;
    _localDebounce?.cancel();
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
