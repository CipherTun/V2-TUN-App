package io.surprise.vpn

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.surprise.mobile.Mobile
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "io.surprise.vpn/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                Hub.sink = sink
                sink?.success(mapOf("type" to "state", "state" to Hub.state, "error" to null))
            }
            override fun onCancel(args: Any?) { Hub.sink = null }
        })

        MethodChannel(messenger, "io.surprise.vpn/core").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> prepareVpn(result)
                "start" -> {
                    val opts = org.json.JSONObject(call.argument<Map<String, Any?>>("opts") ?: emptyMap<String, Any?>())
                    val i = Intent(this, V2TunVpnService::class.java)
                        .setAction(V2TunVpnService.ACTION_START)
                        .putExtra("config", call.argument<String>("config"))
                        .putExtra("opts", opts.toString())
                    // The Quick Settings tile reconnects with these. They hold passwords and keys,
                    // so they are stored encrypted, and the old plain copy is removed.
                    runCatching {
                        Vault.put(this, "last_config", call.argument<String>("config") ?: "")
                        Vault.put(this, "last_opts", opts.toString())
                    }
                    getSharedPreferences("v2tun", MODE_PRIVATE).edit().remove("last_config").remove("last_opts").apply()
                    startForegroundService(i)
                    result.success(null)
                }
                "stop" -> {
                    startService(Intent(this, V2TunVpnService::class.java).setAction(V2TunVpnService.ACTION_STOP))
                    result.success(null)
                }
                "isRunning" -> result.success(Hub.state == "connected")
                "installedApps" -> background(result) { installedApps() }
                "openVpnSettings" -> {
                    startActivity(Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "keepScreenOn" -> {
                    val on = call.argument<Boolean>("on") == true
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "shareText" -> {
                    val send = Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                    startActivity(Intent.createChooser(send, call.argument<String>("title") ?: "Share"))
                    result.success(null)
                }
                "vaultPut" -> background(result) {
                    Vault.put(this, call.argument<String>("key") ?: "", call.argument<String>("value") ?: "")
                    null
                }
                "vaultGet" -> background(result) { Vault.get(this, call.argument<String>("key") ?: "") }
                else -> library(call, result)
            }
        }
    }

    /** Calls into the tunnel library. They can block, so they never run on the main thread. */
    private fun library(call: MethodCall, result: MethodChannel.Result) {
        fun s(k: String) = call.argument<String>(k) ?: ""
        fun n(k: String) = (call.argument<Number>(k) ?: 0).toLong()
        when (call.method) {
            "parseLink" -> background(result) { Mobile.parseLink(s("link")) }
            "shareLink" -> background(result) { Mobile.shareLink(s("config"), s("name")) }
            "validate" -> background(result) { Mobile.validate(s("config")) }
            "ping" -> background(result) { Mobile.ping(s("config"), s("url")) }
            "speedTest" -> background(result) { Mobile.speedTest(s("config"), "", n("seconds")) }
            "scanHosts" -> background(result) {
                Mobile.scanHosts(s("config"), s("field"), s("values"), s("target"), n("jobs"), n("seconds"))
            }
            "payloadPreview" -> background(result) { Mobile.payloadPreview(s("config")) }
            "previewPayload" -> background(result) { Mobile.previewPayload(s("template"), s("host"), s("server"), n("port")) }
            "validatePayload" -> background(result) {
                try { Mobile.validatePayload(s("template")); "" } catch (e: Exception) { e.message ?: "invalid" }
            }
            "explainRoute" -> background(result) { Mobile.explainRoute(s("network"), s("addr"), s("protocol")) }
            "updateRouting" -> background(result) { Mobile.updateRouting(s("routing")); null }
            "setRouteList" -> background(result) { Mobile.setRouteList(s("name"), s("items")); null }
            "activeOutbound" -> background(result) { Mobile.activeOutbound().toInt() }
            "resetTraffic" -> background(result) { Mobile.resetTraffic(); null }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: Throwable) {
                main.post { result.error("lib", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun installedApps(): List<Map<String, String>> {
        val pm = packageManager
        return pm.getInstalledApplications(PackageManager.GET_META_DATA)
            .filter { pm.getLaunchIntentForPackage(it.packageName) != null && it.packageName != packageName }
            .map { mapOf("package" to it.packageName, "label" to pm.getApplicationLabel(it).toString()) }
            .sortedBy { it["label"]!!.lowercase() }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
        } else {
            pendingPrepare = result
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_VPN)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN) {
            pendingPrepare?.success(resultCode == Activity.RESULT_OK)
            pendingPrepare = null
        }
    }

    companion object { private const val REQ_VPN = 7001 }
}
