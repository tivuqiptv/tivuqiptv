package com.tivuq.iptv

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import android.util.Log
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONArray
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.URI
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.security.Principal
import java.security.PrivateKey
import java.security.KeyPairGenerator
import java.security.KeyFactory
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.X509Certificate
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.math.BigInteger
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.X509ExtendedKeyManager

class LocalCompanionPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val CHANNEL = "com.tivuq.iptv/local_companion"
        private const val DISCOVERY_PORT = 47852
        private const val CERT_ALIAS = "tivuq_local_companion_tls_software_v1"
        private const val TLS_PRIVATE_KEY = "tls_private_key_v1"
        private const val TLS_CERTIFICATE = "tls_certificate_v1"
        private const val PREFS = "tivuq_local_companion_v1"
        private const val CLIENTS_KEY = "paired_clients"
        private const val MAX_BODY_BYTES = 64 * 1024
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioPool = Executors.newCachedThreadPool()
    private val running = AtomicBoolean(false)
    private val secureRandom = SecureRandom()
    private var serverSocket: SSLServerSocket? = null
    private var discoverySocket: DatagramSocket? = null
    @Volatile private var pairingCode: String? = null
    @Volatile private var pairingExpiresAt = 0L
    @Volatile private var pairingAttempts = 0
    @Volatile private var lastPairingPromptAt = 0L
    @Volatile private var liveChannelCatalog = JSONArray()
    @Volatile private var liveChannelIds = emptySet<String>()
    @Volatile private var contentCatalog = JSONArray()
    @Volatile private var appSettings = JSONObject()
    private var pendingLiveUpdateId: String? = null
    private var pendingLiveCatalog = JSONArray()
    private var pendingLiveIds = LinkedHashSet<String>()
    private var pendingContentUpdateId: String? = null
    private var pendingContentCatalog = JSONArray()
    private var pendingContentIds = LinkedHashSet<String>()
    private var deviceId = ""
    private var deviceName = "TIVUQIPTV"
    private var certificateSha256 = ""

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(statusMap())
                "beginPairing" -> result.success(beginPairing())
                "cancelPairing" -> {
                    pairingCode = null
                    pairingExpiresAt = 0L
                    pairingAttempts = 0
                    result.success(null)
                }
                "getPairedDevices" -> result.success(pairedDeviceMaps())
                "revokeDevice" -> {
                    val id = call.argument<String>("id")
                    result.success(id != null && revokeDevice(id))
                }
                "revokeAll" -> {
                    saveClients(JSONObject())
                    result.success(null)
                }
                "publishLiveChannels" -> {
                    val channels = call.argument<List<Map<String, Any?>>>("channels")
                        ?: emptyList()
                    val catalog = JSONArray()
                    val ids = LinkedHashSet<String>()
                    channels.take(10_000).forEach { item ->
                        val id = item["id"]?.toString()?.trim().orEmpty()
                        val name = item["name"]?.toString()?.trim().orEmpty()
                        val category = item["category"]?.toString()?.trim().orEmpty()
                        val profileName = item["profileName"]?.toString()?.trim().orEmpty()
                        if (id.isNotEmpty() && name.isNotEmpty() && ids.add(id)) {
                            catalog.put(
                                JSONObject()
                                    .put("id", id)
                                    .put("name", name.take(240))
                                    .put("category", category.take(160))
                                    .put("profileName", profileName.take(80))
                                    .put("isFavorite", item["isFavorite"] as? Boolean ?: false)
                                    .put("isRecentlyWatched", item["isRecentlyWatched"] as? Boolean ?: false)
                                    .put("recentOrder", (item["recentOrder"] as? Number)?.toInt() ?: -1),
                            )
                        }
                    }
                    liveChannelCatalog = catalog
                    liveChannelIds = ids
                    result.success(catalog.length())
                }
                "publishContentCatalog" -> {
                    val contents = call.argument<List<Map<String, Any?>>>("contents")
                        ?: emptyList()
                    val catalog = JSONArray()
                    val ids = LinkedHashSet<String>()
                    contents.take(25_000).forEach { item ->
                        val id = item["id"]?.toString()?.trim().orEmpty()
                        val name = item["name"]?.toString()?.trim().orEmpty()
                        val category = item["category"]?.toString()?.trim().orEmpty()
                        val profileName = item["profileName"]?.toString()?.trim().orEmpty()
                        val type = item["type"]?.toString()?.trim().orEmpty()
                        if (id.isNotEmpty() && name.isNotEmpty() &&
                            (type == "movie" || type == "series") && ids.add(id)
                        ) {
                            catalog.put(
                                JSONObject()
                                    .put("id", id)
                                    .put("name", name.take(240))
                                    .put("category", category.take(160))
                                    .put("profileName", profileName.take(80))
                                    .put("type", type)
                                    .put("isFavorite", item["isFavorite"] as? Boolean ?: false)
                                    .put("isRecentlyWatched", item["isRecentlyWatched"] as? Boolean ?: false)
                                    .put("lastWatchedAt", item["lastWatchedAt"]?.toString().orEmpty().take(48))
                                    .put("isNewlyAdded", item["isNewlyAdded"] as? Boolean ?: false),
                            )
                        }
                    }
                    contentCatalog = catalog
                    result.success(catalog.length())
                }
                "beginLiveChannelsUpdate" -> {
                    pendingLiveUpdateId = call.argument<String>("updateId")
                    pendingLiveCatalog = JSONArray()
                    pendingLiveIds = LinkedHashSet()
                    result.success(null)
                }
                "appendLiveChannelsUpdate" -> {
                    val updateId = call.argument<String>("updateId")
                    if (updateId != pendingLiveUpdateId) {
                        result.success(null)
                    } else {
                        val channels = call.argument<List<Map<String, Any?>>>("channels")
                            ?: emptyList()
                        channels.forEach { appendLiveChannel(it) }
                        result.success(null)
                    }
                }
                "commitLiveChannelsUpdate" -> {
                    val updateId = call.argument<String>("updateId")
                    if (updateId != pendingLiveUpdateId) {
                        result.success(liveChannelCatalog.length())
                    } else {
                        liveChannelCatalog = pendingLiveCatalog
                        liveChannelIds = pendingLiveIds.toSet()
                        pendingLiveUpdateId = null
                        result.success(liveChannelCatalog.length())
                    }
                }
                "beginContentCatalogUpdate" -> {
                    pendingContentUpdateId = call.argument<String>("updateId")
                    pendingContentCatalog = JSONArray()
                    pendingContentIds = LinkedHashSet()
                    result.success(null)
                }
                "appendContentCatalogUpdate" -> {
                    val updateId = call.argument<String>("updateId")
                    if (updateId != pendingContentUpdateId) {
                        result.success(null)
                    } else {
                        val contents = call.argument<List<Map<String, Any?>>>("contents")
                            ?: emptyList()
                        contents.forEach { appendContent(it) }
                        result.success(null)
                    }
                }
                "commitContentCatalogUpdate" -> {
                    val updateId = call.argument<String>("updateId")
                    if (updateId != pendingContentUpdateId) {
                        result.success(contentCatalog.length())
                    } else {
                        contentCatalog = pendingContentCatalog
                        pendingContentUpdateId = null
                        result.success(contentCatalog.length())
                    }
                }
                "publishAppSettings" -> {
                    val settings = call.argument<Map<String, Any?>>("settings")
                        ?: emptyMap()
                    appSettings = JSONObject(settings)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        start()
    }

    private fun appendLiveChannel(item: Map<String, Any?>) {
        if (pendingLiveCatalog.length() >= 10_000) return
        val id = item["id"]?.toString()?.trim().orEmpty()
        val name = item["name"]?.toString()?.trim().orEmpty()
        val category = item["category"]?.toString()?.trim().orEmpty()
        val profileName = item["profileName"]?.toString()?.trim().orEmpty()
        if (id.isNotEmpty() && name.isNotEmpty() && pendingLiveIds.add(id)) {
            pendingLiveCatalog.put(
                JSONObject()
                    .put("id", id)
                    .put("name", name.take(240))
                    .put("category", category.take(160))
                    .put("profileName", profileName.take(80))
                    .put("isFavorite", item["isFavorite"] as? Boolean ?: false)
                    .put("isRecentlyWatched", item["isRecentlyWatched"] as? Boolean ?: false)
                    .put("recentOrder", (item["recentOrder"] as? Number)?.toInt() ?: -1),
            )
        }
    }

    private fun appendContent(item: Map<String, Any?>) {
        if (pendingContentCatalog.length() >= 25_000) return
        val id = item["id"]?.toString()?.trim().orEmpty()
        val name = item["name"]?.toString()?.trim().orEmpty()
        val category = item["category"]?.toString()?.trim().orEmpty()
        val profileName = item["profileName"]?.toString()?.trim().orEmpty()
        val type = item["type"]?.toString()?.trim().orEmpty()
        if (id.isNotEmpty() && name.isNotEmpty() &&
            (type == "movie" || type == "series") && pendingContentIds.add(id)
        ) {
            pendingContentCatalog.put(
                JSONObject()
                    .put("id", id)
                    .put("name", name.take(240))
                    .put("category", category.take(160))
                    .put("profileName", profileName.take(80))
                    .put("type", type)
                    .put("isFavorite", item["isFavorite"] as? Boolean ?: false)
                    .put("isRecentlyWatched", item["isRecentlyWatched"] as? Boolean ?: false)
                    .put("lastWatchedAt", item["lastWatchedAt"]?.toString().orEmpty().take(48))
                    .put("isNewlyAdded", item["isNewlyAdded"] as? Boolean ?: false),
            )
        }
    }

    fun stop() {
        running.set(false)
        runCatching { serverSocket?.close() }
        runCatching { discoverySocket?.close() }
        ioPool.shutdownNow()
    }

    private fun start() {
        if (!running.compareAndSet(false, true)) return
        ioPool.execute {
            try {
                val keyStore = ensureCertificate()
                val certificate = keyStore.getCertificate(CERT_ALIAS) as X509Certificate
                certificateSha256 = sha256Hex(certificate.encoded)
                val androidId = Settings.Secure.getString(
                    activity.contentResolver,
                    Settings.Secure.ANDROID_ID,
                ) ?: "unknown"
                deviceId = sha256Hex("tivuq:$androidId".toByteArray()).take(24)
                deviceName = localDeviceName()
                val keyManagers = KeyManagerFactory.getInstance(
                    KeyManagerFactory.getDefaultAlgorithm(),
                ).apply { init(keyStore, tlsPassword()) }.keyManagers
                val delegate = keyManagers
                    .filterIsInstance<X509ExtendedKeyManager>()
                    .first()
                val forcedKeyManager = AliasForcingKeyManager(
                    delegate,
                    CERT_ALIAS,
                )
                val sslContext = SSLContext.getInstance("TLS").apply {
                    init(arrayOf(forcedKeyManager), null, secureRandom)
                }
                val socket = sslContext.serverSocketFactory.createServerSocket(
                    0,
                    24,
                ) as SSLServerSocket
                socket.enabledProtocols = socket.supportedProtocols.filter {
                    it == "TLSv1.2" || it == "TLSv1.3"
                }.toTypedArray()
                serverSocket = socket
                startDiscovery(socket.localPort)
                while (running.get()) {
                    val client = socket.accept()
                    ioPool.execute { handleClient(client) }
                }
            } catch (error: Exception) {
                Log.e("TivuqCompanion", "Local server stopped", error)
                running.set(false)
            }
        }
    }

    private class AliasForcingKeyManager(
        private val delegate: X509ExtendedKeyManager,
        private val alias: String,
    ) : X509ExtendedKeyManager() {
        override fun getClientAliases(
            keyType: String?,
            issuers: Array<out Principal>?,
        ): Array<String> = emptyArray()

        override fun chooseClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out Principal>?,
            socket: Socket?,
        ): String? = null

        override fun getServerAliases(
            keyType: String?,
            issuers: Array<out Principal>?,
        ): Array<String> = arrayOf(alias)

        override fun chooseServerAlias(
            keyType: String?,
            issuers: Array<out Principal>?,
            socket: Socket?,
        ): String = alias

        override fun chooseEngineServerAlias(
            keyType: String?,
            issuers: Array<out Principal>?,
            engine: SSLEngine?,
        ): String = alias

        override fun getCertificateChain(alias: String?): Array<X509Certificate> =
            delegate.getCertificateChain(this.alias)

        override fun getPrivateKey(alias: String?): PrivateKey =
            delegate.getPrivateKey(this.alias)
    }

    private fun ensureCertificate(): KeyStore {
        val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        var privateKeyBytes = prefs.getString(TLS_PRIVATE_KEY, null)
            ?.let { runCatching { Base64.decode(it, Base64.NO_WRAP) }.getOrNull() }
        var certificateBytes = prefs.getString(TLS_CERTIFICATE, null)
            ?.let { runCatching { Base64.decode(it, Base64.NO_WRAP) }.getOrNull() }

        if (privateKeyBytes == null || certificateBytes == null) {
            val pair = KeyPairGenerator.getInstance("RSA").apply {
                initialize(2048, secureRandom)
            }.generateKeyPair()
            privateKeyBytes = pair.private.encoded
            certificateBytes = createSelfSignedCertificate(
                pair.public.encoded,
                pair.private,
            )
            prefs.edit()
                .putString(
                    TLS_PRIVATE_KEY,
                    Base64.encodeToString(privateKeyBytes, Base64.NO_WRAP),
                )
                .putString(
                    TLS_CERTIFICATE,
                    Base64.encodeToString(certificateBytes, Base64.NO_WRAP),
                )
                .apply()
        }

        val privateKey = KeyFactory.getInstance("RSA").generatePrivate(
            PKCS8EncodedKeySpec(privateKeyBytes),
        )
        val certificate = CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(certificateBytes))
        return KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null)
            setKeyEntry(
                CERT_ALIAS,
                privateKey,
                tlsPassword(),
                arrayOf(certificate),
            )
        }
    }

    private fun tlsPassword(): CharArray = "tivuq-local-tls".toCharArray()

    private fun createSelfSignedCertificate(
        publicKeyInfo: ByteArray,
        privateKey: PrivateKey,
    ): ByteArray {
        val signatureAlgorithm = derSequence(
            byteArrayOf(
                0x06, 0x09, 0x2A, 0x86.toByte(), 0x48, 0x86.toByte(),
                0xF7.toByte(), 0x0D, 0x01, 0x01, 0x0B,
            ),
            byteArrayOf(0x05, 0x00),
        )
        val commonName = derSequence(
            derSet(
                derSequence(
                    byteArrayOf(0x06, 0x03, 0x55, 0x04, 0x03),
                    derValue(0x0C, "TIVUQIPTV Local".toByteArray()),
                ),
            ),
        )
        val validity = derSequence(
            derValue(0x17, "200101000000Z".toByteArray()),
            derValue(0x17, "491231235959Z".toByteArray()),
        )
        val serial = BigInteger(96, secureRandom).abs().add(BigInteger.ONE)
        val tbs = derSequence(
            derValue(0xA0, derInteger(BigInteger.valueOf(2))),
            derInteger(serial),
            signatureAlgorithm,
            commonName,
            validity,
            commonName,
            publicKeyInfo,
        )
        val signature = Signature.getInstance("SHA256withRSA").run {
            initSign(privateKey, secureRandom)
            update(tbs)
            sign()
        }
        return derSequence(
            tbs,
            signatureAlgorithm,
            derValue(0x03, byteArrayOf(0) + signature),
        )
    }

    private fun derInteger(value: BigInteger): ByteArray =
        derValue(0x02, value.toByteArray())

    private fun derSequence(vararg values: ByteArray): ByteArray =
        derValue(0x30, joinDer(values))

    private fun derSet(vararg values: ByteArray): ByteArray =
        derValue(0x31, joinDer(values))

    private fun joinDer(values: Array<out ByteArray>): ByteArray {
        val output = ByteArrayOutputStream()
        values.forEach { output.write(it) }
        return output.toByteArray()
    }

    private fun derValue(tag: Int, contents: ByteArray): ByteArray {
        val output = ByteArrayOutputStream()
        output.write(tag)
        val size = contents.size
        if (size < 128) {
            output.write(size)
        } else {
            val bytes = BigInteger.valueOf(size.toLong()).toByteArray()
                .dropWhile { it == 0.toByte() }
                .toByteArray()
            output.write(0x80 or bytes.size)
            output.write(bytes)
        }
        output.write(contents)
        return output.toByteArray()
    }

    private fun startDiscovery(apiPort: Int) {
        ioPool.execute {
            try {
                val socket = DatagramSocket(null).apply {
                    reuseAddress = true
                    bind(InetSocketAddress(DISCOVERY_PORT))
                }
                discoverySocket = socket
                val buffer = ByteArray(512)
                while (running.get()) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    socket.receive(packet)
                    val request = String(
                        packet.data,
                        packet.offset,
                        packet.length,
                        StandardCharsets.UTF_8,
                    )
                    if (request != "TIVUQ_DISCOVER_V1") continue
                    val payload = JSONObject()
                        .put("service", "tivuq-tv")
                        .put("version", 1)
                        .put("appId", activity.packageName)
                        .put("deviceId", deviceId)
                        .put("name", deviceName)
                        .put("port", apiPort)
                        .put("certificateSha256", certificateSha256)
                        .toString().toByteArray(StandardCharsets.UTF_8)
                    socket.send(
                        DatagramPacket(payload, payload.size, packet.address, packet.port),
                    )
                }
            } catch (error: Exception) {
                Log.e("TivuqCompanion", "Discovery stopped", error)
                // API keeps running for clients that already know the TV address.
            }
        }
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            if (!isLocalClient(client.inetAddress)) {
                Log.e(
                    "TivuqCompanion",
                    "Rejected non-local client: ${client.inetAddress.hostAddress}",
                )
                return
            }
            client.soTimeout = 8_000
            val input: BufferedInputStream
            val output: BufferedOutputStream
            try {
                input = BufferedInputStream(client.getInputStream())
                output = BufferedOutputStream(client.getOutputStream())
            } catch (error: Exception) {
                Log.e("TivuqCompanion", "TLS handshake failed", error)
                return
            }
            try {
                if (running.get() && !client.isClosed) {
                    val requestLine = readLine(input) ?: return
                    val parts = requestLine.split(' ')
                    if (parts.size < 2) {
                        writeJson(output, 400, error("bad_request"))
                        return
                    }
                    val method = parts[0].uppercase()
                    val path = parts[1].substringBefore('?')
                    val headers = mutableMapOf<String, String>()
                    while (true) {
                        val line = readLine(input) ?: return
                        if (line.isEmpty()) break
                        val separator = line.indexOf(':')
                        if (separator > 0) {
                            headers[line.substring(0, separator).trim().lowercase()] =
                                line.substring(separator + 1).trim()
                        }
                    }
                    val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
                    if (contentLength !in 0..MAX_BODY_BYTES) {
                        writeJson(output, 413, error("payload_too_large"))
                        return
                    }
                    val bodyBytes = ByteArray(contentLength)
                    var read = 0
                    while (read < contentLength) {
                        val count = input.read(bodyBytes, read, contentLength - read)
                        if (count < 0) return
                        read += count
                    }
                    val body = if (read > 0) {
                        JSONObject(String(bodyBytes, StandardCharsets.UTF_8))
                    } else JSONObject()
                    route(method, path, headers, body, output)
                }
            } catch (error: Exception) {
                Log.e("TivuqCompanion", "Client request failed", error)
                runCatching { writeJson(output, 400, error("bad_request")) }
            }
        }
    }

    private fun isLocalClient(address: InetAddress): Boolean {
        if (address.isSiteLocalAddress ||
            address.isLoopbackAddress ||
            address.isLinkLocalAddress
        ) return true
        // Fire OS may expose an IPv4 LAN peer as an IPv6-mapped address.
        // Normalize it before applying the private-network restriction.
        val normalized = address.hostAddress
            ?.substringBefore('%')
            ?.removePrefix("::ffff:")
            ?: return false
        return runCatching {
            val parsed = InetAddress.getByName(normalized)
            parsed.isSiteLocalAddress ||
                parsed.isLoopbackAddress ||
                parsed.isLinkLocalAddress
        }.getOrDefault(false)
    }

    private fun route(
        method: String,
        path: String,
        headers: Map<String, String>,
        body: JSONObject,
        output: BufferedOutputStream,
    ) {
        if (method == "POST" && path == "/v1/pair") {
            return handlePair(body, output)
        }
        if (method == "POST" && path == "/v1/pairing/start") {
            val pairing = beginPairing()
            val now = System.currentTimeMillis()
            if (now - lastPairingPromptAt >= 2_000L) {
                lastPairingPromptAt = now
                mainHandler.post {
                    channel.invokeMethod("pairingCodeRequested", pairing)
                }
            }
            return writeJson(
                output,
                202,
                JSONObject()
                    .put("started", true)
                    .put("expiresAt", pairing["expiresAt"]),
            )
        }
        val client = authenticate(headers["authorization"])
            ?: return writeJson(output, 401, error("pairing_required"))
        touchClient(client.first)
        if (method == "GET" && path == "/v1/status") {
            return writeJson(
                output,
                200,
                JSONObject()
                    .put("ok", true)
                    .put("protocol", 1)
                    .put("deviceId", deviceId),
            )
        }
        if (method == "GET" && path == "/v1/channels") {
            return writeJson(
                output,
                200,
                JSONObject()
                    .put("channels", liveChannelCatalog)
                    .put("count", liveChannelCatalog.length()),
            )
        }
        if (method == "GET" && path == "/v1/content") {
            return writeJson(
                output,
                200,
                JSONObject()
                    .put("contents", contentCatalog)
                    .put("count", contentCatalog.length()),
            )
        }
        if (method == "POST" && path == "/v1/series/episodes") {
            val id = body.optString("id").trim()
            if (id.isEmpty()) {
                return writeJson(output, 400, error("invalid_series"))
            }
            val episodes = requestSeriesEpisodes(id)
                ?: return writeJson(output, 504, error("episodes_timeout"))
            return writeJson(
                output,
                200,
                JSONObject().put("episodes", episodes).put("count", episodes.length()),
            )
        }
        if (method == "GET" && path == "/v1/settings") {
            return writeJson(
                output,
                200,
                JSONObject().put("settings", appSettings),
            )
        }
        if (method == "GET" && path == "/v1/profiles") {
            val profiles = requestProfiles()
                ?: return writeJson(output, 504, error("profiles_timeout"))
            return writeJson(
                output,
                200,
                JSONObject().put("profiles", profiles).put("count", profiles.length()),
            )
        }
        if (method == "POST" && path == "/v1/settings") {
            val updates = sanitizeSettingUpdates(body)
            if (updates.length() == 0) {
                return writeJson(output, 400, error("invalid_settings"))
            }
            mainHandler.post {
                channel.invokeMethod(
                    "settingsUpdateRequested",
                    updates.keys().asSequence().associateWith { updates.get(it) },
                )
            }
            return writeJson(output, 202, JSONObject().put("accepted", true))
        }
        if (method == "POST" && path == "/v1/channels/play") {
            val id = body.optString("id").trim()
            if (id.isEmpty() || !liveChannelIds.contains(id)) {
                return writeJson(output, 404, error("channel_not_found"))
            }
            mainHandler.post {
                channel.invokeMethod("channelPlayRequested", mapOf("id" to id))
            }
            return writeJson(output, 202, JSONObject().put("accepted", true))
        }
        if (method == "POST" && path == "/v1/content/play") {
            val id = body.optString("id").trim()
            if (id.isEmpty()) {
                return writeJson(output, 400, error("invalid_content"))
            }
            mainHandler.post {
                channel.invokeMethod("contentPlayRequested", mapOf("id" to id))
            }
            return writeJson(output, 202, JSONObject().put("accepted", true))
        }
        if (method == "POST" && path == "/v1/remote/command") {
            val command = body.optString("command")
            if (!dispatchRemoteCommand(command)) {
                return writeJson(output, 400, error("unsupported_command"))
            }
            return writeJson(output, 200, JSONObject().put("ok", true))
        }
        if (method == "POST" &&
            (path == "/v1/profiles" || path == "/v1/profiles/update")
        ) {
            val name = body.optString("name").trim().take(80)
            val playlistUrl = body.optString("playlistUrl").trim()
            val profileId = body.optString("profileId").trim()
            val parsedUrl = runCatching { URI(playlistUrl) }.getOrNull()
            if (name.isEmpty() ||
                playlistUrl.length > 8192 ||
                parsedUrl?.host.isNullOrEmpty() ||
                !(parsedUrl?.scheme == "http" || parsedUrl?.scheme == "https")
            ) {
                return writeJson(output, 400, error("invalid_profile"))
            }
            if (path == "/v1/profiles/update") {
                if (profileId.isEmpty()) {
                    return writeJson(output, 400, error("invalid_profile"))
                }
                val profiles = requestProfiles()
                    ?: return writeJson(output, 504, error("profiles_timeout"))
                val exists = (0 until profiles.length()).any { index ->
                    profiles.optJSONObject(index)?.optString("id") == profileId
                }
                if (!exists) {
                    return writeJson(output, 404, error("profile_not_found"))
                }
            }
            val payload = hashMapOf<String, Any>(
                "name" to name,
                "playlistUrl" to playlistUrl,
            )
            if (profileId.isNotEmpty()) payload["profileId"] = profileId
            if (!saveProfile(payload)) {
                return writeJson(output, 500, error("profile_save_failed"))
            }
            return writeJson(output, 200, JSONObject().put("saved", true))
        }
        writeJson(output, 404, error("not_found"))
    }

    private fun requestSeriesEpisodes(id: String): JSONArray? {
        val latch = CountDownLatch(1)
        var response: JSONArray? = null
        mainHandler.post {
            channel.invokeMethod(
                "seriesEpisodesRequested",
                mapOf("id" to id),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val items = result as? List<*> ?: emptyList<Any?>()
                        response = JSONArray(items)
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        latch.countDown()
                    }
                },
            )
        }
        return if (latch.await(20, TimeUnit.SECONDS)) response else null
    }

    private fun requestProfiles(): JSONArray? {
        val latch = CountDownLatch(1)
        var response: JSONArray? = null
        mainHandler.post {
            channel.invokeMethod(
                "profilesRequested",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val items = result as? List<*> ?: emptyList<Any?>()
                        response = JSONArray(items)
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        latch.countDown()
                    }
                },
            )
        }
        return if (latch.await(10, TimeUnit.SECONDS)) response else null
    }

    private fun saveProfile(payload: Map<String, Any>): Boolean {
        val latch = CountDownLatch(1)
        var saved = false
        mainHandler.post {
            channel.invokeMethod(
                "profileReceived",
                payload,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        saved = result == true
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        latch.countDown()
                    }
                },
            )
        }
        return latch.await(30, TimeUnit.SECONDS) && saved
    }

    private fun sanitizeSettingUpdates(body: JSONObject): JSONObject {
        val updates = JSONObject()
        if (body.has("sidebarOpacity")) {
            val value = body.optDouble("sidebarOpacity", Double.NaN)
            if (!value.isNaN() && value in 0.05..1.0) {
                updates.put("sidebarOpacity", value)
            }
        }
        if (body.has("autoHideDuration")) {
            val value = body.optDouble("autoHideDuration", Double.NaN)
            if (value in setOf(0.0, 2.0, 3.0, 5.0, 8.0, 10.0)) {
                updates.put("autoHideDuration", value)
            }
        }
        val quality = body.optString("quality")
        if (quality in setOf("auto", "4k", "1080p", "720p")) {
            updates.put("quality", quality)
        }
        val startup = body.optString("startupScreen")
        if (startup in setOf("live_tv", "movies", "series", "last_screen")) {
            updates.put("startupScreen", startup)
        }
        if (body.has("liveTvRefreshRate")) {
            val refreshRate = body.optInt("liveTvRefreshRate")
            if (refreshRate == 50 || refreshRate == 60) {
                updates.put("liveTvRefreshRate", refreshRate)
            }
        }
        if (body.has("enableTunneling")) {
            updates.put("enableTunneling", body.optBoolean("enableTunneling"))
        }
        if (body.has("autoStartOnBoot")) {
            updates.put("autoStartOnBoot", body.optBoolean("autoStartOnBoot"))
        }
        return updates
    }

    private fun handlePair(body: JSONObject, output: BufferedOutputStream) {
        val expected = pairingCode
        val now = System.currentTimeMillis()
        val supplied = body.optString("code")
        if (expected == null || now > pairingExpiresAt || pairingAttempts >= 6) {
            return writeJson(output, 410, error("pairing_expired"))
        }
        pairingAttempts += 1
        if (!MessageDigest.isEqual(expected.toByteArray(), supplied.toByteArray())) {
            return writeJson(output, 403, error("invalid_pairing_code"))
        }
        val clientName = body.optString("clientName", "TIVUQIPTV Remote").trim().take(80)
        val clientId = randomToken(12)
        val token = randomToken(32)
        val clients = loadClients()
        clients.put(
            clientId,
            JSONObject()
                .put("name", clientName)
                .put("tokenHash", sha256Hex(token.toByteArray()))
                .put("pairedAt", now)
                .put("lastSeenAt", now),
        )
        saveClients(clients)
        pairingCode = null
        pairingExpiresAt = 0L
        mainHandler.post { channel.invokeMethod("pairedDevicesChanged", null) }
        writeJson(
            output,
            200,
            JSONObject().put("token", token).put("clientId", clientId),
        )
    }

    private fun authenticate(value: String?): Pair<String, JSONObject>? {
        if (value == null || !value.startsWith("Bearer ")) return null
        val hash = sha256Hex(value.removePrefix("Bearer ").trim().toByteArray())
        val clients = loadClients()
        for (key in clients.keys()) {
            val client = clients.optJSONObject(key) ?: continue
            if (MessageDigest.isEqual(
                    hash.toByteArray(),
                    client.optString("tokenHash").toByteArray(),
                )
            ) return key to client
        }
        return null
    }

    private fun touchClient(id: String) {
        val clients = loadClients()
        clients.optJSONObject(id)?.put("lastSeenAt", System.currentTimeMillis())
        saveClients(clients)
    }

    private fun dispatchRemoteCommand(command: String): Boolean {
        if (command == "system_volume_up" ||
            command == "system_volume_down" ||
            command == "system_volume_mute"
        ) {
            mainHandler.post { dispatchSystemVolumeCommand(command) }
            return true
        }
        val keyCode = when (command) {
            "up" -> KeyEvent.KEYCODE_DPAD_UP
            "down" -> KeyEvent.KEYCODE_DPAD_DOWN
            "left" -> KeyEvent.KEYCODE_DPAD_LEFT
            "right" -> KeyEvent.KEYCODE_DPAD_RIGHT
            "select" -> KeyEvent.KEYCODE_DPAD_CENTER
            "back" -> KeyEvent.KEYCODE_BACK
            "settings" -> KeyEvent.KEYCODE_MENU
            "play_pause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "rewind" -> KeyEvent.KEYCODE_MEDIA_REWIND
            "forward" -> KeyEvent.KEYCODE_MEDIA_FAST_FORWARD
            else -> return false
        }
        mainHandler.post {
            activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        }
        return true
    }

    private fun dispatchSystemVolumeCommand(command: String) {
        val audioManager =
            activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val direction = when (command) {
            "system_volume_up" -> AudioManager.ADJUST_RAISE
            "system_volume_down" -> AudioManager.ADJUST_LOWER
            "system_volume_mute" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    AudioManager.ADJUST_TOGGLE_MUTE
                } else {
                    @Suppress("DEPRECATION")
                    audioManager.setStreamMute(
                        AudioManager.STREAM_MUSIC,
                        !audioManager.isStreamMute(AudioManager.STREAM_MUSIC),
                    )
                    return
                }
            }
            else -> return
        }
        runCatching {
            // Companion volume must stay on the system route. Mirroring it to
            // a player instance can mute the app in a way the TV remote cannot
            // undo.
            activity.volumeControlStream = AudioManager.STREAM_MUSIC
            audioManager.adjustSuggestedStreamVolume(
                direction,
                AudioManager.STREAM_MUSIC,
                AudioManager.FLAG_SHOW_UI,
            )
        }
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "running" to running.get(),
        "deviceId" to deviceId.ifEmpty { null },
        "port" to serverSocket?.localPort,
        "pairedCount" to loadClients().length(),
    )

    @Synchronized
    private fun beginPairing(): Map<String, Any> {
        val now = System.currentTimeMillis()
        if (pairingCode == null || now >= pairingExpiresAt || pairingAttempts >= 6) {
            pairingCode = (secureRandom.nextInt(900_000) + 100_000).toString()
            pairingExpiresAt = now + 5 * 60_000L
            pairingAttempts = 0
        }
        return mapOf(
            "code" to pairingCode!!,
            "expiresAt" to pairingExpiresAt,
            "deviceId" to deviceId,
            "name" to deviceName,
            "address" to localIpv4Address(),
            "port" to (serverSocket?.localPort ?: 0),
            "certificateSha256" to certificateSha256,
        )
    }

    private fun localIpv4Address(): String {
        return runCatching {
            NetworkInterface.getNetworkInterfaces().toList()
                .asSequence()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList().asSequence() }
                .filterIsInstance<Inet4Address>()
                .firstOrNull { !it.isLoopbackAddress && it.isSiteLocalAddress }
                ?.hostAddress
        }.getOrNull() ?: ""
    }

    private fun localDeviceName(): String {
        val configuredName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            Settings.Global.getString(
                activity.contentResolver,
                Settings.Global.DEVICE_NAME,
            )
        } else null
        return configuredName
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.take(80)
            ?: Build.MODEL.trim().takeIf { it.isNotEmpty() }?.take(80)
            ?: "TIVUQIPTV"
    }

    private fun pairedDeviceMaps(): List<Map<String, Any>> {
        val clients = loadClients()
        return clients.keys().asSequence().mapNotNull { id ->
            clients.optJSONObject(id)?.let {
                mapOf(
                    "id" to id,
                    "name" to it.optString("name", "TIVUQIPTV Remote"),
                    "pairedAt" to it.optLong("pairedAt"),
                    "lastSeenAt" to it.optLong("lastSeenAt"),
                )
            }
        }.toList()
    }

    private fun revokeDevice(id: String): Boolean {
        val clients = loadClients()
        if (!clients.has(id)) return false
        clients.remove(id)
        saveClients(clients)
        mainHandler.post { channel.invokeMethod("pairedDevicesChanged", null) }
        return true
    }

    private fun loadClients(): JSONObject {
        val raw = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(CLIENTS_KEY, "{}") ?: "{}"
        return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
    }

    private fun saveClients(clients: JSONObject) {
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(CLIENTS_KEY, clients.toString()).apply()
    }

    private fun randomToken(bytes: Int): String {
        val data = ByteArray(bytes).also(secureRandom::nextBytes)
        return Base64.encodeToString(
            data,
            Base64.NO_WRAP or Base64.URL_SAFE or Base64.NO_PADDING,
        )
    }

    private fun sha256Hex(data: ByteArray): String = MessageDigest
        .getInstance("SHA-256")
        .digest(data)
        .joinToString("") { "%02x".format(it) }

    private fun readLine(input: BufferedInputStream): String? {
        val bytes = ArrayList<Byte>()
        while (bytes.size < 8192) {
            val value = input.read()
            if (value < 0) {
                return if (bytes.isEmpty()) null else String(bytes.toByteArray())
            }
            if (value == '\n'.code) break
            if (value != '\r'.code) bytes.add(value.toByte())
        }
        return String(bytes.toByteArray(), StandardCharsets.UTF_8)
    }

    private fun writeJson(output: BufferedOutputStream, status: Int, body: JSONObject) {
        val bytes = body.toString().toByteArray(StandardCharsets.UTF_8)
        val label = when (status) {
            200 -> "OK"
            202 -> "Accepted"
            400 -> "Bad Request"
            401 -> "Unauthorized"
            403 -> "Forbidden"
            404 -> "Not Found"
            410 -> "Gone"
            413 -> "Payload Too Large"
            else -> "Error"
        }
        output.write(
            "HTTP/1.1 $status $label\r\n".toByteArray(StandardCharsets.UTF_8),
        )
        output.write("Content-Type: application/json\r\n".toByteArray())
        output.write("Content-Length: ${bytes.size}\r\n".toByteArray())
        output.write("Connection: close\r\n\r\n".toByteArray())
        output.write(bytes)
        output.flush()
    }

    private fun error(code: String) = JSONObject().put("error", code)
}
