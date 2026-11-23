package com.chibi.flashcard.chibi_flashcard

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class FlashcardWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_WORD = "flutter.chibi_widget_word"
        private const val KEY_PHONETIC = "flutter.chibi_widget_phonetic"
        private const val KEY_MEANING = "flutter.chibi_widget_meaning"
        private const val KEY_SUMMARY = "flutter.chibi_widget_summary"

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, FlashcardWidgetProvider::class.java)
            )
            for (id in ids) {
                updateAppWidget(context, manager, id)
            }
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val word = prefs.getString(KEY_WORD, null) ?: "Chưa có từ mới"
            val phonetic = prefs.getString(KEY_PHONETIC, null) ?: ""
            val meaning = prefs.getString(KEY_MEANING, null)
                ?: "Mở ứng dụng Chibi Flashcard để thêm từ mới nhé!"
            val summary = prefs.getString(KEY_SUMMARY, null)
                ?: "💎 TỪ MỚI TRONG NGÀY • CHIBI FLASHCARD"

            val views = RemoteViews(context.packageName, R.layout.flashcard_daily_widget)
            views.setTextViewText(R.id.widget_header, summary)
            views.setTextViewText(R.id.widget_word, word)
            views.setTextViewText(
                R.id.widget_phonetic,
                if (phonetic.isNotEmpty()) "/$phonetic/" else "Chạm để nghe & ôn tập"
            )
            views.setTextViewText(R.id.widget_meaning, meaning)

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
