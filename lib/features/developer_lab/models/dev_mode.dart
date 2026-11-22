/// Execution mode for Developer Lab.
enum DevExecutionMode {
  /// Real physical Android device mode using real native bridge, camera, and production SQLite.
  realDevice,

  /// Isolated simulation mode using fake bridge and isolated in-memory/temp database.
  /// Never issues real native access grants.
  simulation;

  /// User-friendly display label.
  String get label => this == realDevice ? 'Real Device' : 'Simulation';

  /// Whether real native Android calls are permitted.
  bool get isReal => this == realDevice;

  /// Whether simulated execution is active.
  bool get isSimulation => this == simulation;
}
