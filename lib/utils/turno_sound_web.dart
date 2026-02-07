import 'dart:html' as html;
import 'turno_sound_base.dart';

class _TurnoSoundWeb implements TurnoSound {
  html.AudioElement? _audio;
  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  void init() {
    _audio = html.AudioElement('assets/sounds/turno.mp3')..preload = 'auto';
  }

  @override
  Future<void> enable() async {
    if (_audio == null) return;
    try {
      _audio!.volume = 0;
      await _audio!.play(); // debe venir de un click/tap del usuario
      _audio!.pause();
      _audio!.currentTime = 0;
      _audio!.volume = 1;
      _enabled = true;
    } catch (_) {
      _enabled = false;
    }
  }

  @override
  void play() {
    if (!_enabled || _audio == null) return;
    try {
      _audio!.currentTime = 0;
      _audio!.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _audio = null;
  }
}

TurnoSound createTurnoSound() => _TurnoSoundWeb();
