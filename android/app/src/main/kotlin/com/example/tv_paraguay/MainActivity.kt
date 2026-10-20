package com.example.tv_paraguay

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "tv_paraguay/channel_list_cache"
        private const val EXTERNAL_APPS_CHANNEL = "tv_paraguay/external_apps"
        private const val PREFERENCES_NAME = "tv_paraguay_channels"
        private const val CHANNELS_JSON_KEY = "last_valid_remote_channels_json_v1"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            val preferences = getSharedPreferences(PREFERENCES_NAME, MODE_PRIVATE)

            when (call.method) {
                "read" -> result.success(preferences.getString(CHANNELS_JSON_KEY, null))
                "write" -> {
                    val json = call.argument<String>("json")

                    if (json == null) {
                        result.error("INVALID_JSON", "No se recibió el JSON de canales", null)
                        return@setMethodCallHandler
                    }

                    val saved = preferences.edit().putString(CHANNELS_JSON_KEY, json).commit()
                    if (saved) {
                        result.success(null)
                    } else {
                        result.error("CACHE_WRITE_FAILED", "No se pudo guardar la lista", null)
                    }
                }
                "clear" -> {
                    val cleared = preferences.edit().remove(CHANNELS_JSON_KEY).commit()
                    if (cleared) {
                        result.success(null)
                    } else {
                        result.error("CACHE_CLEAR_FAILED", "No se pudo limpiar la lista", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_APPS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "launch") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val packageName = call.argument<String>("packageName")?.trim()
            if (packageName.isNullOrEmpty()) {
                result.error("INVALID_PACKAGE", "No se recibió la aplicación", null)
                return@setMethodCallHandler
            }

            try {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)

                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launchIntent)
                    result.success("opened")
                    return@setMethodCallHandler
                }

                val storeIntent = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=$packageName"),
                ).apply {
                    setPackage("com.android.vending")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }

                if (storeIntent.resolveActivity(packageManager) != null) {
                    startActivity(storeIntent)
                    result.success("storeOpened")
                } else {
                    result.success("unavailable")
                }
            } catch (error: Exception) {
                result.error("LAUNCH_FAILED", error.message, null)
            }
        }
    }
}
