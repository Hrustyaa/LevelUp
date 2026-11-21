/// Distinguishes the context and operational goal of a physical challenge.
enum ChallengeType {
  /// Challenge performed to earn temporary screen-time access for a restricted app.
  unlockChallenge,

  /// Voluntary physical workout performed without an app-unlock reward grant.
  freeWorkout,
}
