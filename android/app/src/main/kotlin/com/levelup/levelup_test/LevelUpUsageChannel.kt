package com.levelup.levelup_test

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/**
 * Optional bridge for AndroidUsageGateway's existing getScreenTime contract.
 * Only install if the app does not already register levelup/usage.
 * Uses real UsageStatsManager foreground-duration aggregates; not ML Kit,
 * Focus time saved, a timer or synthetic usage values.
 *
 * UsageStatsManager daily buckets are approximate for partial-day windows.
 * Do not present their aggregate as second-perfect, audited screen time.
 */
internal object LevelUpUsageChannel {
    fun register(
        context: Context,
        messenger: BinaryMessenger,
        supportedPackages: Set<String>,
    ) {
        val app = context.applicationContext
        MethodChannel(messenger, "levelup/usage").setMethodCallHandler { call, result ->
            if (call.method != "getScreenTime") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val ids = call.argument<List<String>>("packageIds")
                ?.filter { it in supportedPackages }?.toSet().orEmpty()
            if (ids.isEmpty() || !hasUsageAccess(app)) {
                // No permission is unknown, NOT 0 minutes of screen time.
                result.success(null)
                return@setMethodCallHandler
            }
            // UsageStats queries are disk-backed and must not block Flutter's UI thread.
            Thread({
                try {
                    val manager = app.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    val now = System.currentTimeMillis()
                    val todayStart = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, 0)
                        set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    val byAppToday = dailyTotals(manager, ids, todayStart.timeInMillis, now)
                    val week = mutableListOf<Map<String, Long>>()
                    for (daysAgo in 6 downTo 0) {
                        val start = (todayStart.clone() as Calendar).apply {
                            add(Calendar.DAY_OF_YEAR, -daysAgo)
                        }
                        val end = (start.clone() as Calendar).apply {
                            add(Calendar.DAY_OF_YEAR, 1)
                        }
                        val duration = if (daysAgo == 0) byAppToday.values.sum() else
                            dailyTotals(
                                manager, ids, start.timeInMillis,
                                minOf(end.timeInMillis, now),
                            ).values.sum()
                        week.add(mapOf(
                            "dateMs" to start.timeInMillis,
                            "durationMs" to duration,
                        ))
                    }
                    result.success(mapOf(
                        "todayMs" to byAppToday.values.sum(),
                        "week" to week,
                        "byAppMs" to byAppToday,
                    ))
                } catch (_: SecurityException) {
                    result.success(null)
                } catch (error: Exception) {
                    result.error("USAGE_ERROR", error.javaClass.simpleName, null)
                }
            }, "LevelUp-UsageStats").start()
        }
    }

    private fun hasUsageAccess(context: Context): Boolean {
        return try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(), context.packageName,
            ) == AppOpsManager.MODE_ALLOWED
        } catch (_: SecurityException) {
            false
        }
    }

    private fun dailyTotals(
        manager: UsageStatsManager,
        ids: Set<String>,
        startMs: Long,
        endMs: Long,
    ): Map<String, Long> {
        if (endMs <= startMs) return ids.associateWith { 0L }
        val totals = ids.associateWith { 0L }.toMutableMap()
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startMs, endMs)
            ?: return totals
        for (record in stats) {
            val id = record.packageName
            if (id in ids) {
                totals[id] = (totals[id] ?: 0L) +
                    record.totalTimeInForeground.coerceAtLeast(0L)
            }
        }
        return totals
    }
}
