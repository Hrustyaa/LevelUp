import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dashboard_data.dart';

class AndroidUsageGateway {
  const AndroidUsageGateway();

  static const _channel = MethodChannel('levelup/usage');

  Future<Map<String, Object?>?> readUsageData(Set<String> packageIds) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        packageIds.isEmpty) {
      return null;
    }
    try {
      return await _channel.invokeMapMethod<String, Object?>('getScreenTime', {
        'packageIds': packageIds.toList(growable: false),
      });
    } on PlatformException catch (error) {
      if (error.code == 'USAGE_DENIED') return null;
      rethrow;
    }
  }

  Future<DashboardInsights> read(Set<String> packageIds) async {
    Map<String, Object?>? data;
    try {
      data = await readUsageData(packageIds);
    } on MissingPluginException {
      // Keep Home available when the optional native usage bridge is absent.
      return const DashboardInsights();
    }
    if (data == null) return const DashboardInsights();

    final today = data['todayMs'];
    final week = data['week'];
    final byApp = data['byAppMs'];
    return DashboardInsights(
      todayUsageMinutes: today is int && today >= 0 ? today ~/ 60000 : null,
      week: [
        if (week is List)
          for (final day in week)
            if (day case {
              'dateMs': final int date,
              'durationMs': final int duration,
            } when duration >= 0)
              UsageDay(
                DateTime.fromMillisecondsSinceEpoch(date),
                duration ~/ 60000,
              ),
      ],
      usageByApp: {
        if (byApp is Map && today is int && today >= 0)
          for (final id in packageIds)
            if (byApp[id] case final int duration when duration >= 0)
              id: duration ~/ 60000,
      },
    );
  }
}
