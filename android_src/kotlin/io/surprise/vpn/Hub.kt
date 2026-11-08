package io.surprise.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Process-wide bridge between the VpnService and the Flutter event channel. */
object Hub {
    private val main = Handler(Looper.getMainLooper())
    @Volatile var sink: EventChannel.EventSink? = null
    @Volatile var state: String = "disconnected"

    private fun emit(m: Map<String, Any?>) {
        main.post { sink?.success(m) }
    }

    fun state(s: String, error: String? = null) {
        state = s
        emit(mapOf("type" to "state", "state" to s, "error" to error))
    }

    fun log(level: String, text: String) = emit(mapOf("type" to "log", "level" to level, "text" to text))

    fun traffic(up: Long, down: Long) = emit(mapOf("type" to "traffic", "up" to up, "down" to down))
}
