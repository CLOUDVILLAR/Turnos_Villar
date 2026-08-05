String _resolveBaseUrl() {
  final uri = Uri.base;
  final host = uri.host;

  if (host == 'turnos.villar.do') {
    return '${uri.scheme}://${uri.host}/api';
  }

  if (host == '18.118.99.60') {
    return 'http://18.118.99.60:8002';
  }

  if (host == 'localhost' || host == '127.0.0.1') {
    return 'http://$host:8002';
  }

  return '${uri.scheme}://${uri.host}/api';
}

final String baseUrl = _resolveBaseUrl();
final Uri _base = Uri.parse(baseUrl);

String wsUrl(int sucursalId) {
  final uri = Uri.base;
  final host = uri.host;

  if (host == 'turnos.villar.do') {
    return 'wss://${uri.host}/ws/$sucursalId';
  }

  final scheme = (_base.scheme == 'https') ? 'wss' : 'ws';
  return '$scheme://${_base.authority}/ws/$sucursalId';
}