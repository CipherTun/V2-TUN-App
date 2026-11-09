package io.surprise.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.surprise.mobile.Mobile
import io.surprise.mobile.Protector
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetAddress
import java.util.concurrent.Executors

class V2TunVpnService : VpnService() {
    private val worker = Executors.newSingleThreadExecutor()
    // Stopping must not wait behind a running connect or traffic check, so it has its own threads.
    private val closer = Executors.newSingleThreadExecutor()
    private val health = Executors.newSingleThreadExecutor()
    private val ticker = Handler(Looper.getMainLooper())
    private var pfd: ParcelFileDescriptor? = null
    @Volatile private var mode = "tun"
    @Volatile private var running = false
    @Volatile private var aborted = false   // the user asked to stop while connecting
    @Volatile private var session = 0       // changes on every connect and disconnect
    @Volatile private var badChecks = 0
    private var lastUp = 0L
    private var lastDown = 0L
    private var nm: NotificationManager? = null
    private var builder: Notification.Builder? = null

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            val up = Mobile.trafficUp()
            val down = Mobile.trafficDown()
            Hub.traffic(up, down)
            updateNotification("↓ ${rate(down - lastDown)}   ↑ ${rate(up - lastUp)}")
            lastUp = up
            lastDown = down
            ticker.postDelayed(this, 1000)
        }
    }

    // While connected, a small real request goes through the tunnel every HEALTH_MS. When it fails
    // MAX_BAD times in a row the tunnel is torn down, so the app never keeps saying "connected"
    // while nothing passes.
    private val healthTick = object : Runnable {
        override fun run() {
            if (!running) return
            val s = session
            health.execute { checkHealth(s) }
            ticker.postDelayed(this, HEALTH_MS)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                aborted = true
                // Close the tunnel right away so a connect or check that is in progress ends quickly.
                closer.execute { runCatching { if (mode == "socks") Mobile.stop() else Mobile.stopTun() } }
                worker.execute { shutdown(null) }
            }
            ACTION_START -> {
                aborted = false
                startForegroundCompat()
                val cfg = intent.getStringExtra("config") ?: ""
                val opts = JSONObject(intent.getStringExtra("opts") ?: "{}")
                worker.execute { bringUp(cfg, opts) }
            }
        }
        return START_NOT_STICKY
    }

    private fun bringUp(configIn: String, o: JSONObject) {
        if (running) shutdown(null)
        Hub.state("connecting")
        mode = o.optString("mode", "tun")
        try {
            if (mode == "socks") {
                Mobile.startEx(configIn, o.optString("listen", "127.0.0.1:10808"), o.optString("user"), o.optString("pass"))
                Hub.log("I", "SOCKS5 listening on ${o.optString("listen")}")
            } else {
                // Sockets the tunnel opens must bypass the VPN or they would loop into it.
                Mobile.setProtector(object : Protector {
                    override fun protect(fd: Long): Boolean = this@V2TunVpnService.protect(fd.toInt())
                })
                // The server name has to be resolved before the VPN exists.
                val cfg = resolveServer(configIn)
                val dns = o.optString("dns", "1.1.1.1:53")
                val dnsIp = dns.substringBeforeLast(":")
                val mtu = o.optInt("mtu", 1500)

                val b = Builder()
                    .setSession("V2-TUN")
                    .setMtu(mtu)
                    .addAddress("172.19.0.1", 30)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer(dnsIp)
                    .setMetered(o.optBoolean("metered", false))
                // The tunnel carries IPv4 only. Sending ::/0 into the interface drops IPv6 instead of leaking it.
                runCatching { b.addAddress("fdfe:dcba:9876::1", 126); b.addRoute("::", 0) }
                    .onFailure { Hub.log("W", "IPv6 blackhole route unavailable: ${it.message}") }

                val appMode = o.optString("appMode", "all")
                val apps = o.optJSONArray("apps") ?: JSONArray()
                when (appMode) {
                    "allow" -> for (i in 0 until apps.length()) runCatching { b.addAllowedApplication(apps.getString(i)) }
                    "disallow" -> for (i in 0 until apps.length()) runCatching { b.addDisallowedApplication(apps.getString(i)) }
                }
                if (appMode != "allow" && o.optBoolean("excludeSelf", true)) runCatching { b.addDisallowedApplication(packageName) }

                val p = b.establish() ?: throw IllegalStateException("The system refused to create the VPN interface")
                pfd = p
                // This service keeps ownership of the descriptor and closes it in closeInterface().
                // Handing it over with detachFd() would leave nobody to close it, so the VPN interface
                // (and the key icon in the status bar) would stay after disconnecting.
                Mobile.startTunEx(cfg, p.fd.toLong(), mtu.toLong(), dns, o.optBoolean("fakeDns"), o.optBoolean("sniff"))
                Hub.log("I", "TUN up, MTU $mtu, DNS $dns")
            }
            // Starting the tunnel opens no connection to the server, so nothing is known yet about
            // whether it works. Only a real request through it can say, and until then the state
            // stays "connecting".
            verifyTraffic()
            if (aborted) {
                shutdown(null)
                return
            }
            running = true
            lastUp = 0L
            lastDown = 0L
            session++
            badChecks = 0
            Hub.state("connected")
            V2TunTileService.refresh(this)
            ticker.post(tick)
            ticker.postDelayed(healthTick, HEALTH_MS)
        } catch (e: Throwable) {
            val msg = e.message ?: e.toString()
            if (aborted) {
                shutdown(null)
            } else {
                Hub.log("E", msg)
                shutdown(msg)
            }
        }
    }

    /** Fetches a small page through the tunnel; throws with the reason when nothing passes. */
    private fun verifyTraffic() {
        Hub.log("I", "Checking that traffic passes through the tunnel")
        try {
            val ms = Mobile.checkTunnel(20L)
            Hub.log("I", "Traffic check passed ($ms ms)")
        } catch (e: Exception) {
            throw IllegalStateException(e.message ?: "No traffic passes through the tunnel")
        }
    }

    private fun checkHealth(s: Int) {
        if (!running || s != session) return
        val failure = try {
            Mobile.checkTunnel(15L)
            null
        } catch (e: Exception) {
            e.message ?: e.toString()
        }
        if (!running || s != session) return
        if (failure == null) {
            badChecks = 0
            return
        }
        badChecks++
        Hub.log("W", "No traffic is passing through the tunnel ($badChecks/$MAX_BAD): $failure")
        if (badChecks >= MAX_BAD) {
            worker.execute {
                if (running && s == session) shutdown("No traffic is passing through the tunnel: $failure")
            }
        }
    }

    /** Replace a host name in "server" by its IP, keeping the name for SNI and WebSocket Host when unset. */
    private fun resolveServer(cfg: String): String {
        val j = JSONObject(cfg)
        val host = j.optString("server")
        if (host.isEmpty() || host.contains(':') || host.matches(Regex("""\d+\.\d+\.\d+\.\d+"""))) return cfg
        val ip = InetAddress.getByName(host).hostAddress ?: return cfg
        j.optJSONObject("tls")?.let { if (it.optString("sni").isEmpty()) it.put("sni", host) }
        j.optJSONObject("ws")?.let { if (it.optString("host").isEmpty()) it.put("host", host) }
        j.put("server", ip)
        Hub.log("I", "Resolved $host to $ip")
        return j.toString()
    }

    /** Closes the VPN interface. This is what removes the key icon; call it after the tunnel library has stopped. */
    private fun closeInterface() {
        runCatching { pfd?.close() }
        pfd = null
    }

    private fun shutdown(error: String?) {
        Hub.state("disconnecting")
        running = false
        session++
        ticker.removeCallbacks(tick)
        ticker.removeCallbacks(healthTick)
        runCatching { if (mode == "socks") Mobile.stop() else Mobile.stopTun() }
        closeInterface()
        Hub.state("disconnected", error)
        V2TunTileService.refresh(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        worker.execute { shutdown("VPN permission was revoked") }
    }

    override fun onDestroy() {
        ticker.removeCallbacks(tick)
        ticker.removeCallbacks(healthTick)
        if (running) {
            running = false
            runCatching { if (mode == "socks") Mobile.stop() else Mobile.stopTun() }
            Hub.state("disconnected")
        }
        closeInterface()
        worker.shutdown()
        closer.shutdown()
        health.shutdown()
        super.onDestroy()
    }

    private fun rate(b: Long): String = when {
        b >= 1 shl 20 -> "%.1f MB/s".format(b / 1048576.0)
        b >= 1 shl 10 -> "%.0f KB/s".format(b / 1024.0)
        else -> "$b B/s"
    }

    private fun updateNotification(text: String) {
        val b = builder ?: return
        b.setContentText(text)
        nm?.notify(1, b.build())
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(NotificationManager::class.java)
        this.nm = nm
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Tunnel status", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(
            this, 1, Intent(this, V2TunVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE
        )
        val n = Notification.Builder(this, CHANNEL)
            .setContentTitle("V2-TUN")
            .setContentText("Connecting…")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Disconnect", stop).build())
        builder = n
        val built = n.build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, built, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1, built)
    }

    companion object {
        const val ACTION_START = "io.surprise.vpn.START"
        const val ACTION_STOP = "io.surprise.vpn.STOP"
        private const val CHANNEL = "tunnel"
        private const val HEALTH_MS = 30_000L
        private const val MAX_BAD = 2
    }
}
