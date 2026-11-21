/// Supported physical exercises in LevelUp.
///
/// Designed to be extensible for future biomechanical movement detectors
/// (e.g. pushups, lunges) without rewriting the Challenge Engine.
enum ExerciseType {
  /// Bodyweight squat detected via Google ML Kit pose landmarks (hip, knee, ankle).
  squats('Squats', 'Bodyweight squats with full range of motion (standing -> down -> standing)');

  final String displayName;
  final String description;

  const ExerciseType(this.displayName, this.description);
}
