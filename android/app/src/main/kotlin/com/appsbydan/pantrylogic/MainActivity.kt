package com.appsbydan.pantrylogic

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pantry_logic/actions").setMethodCallHandler { call, result ->
            try {
                val value = call.arguments as? String ?: ""
                when (call.method) {
                    "openUrl" -> {
                        val uri = Uri.parse(value)
                        require(uri.scheme == "https")
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    }
                    "share" -> {
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, value)
                        }, "Share shopping list"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("UNAVAILABLE", "No app can open this action.", null) }
        }
    }
}
