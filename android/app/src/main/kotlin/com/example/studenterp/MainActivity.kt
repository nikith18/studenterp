package com.example.studenterp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "studenterp/local_store")
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("attendly_demo", MODE_PRIVATE)
                when (call.method) {
                    "read" -> result.success(prefs.getString("attendance_history", "[]"))
                    "write" -> {
                        val value = call.argument<String>("value")
                        if (value == null) result.error("invalid_data", "Missing value", null)
                        else if (prefs.edit().putString("attendance_history", value).commit()) result.success(true)
                        else result.error("write_failed", "Could not save local attendance", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
