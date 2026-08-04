import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../utils/ip.dart';
import '../widgets/custom_drawer.dart';

const Color _brandRed = Color(0xFFE5361B);

/// Las recetas se guardan en formato 4:3 (o 3:4 si la foto es vertical):
/// recorta al centro la mayor porción posible con esa proporción.
Uint8List _recortarA43(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final w = decoded.width;
  final h = decoded.height;
  final esVertical = h >= w;

  int targetW, targetH;
  if (esVertical) {
    targetW = w;
    targetH = (w * 4 / 3).round();
    if (targetH > h) {
      targetH = h;
      targetW = (h * 3 / 4).round();
    }
  } else {
    targetH = h;
    targetW = (h * 4 / 3).round();
    if (targetW > w) {
      targetW = w;
      targetH = (w * 3 / 4).round();
    }
  }

  final x = ((w - targetW) / 2).round();
  final y = ((h - targetH) / 2).round();

  final recortada = img.copyCrop(decoded, x: x, y: y, width: targetW, height: targetH);
  return Uint8List.fromList(img.encodeJpg(recortada, quality: 90));
}

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
  final _buscarController = TextEditingController();

  bool _buscando = false;
  String? _error;
  List<Map<String, dynamic>> _resultados = [];

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

  Future<void> _abrirPopupOrden(Map<String, dynamic> orden) async {
    final subido = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RecetaDialog(
        orden: orden,
        sucursalNombre: widget.sucursalNombre,
      ),
    );

    if (subido == true) {
      _toast('Receta anexada correctamente ✅');
      setState(() {
        _resultados = [];
        _buscarController.clear();
      });
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
                  hintText: 'Número de orden (ej. S-52628 o 52628)',
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
                backgroundColor: _brandRed,
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
          'Resultados · toca una orden para anexar la receta',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ..._resultados.map((o) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.black12),
            ),
            child: ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.black45),
              title: Text(o['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '${o['partner_nombre'] ?? 'Sin cliente'} · ${o['state'] ?? ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _abrirPopupOrden(o),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _brandRed,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Popup que se abre al elegir una orden: cámara/galería + subida de la receta.
class _RecetaDialog extends StatefulWidget {
  final Map<String, dynamic> orden;
  final String sucursalNombre;

  const _RecetaDialog({
    required this.orden,
    required this.sucursalNombre,
  });

  @override
  State<_RecetaDialog> createState() => _RecetaDialogState();
}

class _RecetaDialogState extends State<_RecetaDialog> {
  final _picker = ImagePicker();

  Uint8List? _fotoBytes;
  String? _fotoNombre;
  double _fotoAspectRatio = 4 / 3;
  bool _procesandoFoto = false;
  bool _subiendo = false;
  String? _error;

  Future<void> _tomarFoto(ImageSource source) async {
    setState(() => _procesandoFoto = true);
    try {
      final XFile? foto = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (foto == null) return;

      final original = await foto.readAsBytes();
      final recortada = _recortarA43(original);
      final decoded = img.decodeImage(recortada);

      setState(() {
        _fotoBytes = recortada;
        _fotoNombre = foto.name;
        _fotoAspectRatio = decoded != null ? decoded.width / decoded.height : 4 / 3;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'No se pudo abrir la cámara/galería: $e');
    } finally {
      if (mounted) setState(() => _procesandoFoto = false);
    }
  }

  Future<void> _subirReceta() async {
    if (_fotoBytes == null) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });

    try {
      final orderId = widget.orden['id'];
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

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'No se pudo subir la receta: $e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Widget _previewFoto() {
    if (_fotoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: _fotoAspectRatio,
          child: Image.memory(_fotoBytes!, fit: BoxFit.cover, width: double.infinity),
        ),
      );
    }
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12, style: BorderStyle.solid),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: Colors.black38, size: 32),
          SizedBox(height: 6),
          Text('Sin foto todavía', style: TextStyle(color: Colors.black45)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, color: _brandRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.orden['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _subiendo ? null : () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(
                    '${widget.orden['partner_nombre'] ?? 'Sin cliente'} · ${widget.orden['state'] ?? ''}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'La foto se recorta automáticamente a formato 4:3',
                  style: TextStyle(color: Colors.black45, fontSize: 11),
                ),
                const SizedBox(height: 8),
                _previewFoto(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_subiendo || _procesandoFoto) ? null : () => _tomarFoto(ImageSource.camera),
                        icon: _procesandoFoto
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt, size: 20),
                        label: Text(_fotoBytes == null ? 'Tomar foto' : 'Repetir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandRed,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_subiendo || _procesandoFoto) ? null : () => _tomarFoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined, size: 20),
                        label: const Text('Galería'),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                ],
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
            ),
          ),
        ),
      ),
    );
  }
}
