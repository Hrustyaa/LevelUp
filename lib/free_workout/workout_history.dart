import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'workout_session.dart';

/// Local, factual workout history. Does not fabricate XP or Focus unlock events.
class WorkoutHistory {
  WorkoutHistory(this.prefs);
  final SharedPreferences prefs;
  static const key = 'levelup.free_workout.history.v1';
  static const maxEntries = 200;

  List<WorkoutResult> all() {
    final encoded = prefs.getStringList(key) ?? const [];
    final parsed = <WorkoutResult>[];
    for (final item in encoded) {
      try {
        parsed.add(
          WorkoutResult.fromJson(jsonDecode(item) as Map<String, dynamic>),
        );
      } on FormatException {
        // Corrupt older records are ignored rather than crashing the UI.
      } on TypeError {
        // Incompatible old record.
      }
    }
    return List.unmodifiable(parsed);
  }

  Future<bool> add(WorkoutResult result) {
    if (result.sets.isEmpty || result.sets.any((count) => count <= 0)) {
      return Future.value(false);
    }
    final entries = [result, ...all()].take(maxEntries).toList();
    return prefs.setStringList(
      key,
      entries.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }
}
