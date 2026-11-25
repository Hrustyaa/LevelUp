/// Supported physical exercises in LevelUp.
///
/// Designed to be extensible for future biomechanical movement detectors
/// without rewriting the Challenge Engine.
enum ExerciseType {
  /// Bodyweight squat detected via Google ML Kit pose landmarks (hip, knee, ankle).
  squats('Squats', 'Bodyweight squats with full range of motion (standing -> down -> standing)'),

  /// Front-facing push-up detected via Google ML Kit pose landmarks
  /// (shoulder, elbow, wrist). Phone placed on a surface facing the user.
  ///
  /// NOTE: Push-ups are available for Free Workout only.
  /// Native unlock via push-ups is disabled until physical-device accuracy
  /// validation is complete.
  pushUp('Push-ups', 'Front-facing push-ups (top -> down -> top). Phone on surface facing user.');

  final String displayName;
  final String description;

  const ExerciseType(this.displayName, this.description);
}
