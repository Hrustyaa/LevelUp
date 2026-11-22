import 'package:material_ui/material_ui.dart';

import '../models/module_status.dart';

/// Compact visual pill representing an explicit health or lifecycle status.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
  });

  /// Factory for standard module health enum.
  factory StatusBadge.fromHealth(ModuleHealthStatus status, {bool compact = false}) {
    return StatusBadge(
      label: status.label,
      color: status.color,
      icon: status.icon,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: compact ? 11 : 13,
              color: color,
            ),
            SizedBox(width: compact ? 3 : 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
