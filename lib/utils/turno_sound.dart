export 'turno_sound_base.dart';

import 'turno_sound_base.dart';
import 'turno_sound_stub.dart'
  if (dart.library.html) 'turno_sound_web.dart';

TurnoSound makeTurnoSound() => createTurnoSound();
