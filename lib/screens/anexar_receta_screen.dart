import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/ip.dart';
import '../widgets/custom_drawer.dart';

class AnexarRecetaScreen extends StatefulWidget {
  final int sucursalId;
  final String sucursalNombre;

  const AnexarRecetaScreen({
    super.key,
    required this.sucursalId,
    required this.sucursalNombre,
  });

  @override
  State<AnexarRecetaScreen> createState() => _AnexarRecetaScreenState();
}

class _AnexarRecetaScreenState extends State<AnexarRecetaScreen> {
  static const Color brandRed = Color(0xFFE5361B);

  final _buscarController = TextEditingController();
  final _picker = ImagePicker();

  bool _buscando = false;
  bool _subiendo = false;
  String? _error;

  List<Map<String, dynamic>> _resultados = [];
  Map<String, dynamic>? _ordenSeleccionada;

  Uint8List? _fotoBytes;
  String? _fotoNombre;

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _buscarOrdenes() async {
    final q = _buscarController.text.trim();
    if (q.length < 2) {
      setState(() => _error = 'Escribe al menos 2 caracteres del número de orden.');
      return;
    }

    setState(() {
      _buscando = true;
      _error = null;
      _resultados = [];
      _ordenSeleccionada = null;
      _fotoBytes = null;
      _fotoNombre = null;
    });

    try {
      final res = await http.get(
        Uri.parse('$baseUrl/odoo/ordenes/buscar?q=${Uri.encodeQueryComponent(q)}'),
      );

      if (res.statusCode != 200) {
        throw Exception('Error del servidor (${res.statusCode})');
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      setState(() {
        _resultados = data.cast<Map<String, dynamic>>();
        if (_resultados.isEmpty) {
          _error = 'No se encontró ninguna orden con ese número.';
        }
      });
    } catch (e) {
      setState(() => _error = 'No se pudo buscar: $e');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _seleccionarOrden(Map<String, dynamic> orden) {
    setState(() {
      _ordenSeleccionada = orden;
      _fotoBytes = null;
      _fotoNombre = null;
      _error = null;
    });
  }

  Future<void> _tomarFoto() async {
    try {
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (foto == null) return;

      final bytes = await foto.readAsBytes();
      setState(() {
        _fotoBytes = bytes;
        _fotoNombre = foto.name;
      });
    } catch (e) {
      _toast('No se pudo abrir la cámara: $e');
    }
  }

  Future<void> _elegirDeGaleria() async {
    try {
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (foto == null) return;

      final bytes = await foto.readAsBytes();
      setState(() {
        _fotoBytes = bytes;
        _fotoNombre = foto.name;
      });
    } catch (e) {
      _toast('No se pudo abrir la galería: $e');
    }
  }

  Future<void> _subirReceta() async {
    if (_ordenSeleccionada == null || _fotoBytes == null) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });

    try {
      final orderId = _ordenSeleccionada!['id'];
      final uri = Uri.parse('$baseUrl/odoo/ordenes/$orderId/anexar-receta');
      final request = http.MultipartRequest('POST', uri)
        ..fields['sucursal_nombre'] = widget.sucursalNombre
        ..files.add(http.MultipartFile.fromBytes(
          'foto',
          _fotoBytes!,
          filename: _fotoNombre ?? 'receta.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));

      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode != 200) {
        throw Exception('Error del servidor (${res.statusCode}): ${res.body}');
      }

      _toast('Receta anexada correctamente ✅');
      setState(() {
        _ordenSeleccionada = null;
        _fotoBytes = null;
        _fotoNombre = null;
        _resultados = [];
        _buscarController.clear();
      });
    } catch (e) {
      setState(() => _error = 'No se pudo subir la receta: $e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Widget _buscador() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Buscar orden',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _buscarController,
                decoration: const InputDecoration(
                  hintText: 'Número de orden (ej. KBS-52628 o 52628)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _buscarOrdenes(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _buscando ? null : _buscarOrdenes,
              style: ElevatedButton.styleFrom(
                backgroundColor: brandRed,
                foregroundColor: Colors.white,
              ),
              child: _buscando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search),
            ),
          ],
        ),
      ],
    );
  }

  Widget _listaResultados() {
    if (_resultados.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'Resultados',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ..._resultados.map((o) {
          final seleccionada = _ordenSeleccionada != null && _ordenSeleccionada!['id'] == o['id'];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: seleccionada ? brandRed : Colors.black12,
                width: seleccionada ? 2 : 1,
              ),
            ),
            child: ListTile(
              leading: Icon(Icons.receipt_long, color: seleccionada ? brandRed : Colors.black45),
              title: Text(o['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '${o['partner_nombre'] ?? 'Sin cliente'} · ${o['state'] ?? ''}',
              ),
              trailing: seleccionada ? const Icon(Icons.check_circle, color: brandRed) : null,
              onTap: () => _seleccionarOrden(o),
            ),
          );
        }),
      ],
    );
  }

  Widget _panelFoto() {
    if (_ordenSeleccionada == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Orden seleccionada: ${_ordenSeleccionada!['name']}',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 12),
        if (_fotoBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_fotoBytes!, height: 220, fit: BoxFit.cover, width: double.infinity),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ElevatedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.camera_alt),
              label: Text(_fotoBytes == null ? 'Tomar foto' : 'Tomar otra foto'),
              style: ElevatedButton.styleFrom(backgroundColor: brandRed, foregroundColor: Colors.white),
            ),
            OutlinedButton.icon(
              onPressed: _elegirDeGaleria,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir de galería'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_fotoBytes != null && !_subiendo) ? _subirReceta : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _subiendo
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Anexar receta a la orden', style: TextStyle(fontWeight: FontWeight.w800)),
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
        title: Text('${widget.sucursalNombre} • Anexar receta'),
      ),
      drawer: CustomDrawer(
        sucursalId: widget.sucursalId,
        sucursalNombre: widget.sucursalNombre,
        currentRoute: 'anexar_receta',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buscador(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ],
              _listaResultados(),
              _panelFoto(),
            ],
          ),
        ),
      ),
    );
  }
}
