import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/diagnostic_event.dart';
import '../services/dev_lab_log_service.dart';
import '../theme/dev_lab_theme.dart';

/// Real-time collapsible viewer for the Developer Lab diagnostic event stream.
class LiveEventLogView extends StatefulWidget {
  final DevLabLogService logService;
  final bool initialExpanded;

  const LiveEventLogView({
    super.key,
    required this.logService,
    this.initialExpanded = false,
  });

  @override
  State<LiveEventLogView> createState() => _LiveEventLogViewState();
}

class _LiveEventLogViewState extends State<LiveEventLogView> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  Color _levelColor(DevLogLevel level) {
    switch (level) {
      case DevLogLevel.info:
        return DevLabTheme.textSecondary;
      case DevLogLevel.success:
        return DevLabTheme.statusSuccess;
      case DevLogLevel.warning:
        return DevLabTheme.statusWarning;
      case DevLogLevel.error:
        return DevLabTheme.statusError;
    }
  }

  void _copyLogs() {
    final text = widget.logService.exportLogs();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostic log copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.logService,
      builder: (context, _) {
        final events = widget.logService.events;
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.terminal_rounded, size: 18, color: DevLabTheme.accent),
                      const SizedBox(width: 10),
                      Text(
                        'Live Diagnostic Log (${events.length})',
                        style: const TextStyle(
                          color: DevLabTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Copy all logs',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: events.isEmpty ? null : _copyLogs,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        tooltip: 'Clear logs',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: events.isEmpty ? null : widget.logService.clear,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 20,
                        color: DevLabTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                const Divider(),
                Container(
                  height: 220,
                  color: DevLabTheme.background,
                  child: events.isEmpty
                      ? const Center(
                          child: Text(
                            'No events recorded yet.',
                            style: TextStyle(color: DevLabTheme.textMuted, fontSize: 12),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(10),
                          itemCount: events.length,
                          reverse: true, // Show newest at top/bottom naturally
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final event = events[events.length - 1 - index];
                            final color = _levelColor(event.level);
                            final time =
                                '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  time,
                                  style: const TextStyle(
                                    color: DevLabTheme.textMuted,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    event.module.title,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    event.message,
                                    style: const TextStyle(
                                      color: DevLabTheme.textPrimary,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
