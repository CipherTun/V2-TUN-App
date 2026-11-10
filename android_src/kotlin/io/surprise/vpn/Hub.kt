package io.surprise.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.surprise.mobile.LogSink
import io.surprise.mobile.Mobile
import org.json.JSONObject

/** Process-wide bridge between the VpnService and the Flutter event channel. */
object Hub {
    private val main = Handler(Looper.getMainLooper())
    @Volatile var sink: EventChannel.EventSink? = null
    @Volatile var state: String = "disconnected"

    init {
        // The library's own messages (SSH handshake, TLS, payload, failover) go to the Logs tab.
        // Without this the tab only shows what the app itself says, never why a connect failed.
        runCatching {
            Mobile.setLogSink(object : LogSink {
                override fun onLog(entryJSON: String?) {
                    if (entryJSON != null) libraryLog(entryJSON)
                }
            })
        }
    }

    private fun emit(m: Map<String, Any?>) {
        main.post { sink?.success(m) }
    }

    fun state(s: String, error: String? = null) {
        state = s
        emit(mapOf("type" to "state", "state" to s, "error" to error))
    }

    fun log(level: String, text: String) = emit(mapOf("type" to "log", "level" to level, "text" to text))

    /** One entry of the library's feed: {"level":"warn","c":"ssh","msg":"...","attrs":{"k":"v"}}. */
    fun libraryLog(entryJson: String) {
        runCatching {
            val j = JSONObject(entryJson)
            val level = when (j.optString("level")) {
                "error" -> "E"
                "warn" -> "W"
                else -> "I"
            }
            val text = StringBuilder()
            val component = j.optString("c")
            if (component.isNotEmpty()) text.append(component).append(": ")
            text.append(j.optString("msg"))
            j.optJSONObject("attrs")?.let { attrs ->
                val keys = attrs.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    text.append(' ').append(k).append('=').append(attrs.opt(k))
                }
            }
            log(level, text.toString())
        }
    }

    fun traffic(up: Long, down: Long) = emit(mapOf("type" to "traffic", "up" to up, "down" to down))
}
