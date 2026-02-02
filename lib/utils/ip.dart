const String baseUrl = 'http://18.188.101.215:8002';

final Uri _base = Uri.parse(baseUrl);

String wsUrl(int sucursalId) {
  final scheme = (_base.scheme == 'https') ? 'wss' : 'ws';
  return '$scheme://${_base.authority}/ws/$sucursalId';
}
