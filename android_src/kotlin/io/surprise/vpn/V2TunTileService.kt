package io.surprise.vpn

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: tap to connect with the last used config, or disconnect. */
class V2TunTileService : TileService() {

    override fun onStartListening() = render()

    private fun render() {
        val tile = qsTile ?: return
        val on = Hub.state == "connected"
        val busy = Hub.state == "connecting" || Hub.state == "disconnecting"
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "V2-TUN"
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = when {
                busy -> "Working"
                on -> "Connected"
                else -> "Off"
            }
        }
        tile.updateTile()
    }

    override fun onClick() {
        if (Hub.state == "connected" || Hub.state == "connecting") {
            startService(Intent(this, V2TunVpnService::class.java).setAction(V2TunVpnService.ACTION_STOP))
            return
        }
        val prefs = getSharedPreferences("v2tun", Context.MODE_PRIVATE)
        val cfg = prefs.getString("last_config", null)
        // No saved config, or VPN permission missing: open the app instead.
        if (cfg == null || VpnService.prepare(this) != null) {
            val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE))
            } else {
                @Suppress("DEPRECATION") startActivityAndCollapse(open)
            }
            return
        }
        startForegroundService(
            Intent(this, V2TunVpnService::class.java)
                .setAction(V2TunVpnService.ACTION_START)
                .putExtra("config", cfg)
                .putExtra("opts", prefs.getString("last_opts", "{}"))
        )
    }

    companion object {
        fun refresh(ctx: Context) {
            requestListeningState(ctx, ComponentName(ctx, V2TunTileService::class.java))
        }
    }
}
