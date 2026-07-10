import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/ip.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static const Color brandRed = Color(0xFFE5361B);

  bool _loadingUsers = true;
  bool _loadingStats = true;

  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _stats;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _startDate = today;
    _endDate = today;

    _loadUsers();
    _loadStats();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmtDateApi(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtDateUi(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/${d.year}';
  }

  String get _rangeText {
    return 'Rango: ${_fmtDateUi(_startDate)} → ${_fmtDateUi(_endDate)}';
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);

    try {
      final res = await http.get(Uri.parse('$baseUrl/admin/usuarios'));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _users = List<Map<String, dynamic>>.from(data));
      } else {
        _toast('No se pudieron cargar los usuarios');
      }
    } catch (_) {
      _toast('Error de conexión cargando usuarios');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);

    try {
      final inicio = _fmtDateApi(_startDate);
      final fin = _fmtDateApi(_endDate);

      final res = await http.get(
        Uri.parse(
          '$baseUrl/admin/estadisticas-globales?fecha_inicio=$inicio&fecha_fin=$fin',
        ),
      );

      if (res.statusCode == 200) {
        setState(() {
          _stats = Map<String, dynamic>.from(jsonDecode(res.body));
        });
      } else {
        _toast('No se pudieron cargar las estadísticas');
      }
    } catch (_) {
      _toast('Error de conexión cargando estadísticas');
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _pickRangeTwoSteps() async {
    if (_loadingStats) return;

    final today = _dateOnly(DateTime.now());

    final startPicked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2023),
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Selecciona fecha de partida',
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

    if (startPicked == null) return;

    final start = _dateOnly(startPicked);

    final endPicked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(start) ? start : _endDate,
      firstDate: start,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Selecciona fecha final',
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

    if (endPicked == null) return;

    setState(() {
      _startDate = start;
      _endDate = _dateOnly(endPicked);
    });

    await _loadStats();
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final id = user['id'];
    final username = user['username'] ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Seguro que deseas eliminar $username?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: brandRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final res = await http.delete(Uri.parse('$baseUrl/admin/usuarios/$id'));

      if (res.statusCode == 200) {
        _toast('Usuario eliminado');
        await _loadUsers();
      } else {
        final body = jsonDecode(res.body);
        _toast(body['detail'] ?? 'No se pudo eliminar');
      }
    } catch (_) {
      _toast('Error de conexión eliminando usuario');
    }
  }

  Future<void> _openUserForm({Map<String, dynamic>? user}) async {
    final isEdit = user != null;

    final nombreCtrl = TextEditingController(
      text: user?['nombre']?.toString() ?? '',
    );

    final usernameCtrl = TextEditingController(
      text: user?['username']?.toString() ?? '',
    );

    final passCtrl = TextEditingController();

    final doctorCtrl = TextEditingController(
      text: user?['doctor_nombre']?.toString() ?? '',
    );

    String rol = user?['rol']?.toString() ?? 'sucursal';

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'Editar usuario' : 'Nuevo usuario'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(labelText: 'Usuario'),
                  ),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: isEdit
                          ? 'Nueva contraseña (opcional)'
                          : 'Contraseña',
                    ),
                  ),
                  TextField(
                    controller: doctorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Doctor / descripción (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: rol,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: const [
                      DropdownMenuItem(
                        value: 'sucursal',
                        child: Text('Sucursal'),
                      ),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Admin'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => rol = value ?? 'sucursal');
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: brandRed),
                onPressed: () async {
                  final nombre = nombreCtrl.text.trim();
                  final username = usernameCtrl.text.trim();
                  final password = passCtrl.text;
                  final doctor = doctorCtrl.text.trim();

                  if (nombre.isEmpty ||
                      username.isEmpty ||
                      (!isEdit && password.isEmpty)) {
                    _toast('Completa nombre, usuario y contraseña');
                    return;
                  }

                  final payload = {
                    'nombre': nombre,
                    'username': username,
                    'doctor_nombre': doctor.isEmpty ? null : doctor,
                    'rol': rol,
                    if (password.isNotEmpty) 'password': password,
                  };

                  try {
                    final uri = isEdit
                        ? Uri.parse('$baseUrl/admin/usuarios/${user!['id']}')
                        : Uri.parse('$baseUrl/admin/usuarios');

                    final res = isEdit
                        ? await http.put(
                            uri,
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode(payload),
                          )
                        : await http.post(
                            uri,
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode(payload),
                          );

                    if (res.statusCode == 200 || res.statusCode == 201) {
                      if (context.mounted) Navigator.pop(context, true);
                    } else {
                      final body = jsonDecode(res.body);
                      _toast(body['detail'] ?? 'No se pudo guardar');
                    }
                  } catch (_) {
                    _toast('Error de conexión guardando usuario');
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    nombreCtrl.dispose();
    usernameCtrl.dispose();
    passCtrl.dispose();
    doctorCtrl.dispose();

    if (saved == true) {
      _toast(isEdit ? 'Usuario actualizado' : 'Usuario creado');
      await _loadUsers();
    }
  }

  String _formatSeconds(dynamic seconds) {
    final n = (seconds is num) ? seconds.round() : 0;

    if (n <= 0) return '0 min';

    final min = n ~/ 60;
    final sec = n % 60;

    if (min <= 0) return '$sec seg';

    return '$min min ${sec.toString().padLeft(2, '0')} seg';
  }

  Widget _metricCard(String title, String value, IconData icon) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: brandRed.withOpacity(0.10),
              child: Icon(icon, color: brandRed),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _ageRangeHorizontal({
    required int age1to4,
    required int age5to14,
    required int age15to64,
    required int age65plus,
    bool compact = false,
  }) {
    Widget cell(String title, int value) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 10 : 14,
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black12),
            color: Colors.white,
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 11 : 13,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 18 : 22,
                  color: brandRed,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('1 - 4', age1to4),
        const SizedBox(width: 8),
        cell('5 - 14', age5to14),
        const SizedBox(width: 8),
        cell('15 - 64', age15to64),
        const SizedBox(width: 8),
        cell('> 64', age65plus),
      ],
    );
  }

  int _intValue(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _usersTab() {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Usuarios',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: brandRed),
                onPressed: () => _openUserForm(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._users.map((user) {
            final rol = user['rol']?.toString() ?? 'sucursal';

            return Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Colors.black12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: rol == 'admin' ? brandRed : Colors.black12,
                  child: Icon(
                    rol == 'admin'
                        ? Icons.admin_panel_settings
                        : Icons.store,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  user['nombre']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('${user['username']} • $rol'),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () => _openUserForm(user: user),
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteUser(user),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: brandRed,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _statsTab() {
    if (_loadingStats) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = _stats ?? {};
    final global = Map<String, dynamic>.from(stats['global'] ?? {});
    final porSucursal =
        List<Map<String, dynamic>>.from(stats['por_sucursal'] ?? []);

    final globalAge1to4 = _intValue(global, 'edad_1_4');
    final globalAge5to14 = _intValue(global, 'edad_5_14');
    final globalAge15to64 = _intValue(global, 'edad_15_64');
    final globalAge65plus = _intValue(global, 'edad_65_plus');

    Widget sucursalCard(Map<String, dynamic> row) {
      final nombre = row['sucursal_nombre']?.toString() ?? 'Sucursal';
      final total = row['total_turnos'] ?? 0;
      final espera = row['en_espera'] ?? 0;
      final finalizados = row['finalizados'] ?? 0;

      final age1to4 = _intValue(row, 'edad_1_4');
      final age5to14 = _intValue(row, 'edad_5_14');
      final age15to64 = _intValue(row, 'edad_15_64');
      final age65plus = _intValue(row, 'edad_65_plus');

      return SizedBox(
        width: 460,
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.black12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: brandRed.withOpacity(0.10),
                      child: const Icon(Icons.store, color: brandRed),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$total',
                      style: const TextStyle(
                        color: brandRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Total turnos',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _smallChip('Espera', '$espera'),
                    _smallChip('Finalizados', '$finalizados'),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Personas por rango de edad',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                _ageRangeHorizontal(
                  age1to4: age1to4,
                  age5to14: age5to14,
                  age15to64: age15to64,
                  age65plus: age65plus,
                  compact: true,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Estadísticas admin',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickRangeTwoSteps,
                style: OutlinedButton.styleFrom(
                  foregroundColor: brandRed,
                  side: const BorderSide(color: brandRed),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Filtro'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Recargar',
                onPressed: _loadingStats ? null : _loadStats,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            _rangeText,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 220,
                child: _metricCard(
                  'Total general',
                  '${global['total_turnos'] ?? 0}',
                  Icons.people_alt_outlined,
                ),
              ),
              SizedBox(
                width: 220,
                child: _metricCard(
                  'Promedio espera',
                  _formatSeconds(global['promedio_espera_segundos']),
                  Icons.hourglass_bottom,
                ),
              ),
              SizedBox(
                width: 220,
                child: _metricCard(
                  'Promedio atención',
                  _formatSeconds(global['promedio_atencion_segundos']),
                  Icons.timer_outlined,
                ),
              ),
              SizedBox(
                width: 220,
                child: _metricCard(
                  'Promedio total',
                  _formatSeconds(global['promedio_total_segundos']),
                  Icons.av_timer,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          const Text(
            'Personas por rango de edad',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 10),

          _ageRangeHorizontal(
            age1to4: globalAge1to4,
            age5to14: globalAge5to14,
            age15to64: globalAge15to64,
            age65plus: globalAge65plus,
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total por sucursal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${porSucursal.length} sucursales',
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          porSucursal.isEmpty
              ? _emptyBox('No hay datos por sucursal en ese rango.')
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: porSucursal.map(sucursalCard).toList(),
                ),
        ],
      ),
    );
  }

  Widget _smallChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: brandRed.withOpacity(0.08),
        border: Border.all(color: brandRed.withOpacity(0.20)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Colors.black87,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        appBar: AppBar(
          backgroundColor: brandRed,
          foregroundColor: Colors.white,
          title: const Text(
            'Panel admin',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              onPressed: _logout,
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                icon: Icon(Icons.manage_accounts),
                text: 'Usuarios',
              ),
              Tab(
                icon: Icon(Icons.bar_chart),
                text: 'Estadísticas',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _usersTab(),
            _statsTab(),
          ],
        ),
      ),
    );
  }
}