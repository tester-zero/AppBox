package com.appbox.app

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.util.LruCache
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.appbox.app/installed_apps"
    private val STREAM_CHANNEL = "com.appbox.app/app_stream"
    @Volatile
    private var isStreamCancelled = false

    // Cache for app list (in-memory)
    private var cachedApps: List<Map<String, Any>>? = null

    // Cache for icons (LruCache for 100 icons)
    private val iconCache = LruCache<String, ByteArray>(100)

    // Cache for launch intents
    private val intentCache = mutableMapOf<String, android.content.Intent?>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    isStreamCancelled = false
                    Thread {
                        try {
                            val pm = packageManager
                            val installedApps = pm.getInstalledApplications(0)
                            val batch = mutableListOf<Map<String, Any>>()

                            for (appInfo in installedApps) {
                                if (isStreamCancelled) break

                                val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                                val isUpdatedSystemApp = (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0

                                if (isSystemApp && !isUpdatedSystemApp) continue

                                val launchIntent = pm.getLaunchIntentForPackage(appInfo.packageName)
                                if (launchIntent == null) continue

                                if (appInfo.packageName == packageName) continue

                                try {
                                    val appName = pm.getApplicationLabel(appInfo).toString()
                                    val iconBytes = getIconBytes(
                                        appInfo.packageName,
                                        pm.getApplicationIcon(appInfo)
                                    )

                                    val appData = mapOf(
                                        "packageName" to appInfo.packageName,
                                        "appName" to appName,
                                        "icon" to iconBytes
                                    )
                                    batch.add(appData)

                                    if (batch.size == 5) {
                                        val payload = ArrayList(batch)
                                        batch.clear()
                                        runOnUiThread {
                                            events?.success(payload)
                                        }
                                        Thread.sleep(16)
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("AppBox", "Skipping app: ${appInfo.packageName}", e)
                                }
                            }

                            if (!isStreamCancelled && batch.isNotEmpty()) {
                                val payload = ArrayList(batch)
                                runOnUiThread {
                                    events?.success(payload)
                                }
                            }

                            runOnUiThread {
                                events?.endOfStream()
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                events?.error("UNAVAILABLE", "Failed to stream installed apps", null)
                            }
                        }
                    }.start()
                }

                override fun onCancel(arguments: Any?) {
                    isStreamCancelled = true
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    try {
                        val apps = getInstalledApps()
                        result.success(apps)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Failed to get installed apps", null)
                    }
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        launchApp(packageName)
                        result.success(null)
                    } else {
                        result.error("INVALID", "Package name is null", null)
                    }
                }
                "preWarmIntents" -> {
                    val packageNames = call.argument<List<String>>("packageNames")
                    if (packageNames != null) {
                        preWarmIntents(packageNames)
                        result.success(null)
                    } else {
                        result.error("INVALID", "Package names is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        // Return cached apps if available
        cachedApps?.let { return it }

        val pm = packageManager
        val apps = mutableListOf<Map<String, Any>>()

        val installedApps = pm.getInstalledApplications(0)

        for (appInfo in installedApps) {
            // ✅ Skip system apps
            val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
            val isUpdatedSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0

            if (isSystemApp && !isUpdatedSystemApp) {
                continue
            }

            // ✅ Only apps with launcher (can be launched by user)
            val launchIntent = pm.getLaunchIntentForPackage(appInfo.packageName)
            if (launchIntent == null) {
                continue
            }

            // ✅ Remove your own app
            if (appInfo.packageName == this.packageName) {
                continue
            }

            try {
                val appName = pm.getApplicationLabel(appInfo).toString()
                val packageName = appInfo.packageName
                val iconBytes = getIconBytes(packageName, pm.getApplicationIcon(appInfo))

                apps.add(
                    mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "icon" to iconBytes
                    )
                )
            } catch (e: Exception) {
                android.util.Log.e("AppBox", "Skipping app: ${appInfo.packageName}", e)
            }
        }

        // ✅ Sort apps alphabetically
        apps.sortBy { it["appName"] as String }

        // Cache the apps
        cachedApps = apps

        android.util.Log.d("AppBox", "User apps count: ${apps.size}")
        return apps
    }

    private fun getIconBytes(packageName: String, drawable: Drawable): ByteArray {
        // Check cache first
        iconCache[packageName]?.let { return it }

        // Convert drawable to byte array
        val bytes = drawableToByteArray(drawable)

        // Cache the bytes
        iconCache.put(packageName, bytes)

        return bytes
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        val size = 128 // fixed safe size

        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        try {
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
        } catch (e: Exception) {
            // fallback: blank bitmap
            android.util.Log.e("AppBox", "Drawable draw failed", e)
        }

        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
        bitmap.recycle()

        return stream.toByteArray()
    }

    private fun preWarmIntents(packageNames: List<String>) {
        for (pkg in packageNames) {
            if (!intentCache.containsKey(pkg)) {
                val intent = packageManager.getLaunchIntentForPackage(pkg)
                intentCache[pkg] = intent
            }
        }
    }

    private fun launchApp(packageName: String) {
        try {
            var intent = intentCache[packageName]
            if (intent == null) {
                intent = packageManager.getLaunchIntentForPackage(packageName)
                intentCache[packageName] = intent
            }
            if (intent != null) {
                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } else {
                // 🚀 Bonus: Open app settings if launch fails
                android.util.Log.e("AppBox", "No launch intent for $packageName, opening settings")
                val settingsIntent = android.content.Intent(
                    android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                )
                settingsIntent.data = android.net.Uri.parse("package:$packageName")
                settingsIntent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(settingsIntent)
            }
        } catch (e: Exception) {
            android.util.Log.e("AppBox", "Failed to launch $packageName", e)
            // Show toast for user feedback
            android.widget.Toast.makeText(
                this,
                "Cannot open this app",
                android.widget.Toast.LENGTH_SHORT
            ).show()
        }
    }
}
