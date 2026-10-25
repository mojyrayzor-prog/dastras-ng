package com.dastras.ng

import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import libXray.LibXray
import java.io.File

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dastras/core")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "invoke" -> {
                        val req = call.arguments as String
                        Thread {
                            val res = try {
                                LibXray.invoke(req)
                            } catch (t: Throwable) {
                                "{\"success\":false,\"error\":\"" + (t.message ?: "error").replace("\"", "'") + "\"}"
                            }
                            runOnUiThread { result.success(res) }
                        }.start()
                    }
                    "start" -> {
                        File(filesDir, "config.json").writeText(call.arguments as String)
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pending = result
                            startActivityForResult(intent, REQ_VPN)
                        } else {
                            launchService()
                            result.success("ok")
                        }
                    }
                    "stop" -> {
                        startService(Intent(this, XrayVpnService::class.java).setAction(XrayVpnService.ACTION_STOP))
                        result.success("ok")
                    }
                    "status" -> result.success(XrayVpnService.state)
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchService() {
        XrayVpnService.state = "starting"
        ContextCompat.startForegroundService(
            this,
            Intent(this, XrayVpnService::class.java).setAction(XrayVpnService.ACTION_START)
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_VPN) {
            val r = pending
            pending = null
            if (resultCode == RESULT_OK) {
                launchService()
                r?.success("ok")
            } else {
                r?.success("denied")
            }
        } else {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    companion object {
        private const val REQ_VPN = 100
    }
}
