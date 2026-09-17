package cn.edu.xjtu.xjtu_campus

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class CampusRefreshService : Service() {
    companion object { var running = false; const val CHANNEL = "campus_refresh" }
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            FlutterEngineCache.getInstance().get("campus")?.let {
                MethodChannel(it.dartExecutor.binaryMessenger, "campus/platform").invokeMethod("refresh", null)
            }
            handler.postDelayed(this, 15 * 60 * 1000L)
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { stopSelf(); return START_NOT_STICKY }
        if (FlutterEngineCache.getInstance().get("campus") == null) { stopSelf(); return START_NOT_STICKY }
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "校园后台刷新", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, CampusRefreshService::class.java).setAction("stop"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle("校园信息后台刷新")
            .setContentText("约每 15 分钟同步一次；可随时停止")
            .setContentIntent(open).setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stop).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(401, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(401, notification)
        running = true
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopSelf() }
    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        FlutterEngineCache.getInstance().get("campus")?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, "campus/platform").invokeMethod("serviceStopped", null)
        }
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
        super.onDestroy()
    }
}
