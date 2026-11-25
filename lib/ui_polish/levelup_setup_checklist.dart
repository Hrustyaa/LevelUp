import 'package:material_ui/material_ui.dart';

import 'levelup_ui.dart';

enum LevelUpSetupStatus { ready, attention, unknown, optional }

/// The parent builds this from actual existing Android and saved app state.
/// The widget does not infer or change permission status.
class LevelUpSetupItem {
  const LevelUpSetupItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.status,
    this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final LevelUpSetupStatus status;
  final VoidCallback? onTap;
}

class LevelUpSetupChecklist extends StatelessWidget {
  const LevelUpSetupChecklist({
    super.key,
    required this.language,
    required this.items,
  });

  final String language;
  final List<LevelUpSetupItem> items;

  String statusText(LevelUpSetupStatus status) => switch (status) {
    LevelUpSetupStatus.ready => levelUpText(
      language,
      'Готово',
      'Ready',
      'Дайын',
    ),
    LevelUpSetupStatus.attention => levelUpText(
      language,
      'Требуется настройка',
      'Action needed',
      'Баптау керек',
    ),
    LevelUpSetupStatus.unknown => levelUpText(
      language,
      'Не проверено',
      'Not checked',
      'Тексерілмеді',
    ),
    LevelUpSetupStatus.optional => levelUpText(
      language,
      'Необязательно',
      'Optional',
      'Міндетті емес',
    ),
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < items.length; index++) ...[
        _row(items[index]),
        if (index < items.length - 1)
          const Divider(color: LevelUpUi.border, height: 1),
      ],
    ],
  );

  Widget _row(LevelUpSetupItem item) => InkWell(
    onTap: item.onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Icon(
              item.icon,
              size: 21,
              color: item.status == LevelUpSetupStatus.ready
                  ? LevelUpUi.lime
                  : LevelUpUi.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: LevelUpUi.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: const TextStyle(color: LevelUpUi.muted, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  statusText(item.status),
                  style: TextStyle(
                    color: item.status == LevelUpSetupStatus.ready
                        ? LevelUpUi.lime
                        : LevelUpUi.muted,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (item.onTap != null)
            const Icon(Icons.chevron_right, color: LevelUpUi.muted, size: 20),
        ],
      ),
    ),
  );
}
