package com.fta.study_desk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class StudyWidgetProvider : HomeWidgetProvider() {

    // Must match kWidgetHabitSlots in lib/widget_bridge.dart and the row ids in
    // res/layout/study_widget.xml.
    private val rowIds = intArrayOf(R.id.habit_row_0, R.id.habit_row_1, R.id.habit_row_2)
    private val checkIds = intArrayOf(R.id.habit_check_0, R.id.habit_check_1, R.id.habit_check_2)
    private val nameIds = intArrayOf(R.id.habit_name_0, R.id.habit_name_1, R.id.habit_name_2)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.study_widget)

            renderCountdown(views, widgetData)
            renderHabits(context, views, widgetData)

            // Tapping the countdown header opens the app.
            views.setOnClickPendingIntent(
                R.id.widget_header,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun renderCountdown(views: RemoteViews, widgetData: SharedPreferences) {
        val title = widgetData.getString("exam_title", "No exam set")
        val dateStr = widgetData.getString("exam_date", null)

        val days = if (!dateStr.isNullOrBlank()) {
            try {
                val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                val midnight = { cal: Calendar ->
                    cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
                    cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
                }
                val target = Calendar.getInstance().apply { time = fmt.parse(dateStr)!!; midnight(this) }
                val today = Calendar.getInstance().apply { midnight(this) }
                val diff = (target.timeInMillis - today.timeInMillis) / 86_400_000L
                diff.toString()
            } catch (e: Exception) {
                "--"
            }
        } else "--"

        views.setTextViewText(R.id.widget_days, days)
        views.setTextViewText(R.id.widget_title, title)
    }

    /**
     * Draws today's habits. Each row gets its own PendingIntent carrying the
     * habit id, which the Flutter background isolate handles in onWidgetTapped
     * — so ticking a habit never has to open the app.
     */
    private fun renderHabits(context: Context, views: RemoteViews, widgetData: SharedPreferences) {
        val habits = try {
            JSONArray(widgetData.getString("habits_json", "[]") ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }

        views.setViewVisibility(R.id.habit_empty, if (habits.length() == 0) View.VISIBLE else View.GONE)
        views.setViewVisibility(
            R.id.widget_habits_label,
            if (habits.length() == 0) View.GONE else View.VISIBLE
        )

        for (slot in rowIds.indices) {
            if (slot >= habits.length()) {
                views.setViewVisibility(rowIds[slot], View.GONE)
                continue
            }
            val habit = habits.optJSONObject(slot) ?: continue
            val habitId = habit.optString("id")
            val done = habit.optBoolean("done", false)

            views.setViewVisibility(rowIds[slot], View.VISIBLE)
            views.setTextViewText(nameIds[slot], habit.optString("name"))
            views.setTextViewText(checkIds[slot], if (done) "●" else "○")
            views.setTextColor(checkIds[slot], if (done) ORANGE else MUTED)
            views.setTextColor(nameIds[slot], if (done) MUTED else INK)

            views.setOnClickPendingIntent(
                rowIds[slot],
                HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("studydesk://toggle?id=$habitId")
                )
            )
        }
    }

    companion object {
        private const val ORANGE = 0xFFFF5C00.toInt()
        private const val MUTED = 0xFF9A9A9A.toInt()
        private const val INK = 0xFF33373A.toInt()
    }
}
