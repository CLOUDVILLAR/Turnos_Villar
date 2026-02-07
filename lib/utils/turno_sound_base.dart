abstract class TurnoSound {
  bool get enabled;

  void init();
  Future<void> enable(); // en Web desbloquea audio con gesto del usuario
  void play();
  void dispose();
}
