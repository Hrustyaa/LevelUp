import '../../models/diagnostic_event.dart';

/// Test execution classification enforcing security and isolation.
enum TestExecutionType {
  /// Category A: Safe, read-only inspection using real platform APIs.
  realDeviceProbe('A. Real Device Probe', 'Safe read-only check on live Android hardware'),

  /// Category B: Fully isolated in-app scenario with disposable DB and simulation bridge.
  isolatedScenario('B. Isolated In-App Scenario', 'Runs against disposable sandbox; never touches real data'),

  /// Category C: Reference to external unit/integration suites executed via `flutter test`.
  automatedTestRef('C. Automated Suite Ref', 'CI/CLI verified invariant test specifications'),

  /// Category D: Physical human verification protocol requiring manual interaction on hardware.
  manualChecklist('D. Manual Device Checklist', 'Physical verification checklist; never auto-passed');

  final String label;
  final String description;
  const TestExecutionType(this.label, this.description);
}

/// Operational result state of a test scenario.
enum TestRunStatus {
  notRun('NOT RUN'),
  running('RUNNING'),
  pass('PASS'),
  fail('FAIL'),
  blocked('BLOCKED');

  final String label;
  const TestRunStatus(this.label);
}

/// Structured outcome returned by an executed test scenario action.
class TestScenarioResult {
  final TestRunStatus status;
  final String? message;
  final String? error;
  final String? logs;

  const TestScenarioResult({
    required this.status,
    this.message,
    this.error,
    this.logs,
  });

  factory TestScenarioResult.pass([String? message, String? logs]) => TestScenarioResult(
        status: TestRunStatus.pass,
        message: message ?? 'Scenario passed all invariant assertions.',
        logs: logs,
      );

  factory TestScenarioResult.fail(String error, [String? logs]) => TestScenarioResult(
        status: TestRunStatus.fail,
        error: error,
        logs: logs,
      );

  factory TestScenarioResult.blocked(String reason) => TestScenarioResult(
        status: TestRunStatus.blocked,
        error: reason,
      );
}

/// Specification and runtime state of a module diagnostic test scenario.
class TestScenario {
  final String id;
  final BackendModuleId moduleId;
  final String title;
  final String description;
  final TestExecutionType executionType;
  final Future<TestScenarioResult> Function()? action;

  TestRunStatus status;
  DateTime? executedAt;
  int? durationMs;
  String? outputMessage;
  String? errorMessage;
  String? logs;

  TestScenario({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.description,
    required this.executionType,
    this.action,
    this.status = TestRunStatus.notRun,
    this.executedAt,
    this.durationMs,
    this.outputMessage,
    this.errorMessage,
    this.logs,
  });
}
