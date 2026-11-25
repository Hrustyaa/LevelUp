import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/dashboard_data.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const control = ExistingFocusGateway.channel;
  const gateway = ExistingFocusGateway();
  const request = FocusChallengeRequest(id: 'request-id', target: 'test.app');

  tearDown(() => messenger.setMockMethodCallHandler(control, null));

  test(
    'a Flutter preview does not consume the old unbound native request',
    () async {
      messenger.setMockMethodCallHandler(control, (call) {
        expect(call.method, 'claimFocusChallenge');
        throw MissingPluginException();
      });
      expect(await gateway.claimChallenge(), isNull);
    },
  );

  test('only a bound challenge opens the real camera route', () async {
    Object? pending = true;
    messenger.setMockMethodCallHandler(control, (call) async {
      expect(call.method, 'claimFocusChallenge');
      return pending;
    });

    expect(await gateway.claimChallenge(), isNull);
    pending = {'id': request.id, 'target': request.target};
    final claimed = await gateway.claimChallenge();
    expect(claimed?.id, request.id);
    expect(claimed?.target, request.target);
  });

  test(
    'a grant must match the target, active service and future deadline',
    () async {
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      final native = <String, dynamic>{
        'enabled': true,
        'serviceEnabled': true,
        'target': request.target,
        'unlockUntil': deadline.millisecondsSinceEpoch,
      };
      var returnedDeadline = deadline.millisecondsSinceEpoch;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(control, (call) async {
        methods.add(call.method);
        switch (call.method) {
          case 'grantAccess':
            expect(call.arguments, {
              'id': request.id,
              'target': request.target,
              'repetitions': 5,
            });
            return returnedDeadline;
          case 'getState':
            return native;
          default:
            fail('Unexpected method ${call.method}');
        }
      });

      final grant = await gateway.completeChallenge(request, 5);
      expect(grant.isConfirmedAt(DateTime.now()), isTrue);
      expect(
        grant.accessUntil?.millisecondsSinceEpoch,
        deadline.millisecondsSinceEpoch,
      );
      expect(methods, ['grantAccess', 'getState']);

      native['target'] = 'different.app';
      await expectLater(
        gateway.completeChallenge(request, 5),
        throwsStateError,
      );
      native['target'] = request.target;

      native['serviceEnabled'] = false;
      await expectLater(
        gateway.completeChallenge(request, 5),
        throwsStateError,
      );
      native['serviceEnabled'] = true;

      returnedDeadline--;
      await expectLater(
        gateway.completeChallenge(request, 5),
        throwsStateError,
      );
      returnedDeadline = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch;
      native['unlockUntil'] = returnedDeadline;
      await expectLater(
        gateway.completeChallenge(request, 5),
        throwsStateError,
      );
    },
  );
}
