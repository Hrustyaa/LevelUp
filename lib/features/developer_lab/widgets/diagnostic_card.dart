import 'package:material_ui/material_ui.dart';

import '../theme/dev_lab_theme.dart';

/// Reusable structured card for diagnostic panels and module inspection.
class DiagnosticCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? badge;
  final IconData? icon;
  final Widget? child;
  final Widget? trailing;
  final List<Widget>? actions;
  final VoidCallback? onTap;

  const DiagnosticCard({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.icon,
    this.child,
    this.trailing,
    this.actions,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DevLabTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: DevLabTheme.accent),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: DevLabTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: DevLabTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?badge,
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 14),
              child!,
            ],
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );

    return Card(child: content);
  }
}
