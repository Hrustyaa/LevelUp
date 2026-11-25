/// Supported physical exercises in LevelUp.
///
/// Designed to be extensible for future biomechanical movement detectors
/// without rewriting the Challenge Engine.
enum ExerciseType {
  /// Bodyweight squat detected via Google ML Kit pose landmarks (hip, knee, ankle).
  squats('Squats', 'Bodyweight squats with full range of motion (standing -> down -> standing)'),

  /// Front-facing push-up detected via Google ML Kit pose landmarks
  /// across the arms, trunk and legs. Unlock is experimental in debug builds.
  pushUp('Push-ups', 'Front-facing push-ups (top -> down -> top). Phone on surface facing user.');

  final String displayName;
  final String description;

  const ExerciseType(this.displayName, this.description);
}
