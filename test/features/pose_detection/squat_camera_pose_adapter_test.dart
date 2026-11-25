import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/integration/pose_event_adapter.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';

import '../../support/verified_squat_frames.dart';

void main() {
  test('long tracking loss and lifecycle interruption discard a partial squat', () {
    final adapter = SquatCameraPoseAdapter();
    addTearDown(adapter.dispose);
    var time = DateTime.utc(2026);
    SquatCounterResult frame(bool down, {int elapsed = 85}) {
      time = time.add(Duration(milliseconds: elapsed));
      return adapter.processPose(squatPose(down: down), timestamp: time);
    }

    frame(true);
    expect(frame(true).phase, SquatPhase.down);
    frame(false, elapsed: 600);
    expect(frame(false).repetitionCount, 0);

    frame(true);
    frame(true);
    frame(false);
    expect(frame(false).repetitionCount, 1);

    frame(true);
    expect(frame(true).phase, SquatPhase.down);
    adapter.interruptTracking();
    frame(false);
    expect(frame(false).repetitionCount, 1);
  });
}
