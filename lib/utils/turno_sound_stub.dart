import 'package:flutter/services.dart';
import 'turno_sound_base.dart';

class _TurnoSoundStub implements TurnoSound {
  @override
  bool get enabled => true;

  @override
  void init() {}

  @override
  Future<void> enable() async {}

  @override
  void play() {
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  @override
  void dispose() {}
}

TurnoSound createTurnoSound() => _TurnoSoundStub();
