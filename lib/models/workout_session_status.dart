/// Discrete lifecycle states of a physical workout session.
enum WorkoutSessionStatus {
  /// Session has been instantiated from ChallengeRequest and definition parameters.
  created,

  /// Camera initialization, user positioning, and countdown phase.
  preparing,

  /// Live exercise repetition tracking is actively running.
  active,

  /// Target verified repetitions have been achieved. Terminal successful state.
  completed,

  /// User voluntarily stopped or exited the session before achieving goal. Terminal state.
  cancelled,

  /// Camera stream failure, unrecoverable tracking error, or hardware failure. Terminal state.
  failed;

  /// Whether this state is a terminal state (no further transitions permitted).
  bool get isTerminal =>
      this == completed || this == cancelled || this == failed;

  /// Whether the session is actively receiving verified repetition updates.
  bool get canAcceptProgress => this == active;

  /// Whether the session finished successfully.
  bool get isSuccessful => this == completed;
}
