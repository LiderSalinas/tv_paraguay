enum PlaybackStatus {
  idle,
  loading,
  playing,
  paused,
  error;

  String get label => switch (this) {
        idle => 'Elegí un canal',
        loading => 'Cargando…',
        playing => 'En reproducción',
        paused => 'En pausa',
        error => 'Señal no disponible',
      };
}
