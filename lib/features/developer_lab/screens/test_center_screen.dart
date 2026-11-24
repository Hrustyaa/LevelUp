import 'package:material_ui/material_ui.dart';

import '../di/dev_lab_scope.dart';
import '../models/diagnostic_event.dart';
import '../test_center/models/test_scenario.dart';
import '../test_center/services/test_scenario_runner.dart';
import '../theme/dev_lab_theme.dart';
import '../widgets/status_badge.dart';

/// Screen 6 — Diagnostics & Test Center: Comprehensive module-by-module test suite.
///
/// Executes Category A safe real probes, Category B isolated in-app scenarios,
/// documents Category C automated references, and tracks Category D manual device checklists.
class TestCenterScreen extends StatefulWidget {
  const TestCenterScreen({super.key});

  @override
  State<TestCenterScreen> createState() => _TestCenterScreenState();
}

class _TestCenterScreenState extends State<TestCenterScreen> {
  late final TestScenarioRunner _runner;
  TestExecutionType? _selectedTypeFilter;
  final Set<String> _expandedScenarioIds = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DevLabScope.of(context);
    _runner = TestScenarioRunner(controller);
  }

  Color _statusColor(TestRunStatus status) {
    switch (status) {
      case TestRunStatus.pass:
        return DevLabTheme.statusSuccess;
      case TestRunStatus.fail:
        return DevLabTheme.statusError;
      case TestRunStatus.blocked:
        return DevLabTheme.statusWarning;
      case TestRunStatus.running:
        return DevLabTheme.accent;
      case TestRunStatus.notRun:
        return DevLabTheme.statusNeutral;
    }
  }

  Color _typeColor(TestExecutionType type) {
    switch (type) {
      case TestExecutionType.realDeviceProbe:
        return DevLabTheme.statusInfo;
      case TestExecutionType.isolatedScenario:
        return DevLabTheme.accent;
      case TestExecutionType.automatedTestRef:
        return DevLabTheme.statusNeutral;
      case TestExecutionType.manualChecklist:
        return DevLabTheme.statusSpecial;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _runner,
      builder: (context, _) {
        final all = _runner.scenarios;
        final passCount = all.where((s) => s.status == TestRunStatus.pass).length;
        final failCount = all.where((s) => s.status == TestRunStatus.fail).length;
        final blockedCount = all.where((s) => s.status == TestRunStatus.blocked).length;
        final notRunCount = all.where((s) => s.status == TestRunStatus.notRun).length;

        // Group by module
        final grouped = _runner.scenariosByModule;
        final moduleKeys = grouped.keys.toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Diagnostics & Test Center'),
            actions: [
              IconButton(
                icon: const Icon(Icons.playlist_play_rounded),
                tooltip: 'Run all executable scenarios',
                onPressed: _runner.isRunningBatch
                    ? null
                    : () => _runner.runAllExecutableScenarios(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // 1. Isolation & Security Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DevLabTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DevLabTheme.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security_rounded, size: 20, color: DevLabTheme.accent),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Isolation Policy: Test Center executes tests against isolated disposable databases and simulated bridges. Real application access is NEVER granted from this screen.',
                        style: TextStyle(color: DevLabTheme.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 2. Metrics & Execution Summary Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryMetric('TOTAL', '${all.length}', DevLabTheme.textPrimary),
                          _summaryMetric('PASS', '$passCount', DevLabTheme.statusSuccess),
                          _summaryMetric('FAIL', '$failCount', DevLabTheme.statusError),
                          _summaryMetric('BLOCKED', '$blockedCount', DevLabTheme.statusWarning),
                          _summaryMetric('NOT RUN', '$notRunCount', DevLabTheme.textMuted),
                        ],
                      ),
                      const Divider(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: _runner.isRunningBatch
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: DevLabTheme.background,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(_runner.isRunningBatch
                              ? 'Executing Test Batch...'
                              : 'Run All In-App & Probe Scenarios'),
                          onPressed: _runner.isRunningBatch
                              ? null
                              : () => _runner.runAllExecutableScenarios(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 3. Execution Type Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All Types'),
                      selected: _selectedTypeFilter == null,
                      onSelected: (_) => setState(() => _selectedTypeFilter = null),
                      backgroundColor: DevLabTheme.surface,
                      selectedColor: DevLabTheme.accent.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: _selectedTypeFilter == null
                            ? DevLabTheme.accent
                            : DevLabTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    for (final type in TestExecutionType.values) ...[
                      FilterChip(
                        label: Text(type.label),
                        selected: _selectedTypeFilter == type,
                        onSelected: (_) => setState(() => _selectedTypeFilter = type),
                        backgroundColor: DevLabTheme.surface,
                        selectedColor: _typeColor(type).withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: _selectedTypeFilter == type
                              ? _typeColor(type)
                              : DevLabTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 4. Module-by-Module Sections
              for (final mod in moduleKeys) ...[
                _buildModuleSection(mod, grouped[mod]!),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildModuleSection(BackendModuleId mod, List<TestScenario> scenarios) {
    var displayList = scenarios;
    if (_selectedTypeFilter != null) {
      displayList = displayList.where((s) => s.executionType == _selectedTypeFilter).toList();
    }
    if (displayList.isEmpty) return const SizedBox.shrink();

    final modPass = scenarios.where((s) => s.status == TestRunStatus.pass).length;
    final modTotal = scenarios.length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        collapsedIconColor: DevLabTheme.textSecondary,
        iconColor: DevLabTheme.accent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: DevLabTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                mod.title,
                style: const TextStyle(
                  color: DevLabTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$modPass / $modTotal passing',
              style: TextStyle(
                color: modPass == modTotal ? DevLabTheme.statusSuccess : DevLabTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _runner.isRunningBatch ? null : () => _runner.runModuleScenarios(mod),
          child: const Text('Run Module', style: TextStyle(fontSize: 11)),
        ),
        children: [
          const Divider(),
          for (final scenario in displayList) ...[
            _buildScenarioTile(scenario),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildScenarioTile(TestScenario scenario) {
    final isExpanded = _expandedScenarioIds.contains(scenario.id);
    final isChecklist = scenario.executionType == TestExecutionType.manualChecklist;

    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedScenarioIds.remove(scenario.id);
          } else {
            _expandedScenarioIds.add(scenario.id);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _typeColor(scenario.executionType).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    scenario.executionType.label.split('.').first,
                    style: TextStyle(
                      color: _typeColor(scenario.executionType),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scenario.title,
                    style: const TextStyle(
                      color: DevLabTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(
                  label: scenario.status.label,
                  color: _statusColor(scenario.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              scenario.description,
              style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  scenario.durationMs != null
                      ? '${scenario.durationMs}ms'
                      : (scenario.executedAt != null ? 'Executed' : 'Not run'),
                  style: const TextStyle(color: DevLabTheme.textMuted, fontSize: 10),
                ),
                Row(
                  children: [
                    if (isChecklist)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scenario.status == TestRunStatus.pass
                              ? DevLabTheme.surfaceElevated
                              : DevLabTheme.accent,
                          foregroundColor: scenario.status == TestRunStatus.pass
                              ? DevLabTheme.statusSuccess
                              : DevLabTheme.background,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _runner.toggleChecklistPass(scenario),
                        child: Text(
                          scenario.status == TestRunStatus.pass ? 'Marked Passed' : 'Mark Verified',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      )
                    else if (scenario.action != null)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: DevLabTheme.surfaceElevated,
                          foregroundColor: DevLabTheme.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: scenario.status == TestRunStatus.running
                            ? null
                            : () => _runner.runScenario(scenario),
                        child: Text(
                          scenario.status == TestRunStatus.running ? 'Running...' : 'Run Scenario',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DevLabTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DevLabTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scenario ID: ${scenario.id}',
                        style: const TextStyle(
                            color: DevLabTheme.accent, fontFamily: 'monospace', fontSize: 10)),
                    if (scenario.outputMessage != null) ...[
                      const SizedBox(height: 4),
                      Text('Output: ${scenario.outputMessage}',
                          style: const TextStyle(
                              color: DevLabTheme.statusSuccess,
                              fontSize: 11,
                              fontFamily: 'monospace')),
                    ],
                    if (scenario.errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Text('Error: ${scenario.errorMessage}',
                          style: const TextStyle(
                              color: DevLabTheme.statusError,
                              fontSize: 11,
                              fontFamily: 'monospace')),
                    ],
                    if (scenario.logs != null) ...[
                      const SizedBox(height: 4),
                      Text('Stack: ${scenario.logs}',
                          style: const TextStyle(
                              color: DevLabTheme.textMuted,
                              fontSize: 10,
                              fontFamily: 'monospace')),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}
