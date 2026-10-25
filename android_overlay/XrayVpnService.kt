package com.dastras.ng

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import libXray.DialerController
import libXray.LibXray
import org.json.JSONObject
import java.io.File

class XrayVpnService : VpnService(), DialerController {

    companion object {
        const val ACTION_START = "com.dastras.ng.START"
        const val ACTION_STOP = "com.dastras.ng.STOP"
        private const val CHANNEL_ID = "dastras_vpn"
        private const val NOTIF_ID = 1

        // stopped | starting | running | error:<message>
        @Volatile
        var state: String = "stopped"
    }

    private var tun: ParcelFileDescriptor? = null

    // Called by libXray for every outbound socket so it bypasses the VPN.
    override fun protectFd(fd: Long): Boolean = protect(fd.toInt())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopCore(false)
            return START_NOT_STICKY
        }
        showForeground()
        state = "starting"
        Thread { startCore() }.start()
        return START_NOT_STICKY
    }

    private fun invoke(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val req = JSONObject()
            .put("apiVersion", 3)
            .put("method", method)
            .put("payload", payload)
        return JSONObject(LibXray.invoke(req.toString()))
    }

    private fun startCore() {
        try {
            val datDir = File(filesDir, "dat").apply { mkdirs() }
            copyAsset("geoip.dat", datDir)
            copyAsset("geosite.dat", datDir)

            val cfg = JSONObject(File(filesDir, "config.json").readText())

            val builder = Builder()
                .setSession("DastRas NG")
                .setMtu(1500)
                .addAddress("172.19.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addAddress("fdfe:dcba:9876::1", 126)
                .addRoute("::", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
            try {
                builder.addDisallowedApplication(packageName)
            } catch (_: Exception) {
            }

            val pfd = builder.establish() ?: throw IllegalStateException("VPN establish failed")
            tun = pfd
            val fd = pfd.detachFd()

            val env = cfg.optJSONObject("env") ?: JSONObject()
            env.put("xray.tun.fd", fd.toString())
            env.put("xray.location.asset", datDir.absolutePath)
            cfg.put("env", env)

            LibXray.registerDialerController(this)
            LibXray.registerListenerController(this)
            try {
                LibXray.setDNS(this, "1.1.1.1:53")
            } catch (_: Throwable) {
            }

            val resp = invoke("runXray", JSONObject().put("xrayJson", cfg.toString()))
            if (!resp.optBoolean("success", false)) {
                throw IllegalStateException(resp.optString("error", "runXray failed"))
            }
            state = "running"
        } catch (t: Throwable) {
            state = "error:" + (t.message ?: t.javaClass.simpleName)
            stopCore(true)
        }
    }

    private fun stopCore(keepState: Boolean) {
        try {
            invoke("stopXray")
        } catch (_: Throwable) {
        }
        try {
            LibXray.resetDNS()
        } catch (_: Throwable) {
        }
        try {
            tun?.close()
        } catch (_: Throwable) {
        }
        tun = null
        if (!keepState) state = "stopped"
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    override fun onRevoke() {
        stopCore(false)
    }

    override fun onDestroy() {
        if (state == "running" || state == "starting") stopCore(false)
        super.onDestroy()
    }

    private fun copyAsset(name: String, dir: File) {
        val out = File(dir, name)
        val updated = packageManager.getPackageInfo(packageName, 0).lastUpdateTime
        if (out.exists() && out.length() > 0 && out.lastModified() >= updated) return
        assets.open("flutter_assets/assets/$name").use { input ->
            out.outputStream().use { input.copyTo(it) }
        }
    }

    private fun showForeground() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "DastRas NG", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val n = b.setContentTitle("DastRas NG")
            .setContentText("VPN")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }
}
