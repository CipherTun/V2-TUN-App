package io.surprise.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.surprise.mobile.Mobile
import io.surprise.mobile.Protector
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet4Address
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
    // Every Start and every Stop takes a new number. A connect attempt that finds the number changed
    // was cancelled (by a Stop or by a newer Start) and cleans up after itself.
    @Volatile private var attempt = 0
    @Volatile private var session = 0       // changes on every connect and disconnect
    @Volatile private var badChecks = 0
    private var lastUp = 0L
    private var lastDown = 0L
    private var nm: NotificationManager? = null
    private var builder: Notification.Builder? = null

    // Auto-reconnect: what the last Start asked for, so a lost tunnel can be brought up again.
    @Volatile private var autoReconnect = true
    @Volatile private var reconnects = 0
    private var lastCfg = ""
    private var lastOpts = JSONObject()
    private val ipv4 = Regex("""\d+\.\d+\.\d+\.\d+""")

    // Network change detection: when the phone moves to another network (Wi-Fi to mobile data and
    // back) the tunnel's connection to the server is usually dead, so it is checked right away.
    private var netCb: ConnectivityManager.NetworkCallback? = null
    @Volatile private var lastNet: Network? = null
    @Volatile private var netLost = false

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
    // MAX_BAD times in a row the tunnel is brought up again (or torn down when auto-reconnect is off
    // or has given up), so the app never keeps saying "connected" while nothing passes.
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
                val stop = ++attempt
                // Close the tunnel right away so a connect or check that is in progress ends quickly.
                closer.execute { runCatching { if (mode == "socks") Mobile.stop() else Mobile.stopTun() } }
                worker.execute { shutdown(null, stop) }
            }
            ACTION_START -> {
                val a = ++attempt
                startForegroundCompat()
                val cfg = intent.getStringExtra("config") ?: ""
                val opts = JSONObject(intent.getStringExtra("opts") ?: "{}")
                lastCfg = cfg
                lastOpts = opts
                reconnects = 0
                worker.execute { bringUp(cfg, opts, a) }
            }
        }
        return START_NOT_STICKY
    }

    private fun bringUp(configIn: String, o: JSONObject, a: Int, auto: Boolean = false) {
        fun cancelled() = attempt != a
        // Stopped or replaced before it began: the Stop or the newer Start takes over from here.
        if (cancelled()) return
        // A tunnel from an earlier connect is replaced, not announced as disconnected, and the
        // service must stay alive for the new one.
        if (running) teardown()
        Hub.state("connecting")
        mode = o.optString("mode", "tun")
        autoReconnect = o.optBoolean("autoReconnect", true)
        try {
            if (mode == "socks") {
                Mobile.startEx(configIn, o.optString("listen", "127.0.0.1:10808"), o.optString("user"), o.optString("pass"))
                Hub.log("I", "SOCKS5 listening on ${o.optString("listen")}")
            } else {
                // Sockets the tunnel opens must bypass the VPN or they would loop into it.
                Mobile.setProtector(object : Protector {
                    override fun protect(fd: Long): Boolean = this@V2TunVpnService.protect(fd.toInt())
                })
                // Every host name the tunnel has to dial (server, remote proxy, backups) is resolved
                // here, with the system resolver, before the VPN exists. Resolving them later, inside
                // the tunnel library, goes to a public DNS server that is often unreachable on the
                // networks these configs are made for, and the dial then times out on the lookup.
                val cfg = resolveServer(configIn)
                // "dns" may list several servers separated by commas or spaces. The VPN interface
                // gets every IPv4 one (the tunnel carries IPv4 only) so the system can fall back to
                // the next, and the library gets the first. tls:// entries are for the library's own
                // resolver (directDns) and are skipped here.
                val dns = o.optString("dns", "1.1.1.1:53")
                val dnsList = dns.split(',', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("tls://") }
                val dnsMain = dnsList.firstOrNull() ?: "1.1.1.1:53"
                val mtu = o.optInt("mtu", 1500)

                val b = Builder()
                    .setSession("V2-TUN")
                    .setMtu(mtu)
                    .addAddress("172.19.0.1", 30)
                    .addRoute("0.0.0.0", 0)
                    .setMetered(o.optBoolean("metered", false))
                var dnsAdded = 0
                for (d in dnsList) {
                    val h = dnsHost(d)
                    if (ipv4.matches(h)) {
                        b.addDnsServer(h)
                        dnsAdded++
                    }
                }
                if (dnsAdded == 0) b.addDnsServer("1.1.1.1")
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

                // A reconnect keeps the old interface up while the tunnel is down, so apps get no
                // connection instead of a direct one. The new interface replaces it, then it is closed.
                val old = pfd
                val p = b.establish() ?: throw IllegalStateException("The system refused to create the VPN interface")
                pfd = p
                runCatching { old?.close() }
                // This service keeps ownership of the descriptor and closes it in closeInterface().
                // Handing it over with detachFd() would leave nobody to close it, so the VPN interface
                // (and the key icon in the status bar) would stay after disconnecting.
                Mobile.startTunEx(cfg, p.fd.toLong(), mtu.toLong(), dnsMain, o.optBoolean("fakeDns"), o.optBoolean("sniff"))
                Hub.log("I", "TUN up, MTU $mtu, DNS $dns")
            }
            // Starting the tunnel opens no connection to the server, so nothing is known yet about
            // whether it works. Only a real request through it can say, and until then the state
            // stays "connecting".
            verifyTraffic()
            if (cancelled()) {
                teardown()
                return
            }
            running = true
            lastUp = 0L
            lastDown = 0L
            session++
            badChecks = 0
            reconnects = 0
            if (auto) Hub.log("I", "Reconnected")
            Hub.state("connected")
            V2TunTileService.refresh(this)
            ticker.post(tick)
            ticker.postDelayed(healthTick, HEALTH_MS)
            watchNetwork()
        } catch (e: Throwable) {
            if (cancelled()) {
                // The Stop, or the newer Start, that cancelled this attempt does the announcing.
                teardown()
            } else {
                val msg = e.message ?: e.toString()
                Hub.log("E", msg)
                // A first connect that fails is reported at once (a wrong config would otherwise
                // loop); a reconnect that fails goes on to the next try.
                if (auto) reconnect(msg, a) else shutdown(msg, a)
            }
        }
    }

    /**
     * The tunnel stopped working. Stops it, keeps the VPN interface and tries again after a growing
     * pause (3 s, 6 s, 12 s ... up to 60 s), at most MAX_RECONNECTS times, then disconnects with the
     * reason. A Stop or a new Start during the pause cancels it. Runs on the worker thread.
     */
    private fun reconnect(why: String, owner: Int) {
        if (attempt != owner) return
        if (!autoReconnect || reconnects >= MAX_RECONNECTS) {
            val note = if (reconnects > 0) "$why (gave up after $reconnects reconnect attempts)" else why
            shutdown(note, owner)
            return
        }
        reconnects++
        val wait = minOf(RECONNECT_BASE_MS shl (reconnects - 1), RECONNECT_MAX_MS)
        Hub.log("W", "$why. Reconnecting in ${wait / 1000} s (attempt $reconnects of $MAX_RECONNECTS)")
        running = false
        session++
        ticker.removeCallbacks(tick)
        ticker.removeCallbacks(healthTick)
        runCatching { if (mode == "socks") Mobile.stop() else Mobile.stopTun() }
        Hub.state("connecting")
        updateNotification("Reconnecting…")
        val next = ++attempt
        ticker.postDelayed({ worker.execute { bringUp(lastCfg, lastOpts, next, true) } }, wait)
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
        val at = attempt
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
                if (running && s == session) reconnect("No traffic is passing through the tunnel: $failure", at)
            }
        }
    }

    /** Starts watching the real networks; a change triggers a quick check (see [recheckSoon]). */
    private fun watchNetwork() {
        if (netCb != null) return
        runCatching {
            val cm = getSystemService(ConnectivityManager::class.java)
            val req = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()
            lastNet = null
            netLost = false
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    val changed = (lastNet != null && lastNet != network) || netLost
                    lastNet = network
                    netLost = false
                    if (changed && running) {
                        Hub.log("I", "The network changed, checking the tunnel")
                        recheckSoon()
                    }
                }

                override fun onLost(network: Network) {
                    if (network == lastNet) netLost = true
                }
            }
            cm.registerNetworkCallback(req, cb)
            netCb = cb
        }.onFailure { Hub.log("W", "Network change detection is unavailable: ${it.message}") }
    }

    private fun unwatchNetwork() {
        val cb = netCb ?: return
        netCb = null
        runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(cb) }
    }

    /**
     * After a network change one failed check is enough to reconnect (instead of MAX_BAD in a row),
     * and it runs after a short pause so the new network can settle.
     */
    private fun recheckSoon() {
        val s = session
        badChecks = MAX_BAD - 1
        ticker.postDelayed({ health.execute { checkHealth(s) } }, 2500)
    }

    /**
     * Replace every host name the tunnel dials by its IP: the server, the payload's remote proxy,
     * the XHTTP download server, and the same for each backup. Names that the config leaves unset
     * (SNI, WebSocket Host, payload [host]) keep the original server name.
     */
    private fun resolveServer(cfg: String): String {
        val j = JSONObject(cfg)
        resolveOutbound(j)
        j.optJSONArray("backups")?.let { arr ->
            for (i in 0 until arr.length()) arr.optJSONObject(i)?.let { resolveOutbound(it) }
        }
        return j.toString()
    }

    private fun resolveOutbound(j: JSONObject) {
        val host = j.optString("server")
        if (host.isNotEmpty() && !isIpLiteral(host)) {
            val ip = lookup(host)
            val proto = j.optString("protocol").lowercase()
            val net = j.optString("network").lowercase()
            val hysteria = proto == "hysteria" || proto == "hysteria1" || proto == "hy" || proto == "hysteria2" || proto == "hy2"
            // The editor drops empty objects, so "tls" and "ws" may not exist even though the name is
            // needed: REALITY, QUIC and Hysteria take their TLS name from tls.sni, and the HTTP based
            // transports take the Host / authority from ws.host. Without them the library would
            // fall back to the address it dials, which is now the IP.
            val needsTlsName = j.has("reality") || net == "quic" || hysteria
            val tls = j.optJSONObject("tls") ?: if (needsTlsName) JSONObject().also { j.put("tls", it) } else null
            tls?.let { if (it.optString("sni").isEmpty()) it.put("sni", host) }
            val httpTransport = net in HTTP_TRANSPORTS
            val ws = j.optJSONObject("ws") ?: if (httpTransport) JSONObject().also { j.put("ws", it) } else null
            // A Host entry in ws.headers is honored by the library when ws.host is empty, so it must
            // not be overridden here.
            ws?.let { if (it.optString("host").isEmpty() && !hasHostHeader(it.optJSONObject("headers"))) it.put("host", host) }
            // Without this the payload's [host] (empty means the server) would turn into the IP.
            j.optJSONObject("payload")?.let { if (it.optString("host").isEmpty()) it.put("host", host) }
            j.put("server", ip)
        }
        // HTTP-Injector style remote proxy: the TCP connection goes to this host:port, so its name
        // must be resolved here too. This is the lookup that used to time out inside the tunnel.
        j.optJSONObject("payload")?.let { p ->
            val proxy = p.optString("proxy")
            if (proxy.isNotEmpty()) p.put("proxy", resolveHostPort(proxy))
        }
        j.optJSONObject("xhttp")?.optJSONObject("download")?.let { d ->
            val s = d.optString("server")
            if (s.isNotEmpty() && !isIpLiteral(s)) {
                val dtls = d.optJSONObject("tls") ?: if (d.has("reality")) JSONObject().also { d.put("tls", it) } else null
                dtls?.let { if (it.optString("sni").isEmpty()) it.put("sni", s) }
                if (d.optString("host").isEmpty() && !hasHostHeader(d.optJSONObject("headers"))) d.put("host", s)
                d.put("server", lookup(s))
            }
        }
    }

    private fun hasHostHeader(h: JSONObject?): Boolean {
        if (h == null) return false
        val keys = h.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            if (k.equals("host", ignoreCase = true) && h.optString(k).isNotEmpty()) return true
        }
        return false
    }

    private fun isIpLiteral(h: String) = h.contains(':') || h.matches(Regex("""\d+\.\d+\.\d+\.\d+"""))

    /** The host of a DNS entry: "1.1.1.1:53" gives "1.1.1.1", "[::1]:53" gives "::1", a bare address stays. */
    private fun dnsHost(e: String): String = when {
        e.startsWith("[") -> e.substringAfter("[").substringBefore("]")
        e.count { it == ':' } == 1 -> e.substringBefore(":")
        else -> e
    }

    /** Resolves [host] with the system resolver (IPv4 first, the tunnel carries IPv4 only). */
    private fun lookup(host: String): String {
        val all = try {
            InetAddress.getAllByName(host)
        } catch (e: Exception) {
            throw IllegalStateException("Could not resolve $host: ${e.message ?: "unknown host"}")
        }
        val ip = (all.firstOrNull { it is Inet4Address } ?: all.first()).hostAddress
            ?: throw IllegalStateException("Could not resolve $host")
        Hub.log("I", "Resolved $host to $ip")
        return ip
    }

    /** "name:port" becomes "ip:port"; an IP, an IPv6 literal or a value without a port is kept. */
    private fun resolveHostPort(hp: String): String {
        val i = hp.lastIndexOf(':')
        if (i <= 0 || hp.startsWith("[")) return hp
        val h = hp.substring(0, i)
        if (isIpLiteral(h)) return hp
        return "${lookup(h)}:${hp.substring(i + 1)}"
    }

    /** Closes the VPN interface. This is what removes the key icon; call it after the tunnel library has stopped. */
    private fun closeInterface() {
        runCatching { pfd?.close() }
        pfd = null
    }

    /** Stops the tunnel and closes the VPN interface, without announcing anything or stopping the service. */
    private fun teardown() {
        running = false
        session++
        ticker.removeCallbacks(tick)
        ticker.removeCallbacks(healthTick)
        unwatchNetwork()
        runCatching { if (mode == "socks") Mobile.stop() else Mobile.stopTun() }
        closeInterface()
    }

    /**
     * Disconnects and stops the service. [owner] is the attempt number this shutdown belongs to:
     * when a newer Start has arrived since, the shutdown leaves everything to it.
     */
    private fun shutdown(error: String?, owner: Int = -1) {
        if (owner >= 0 && attempt != owner) return
        Hub.state("disconnecting")
        teardown()
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
        unwatchNetwork()
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
        private const val MAX_RECONNECTS = 6
        private const val RECONNECT_BASE_MS = 3_000L
        private const val RECONNECT_MAX_MS = 60_000L
        // Transports whose Host / authority comes from ws.host (names as the library accepts them).
        private val HTTP_TRANSPORTS = setOf("ws", "websocket", "httpupgrade", "h2", "http", "grpc", "xhttp", "splithttp")
    }
}
