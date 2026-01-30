const String baseUrl = 'http://10.0.0.179:8000';

final Uri _base = Uri.parse(baseUrl);

String wsUrl(int sucursalId) {
  final scheme = (_base.scheme == 'https') ? 'wss' : 'ws';
  return '$scheme://${_base.authority}/ws/$sucursalId';
}
