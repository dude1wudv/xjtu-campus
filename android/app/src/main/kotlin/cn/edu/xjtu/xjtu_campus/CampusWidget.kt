package cn.edu.xjtu.xjtu_campus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.widget.RemoteViews
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object WidgetStore {
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("campus_widget", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("campus_widget", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun write(context: Context, value: String?) {
        val prefs = context.getSharedPreferences("campus_widget", Context.MODE_PRIVATE)
        if (value == null) { prefs.edit().clear().apply(); return }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        prefs.edit().putString("data", Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)).apply()
    }
    fun read(context: Context): JSONObject = try {
        val raw = context.getSharedPreferences("campus_widget", Context.MODE_PRIVATE).getString("data", null)
        if (raw == null) JSONObject() else {
            val bytes = Base64.decode(raw, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        }
    } catch (_: Exception) { JSONObject() }
}

class CampusWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val data = WidgetStore.read(context)
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.campus_widget)
            views.setTextViewText(R.id.widget_title, "校园 · 本周")
            views.setTextViewText(R.id.widget_week, data.optString("week", "请在应用设置中开启桌面信息"))
            views.setTextViewText(R.id.widget_attendance, data.optString("attendance", "考勤 · 暂未同步"))
            views.setTextViewText(R.id.widget_homework, data.optString("homework", "作业 · 暂未同步"))
            views.setTextViewText(R.id.widget_card, data.optString("card", "校园卡 · 暂未同步"))
            views.setTextViewText(R.id.widget_seat, data.optString("seat", "座位 · 暂未同步"))
            views.setTextViewText(R.id.widget_updated, data.optString("updated", "点击打开校园助手"))
            val dayIds = intArrayOf(R.id.widget_day0, R.id.widget_day1, R.id.widget_day2, R.id.widget_day3, R.id.widget_day4, R.id.widget_day5, R.id.widget_day6)
            val labels = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
            for (i in dayIds.indices) views.setTextViewText(dayIds[i], data.optString("day$i", "${labels[i]} · 暂未同步"))
            val links = mutableMapOf(R.id.widget_week to "/calendar", R.id.widget_attendance to "/attendance",
                R.id.widget_homework to "/homework", R.id.widget_card to "/campus-card",
                R.id.widget_seat to "/library-seats", R.id.widget_title to "/home", R.id.widget_updated to "/settings")
            for (day in dayIds) links[day] = "/calendar"
            for ((view, route) in links) {
                val intent = Intent(context, MainActivity::class.java).putExtra("campus_route", route)
                    .setAction("campus.widget.$view").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                views.setOnClickPendingIntent(view, PendingIntent.getActivity(context, view, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            manager.updateAppWidget(id, views)
        }
    }
    companion object {
        fun update(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            CampusWidget().onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, CampusWidget::class.java)))
        }
    }
}
