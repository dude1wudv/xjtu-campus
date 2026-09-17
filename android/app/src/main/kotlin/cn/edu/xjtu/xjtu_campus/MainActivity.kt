package cn.edu.xjtu.xjtu_campus

import android.content.Intent
import android.content.Context
import android.content.ComponentName
import android.appwidget.AppWidgetManager
import android.content.pm.PackageManager
import android.Manifest
import io.flutter.embedding.engine.FlutterEngineCache
import org.json.JSONObject
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "cn.edu.xjtu.xjtu_campus/apk_installer"
        private const val BUILD_PROVENANCE_CHANNEL = "campus/build_provenance"
    }

    private var platform: MethodChannel? = null
    private var buildProvenance: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null
    override fun provideFlutterEngine(context: Context): FlutterEngine? = FlutterEngineCache.getInstance().get("campus")
    override fun shouldDestroyEngineWithHost() = false

    private fun startRefresh(): Boolean {
        val intent = Intent(this, CampusRefreshService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        return true
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("campus_route")?.let {
            platform?.invokeMethod("route", it)
            intent.removeExtra("campus_route")
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9401) {
            try {
                pendingPermission?.success(if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startRefresh() else false)
            } catch (_: Exception) { pendingPermission?.success(false) }
            pendingPermission = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("campus", flutterEngine)
        platform = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "campus/platform")
        platform!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(CampusRefreshService.running)
                    "initialRoute" -> { result.success(intent.getStringExtra("campus_route")); intent.removeExtra("campus_route") }
                    "background" -> {
                        if (call.arguments != true) {
                            stopService(Intent(this, CampusRefreshService::class.java)); result.success(false)
                        } else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (pendingPermission != null) result.success(false) else {
                                pendingPermission = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 9401)
                            }
                        } else result.success(startRefresh())
                    }
                    "widget" -> {
                        val data = call.arguments as? Map<*, *>
                        WidgetStore.write(applicationContext, if (data.isNullOrEmpty()) null else JSONObject(data).toString())
                        CampusWidget.update(applicationContext); result.success(true)
                    }
                    "pinWidget" -> {
                        val manager = AppWidgetManager.getInstance(this)
                        result.success(Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported &&
                            manager.requestPinAppWidget(ComponentName(this, CampusWidget::class.java), null, null))
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("platform_error", "系统暂不允许此操作", null) }
        }
        buildProvenance = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BUILD_PROVENANCE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(
                        mapOf(
                            "commitSha" to BuildConfig.BUILD_COMMIT_SHA,
                            "branch" to BuildConfig.BUILD_BRANCH,
                            "dirty" to BuildConfig.BUILD_DIRTY,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "path required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    "canRequestPackageInstalls" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(packageManager.canRequestPackageInstalls())
                        } else {
                            result.success(true)
                        }
                    }
                    "openUnknownAppSourcesSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        pendingPermission?.success(false)
        pendingPermission = null
        // Keep app-context operations available to Dart's background sync.
        val context = applicationContext
        platform?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "widget" -> {
                        val data = call.arguments as? Map<*, *>
                        WidgetStore.write(context, if (data.isNullOrEmpty()) null else JSONObject(data).toString())
                        CampusWidget.update(context); result.success(true)
                    }
                    "status" -> result.success(CampusRefreshService.running)
                    "background" -> {
                        if (call.arguments == false) context.stopService(Intent(context, CampusRefreshService::class.java))
                        result.success(CampusRefreshService.running && call.arguments != false)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("platform_error", "操作未完成", null) }
        }
        flutterEngine?.let { MethodChannel(it.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(null) }
        buildProvenance?.setMethodCallHandler(null)
        buildProvenance = null
        super.onDestroy()
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("APK not found: $path")
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
