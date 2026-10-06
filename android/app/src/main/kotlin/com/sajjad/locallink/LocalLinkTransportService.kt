package com.sajjad.locallink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.AudioFocusRequest
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.net.wifi.WifiManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.FileInputStream
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.RandomAccessFile
import java.util.PriorityQueue
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject
import com.sajjad.locallink.mesh.*

/**
 * Service-owned LocalLink peer transport. The Activity owns Flutter and Wi-Fi Direct
 * discovery channels only; sockets, mesh routing, queues and file transfers live here.
 */
class LocalLinkTransportService : Service() {
    interface EventListener { fun onTransportEvent(type: String, data: Map<String, Any?>) }
    companion object {
        private const val ROUTE_ADVERTISEMENT_PROTOCOL_VERSION = 2
        private const val ROUTE_ADVERTISEMENT_MAX_AGE_MS = 90_000L
        private const val ROUTE_ADVERTISEMENT_INTERVAL_MS = 10_000L
        private const val LAN_BEACON_MAX_SIZE = 2_048
        private const val LAN_BEACON_MAX_AGE_MS = 12_000L
        private const val LAN_BEACON_FUTURE_SKEW_MS = 5_000L
        private const val CHANNEL_ID = "locallink_transport"
        private const val NOTIFICATION_ID = 2201
        private const val PREFS = "locallink_transport_state"
        private const val STATE_BLOB = "encrypted_state"
        private const val STATE_KEY_ALIAS = "locallink_transport_state_v1"
        private const val ACTION_CONFIGURE = "configure"
        private const val ACTION_UPDATE_KEYS = "update_keys"
        private const val ACTION_CONNECTION = "connection"
        private const val ACTION_RESUME = "resume"
        private const val TRANSPORT_AUTH_VERSION = 2
        private const val CALL_SAMPLE_RATE = 16_000
        private const val CALL_FRAME_MS = 20
        private const val CALL_FRAME_BYTES = CALL_SAMPLE_RATE * CALL_FRAME_MS / 1000 * 2
        private const val CALL_JITTER_BUFFER_MS = 60L
        private const val CALL_MAX_JITTER_FRAMES = 12
        @Volatile private var instance: LocalLinkTransportService? = null
        @Volatile private var listener: EventListener? = null
        @Volatile private var running = false
        fun isRunning() = running
        fun setEventListener(value: EventListener?) { listener=value }
        fun start(context: Context) { startCommand(context,null) }
        fun stop(context: Context) { instance?.stopTransportExplicit(); context.stopService(Intent(context,LocalLinkTransportService::class.java)) }
        fun configure(context:Context,deviceId:String,connected:Boolean,groupOwner:Boolean,address:String?,peerKeys:Map<String,String>){
            val k=JSONObject();peerKeys.forEach{(a,b)->k.put(a,b)}
            startCommand(context,Intent(context,LocalLinkTransportService::class.java).apply{action=ACTION_CONFIGURE;putExtra("device_id",deviceId);putExtra("connected",connected);putExtra("group_owner",groupOwner);putExtra("group_owner_address",address);putExtra("peer_keys",k.toString())})
        }
        fun updatePeerKeys(context:Context,values:Map<String,String>){instance?.updatePeerKeysInternal(values)?:startCommand(context,Intent(context,LocalLinkTransportService::class.java).apply{action=ACTION_UPDATE_KEYS;val k=JSONObject();values.forEach{(a,b)->k.put(a,b)};putExtra("peer_keys",k.toString())})}
        fun updateConnection(context:Context,connected:Boolean,owner:Boolean,address:String?){instance?.startOrStopTransportForConnection(connected,owner,address)?:startCommand(context,Intent(context,LocalLinkTransportService::class.java).apply{action=ACTION_CONNECTION;putExtra("connected",connected);putExtra("group_owner",owner);putExtra("group_owner_address",address)})}
        fun resume(context:Context,connected:Boolean,owner:Boolean,address:String?){instance?.resumeTransport(connected,owner,address)?:startCommand(context,Intent(context,LocalLinkTransportService::class.java).apply{action=ACTION_RESUME;putExtra("connected",connected);putExtra("group_owner",owner);putExtra("group_owner_address",address)})}
        fun send(recipientId:String,payload:Map<String,Any?>)=instance?.sendTransportInternal(recipientId,payload)?:false
        fun startCallMedia(callId:String, peerId:String, codec:String?) = instance?.startCallMediaInternal(callId, peerId, codec)
            ?: throw IllegalStateException("transport service is not running")
        fun stopCallMedia(callId:String) { instance?.stopCallMediaInternal(callId) }
        fun setCallMediaMuted(callId:String, muted:Boolean) { instance?.setCallMediaMutedInternal(callId, muted) }
        fun callMediaStats(callId:String): Map<String,Any?> = instance?.callMediaStatsInternal(callId) ?: emptyMap()
        fun currentDeviceId(): String? = instance?.transportDeviceId
        fun configureCallVideoSurfaces(preview: android.view.Surface, remote: android.view.Surface) { instance?.configureCallVideoSurfacesInternal(preview, remote) }
        fun clearCallVideoSurfaces() { instance?.clearCallVideoSurfacesInternal() }
        fun startCallVideo(callId:String, peerId:String) { instance?.startCallVideoInternal(callId, peerId) ?: throw IllegalStateException("transport service is not running") }
        fun stopCallVideo(callId:String) { instance?.stopCallVideoInternal(callId) }
        fun setCallVideoEnabled(callId:String, enabled:Boolean) { instance?.setCallVideoEnabledInternal(callId, enabled) }
        fun switchCallCamera(callId:String) { instance?.switchCallCameraInternal(callId) }
        fun broadcast(payload:Map<String,Any?>)=instance?.broadcastTransportInternal(payload)?:false
        fun sendFile(recipientId:String,path:String,fileId:String,messageId:String,fileName:String,contentType:String,cb:(Boolean,String?)->Unit){instance?.sendFileTransportInternal(recipientId,path,fileId,messageId,fileName,contentType,cb)?:cb(false,"transport service is not running")}
        fun cancelFile(fileId:String){instance?.cancelFileTransportInternal(fileId)}
        fun topology(): Map<String, Any?> = instance?.meshTopologySnapshot() ?: emptyMap()
        fun flushQueue(){instance?.flushMeshQueue()}
        fun clearStorage(){instance?.clearTransportStorage()}
        private fun startCommand(context:Context,intent:Intent?){val i=intent?:Intent(context,LocalLinkTransportService::class.java);if(android.os.Build.VERSION.SDK_INT>=26)context.startForegroundService(i)else context.startService(i)}
    }

    private val transportPort = MeshTransportPolicy.WIFI_DIRECT_PORT
    private val lanTransportPort = MeshTransportPolicy.LAN_PORT
    private val lanDiscoveryPort = MeshTransportPolicy.LAN_DISCOVERY_PORT
    private val directChunkSize = DirectFileTransferPolicy.CHUNK_SIZE
    private val maxDirectFileSize = DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE
    private var transportDeviceId: String? = null
    private var transportServer: ServerSocket? = null
    private var lanServer: ServerSocket? = null
    private var lanDiscoverySocket: DatagramSocket? = null
    private var lanDiscoveryThread: Thread? = null
    private var lanMulticastLock: WifiManager.MulticastLock? = null
    private var transportRunning = false
    private var transportGroupOwner = false
    private var transportGroupOwnerAddress: String? = null
    /** Preferred logical link per peer. Physical links are retained separately so a LAN
     * failure can fall back to a still-live Wi-Fi Direct link without forcing a new pairing. */
    private val transportPeers = ConcurrentHashMap<String, PeerConnection>()
    private val peerLinks = ConcurrentHashMap<String, ConcurrentHashMap<String, PeerConnection>>()
    private val ownerConnectInFlight = AtomicBoolean(false)
    private val lastOwnerConnectAt = AtomicLong(0)
    private val transportBytesSent = AtomicLong(0)
    private val transportBytesReceived = AtomicLong(0)
    private val transportPacketsSent = AtomicLong(0)
    private val transportPacketsReceived = AtomicLong(0)
    private val transportReconnectAttempts = AtomicLong(0)
    private val transportHeartbeatTimeouts = AtomicLong(0)
    private val lanConnectInFlight = ConcurrentHashMap<String, AtomicBoolean>()
    private val lanEndpoints = ConcurrentHashMap<String, LanEndpoint>()
    private val lastLanBeaconAt = ConcurrentHashMap<String, Long>()
    private val routeAdvertisementLastSentAt = AtomicLong(0L)
    private val routeAdvertisementSequence = AtomicLong(0L)
    private val routeAdvertisementSessionId = UUID.randomUUID().toString()
    private val routeAdvertisementPolicy = com.sajjad.locallink.mesh.MeshRouteAdvertisementPolicy()
    private val routeStabilityPolicy = com.sajjad.locallink.mesh.MeshRouteStabilityPolicy()
    private val transportSendFailures = AtomicLong(0)
    private val peerKeys = ConcurrentHashMap<String, String>()
    private val callMediaLock = Any()
    @Volatile private var callMedia: CallMediaSession? = null
    @Volatile private var callVideo: CallVideoSession? = null
    @Volatile private var callVideoPreviewSurface: android.view.Surface? = null
    @Volatile private var callVideoRemoteSurface: android.view.Surface? = null
    // Application-level call replay cache. Mesh packet IDs provide transport-level
    // duplicate protection; sequence numbers provide protection when the same valid
    // media frame is re-wrapped in a new mesh packet.
    private val callMediaRecent = ConcurrentHashMap<String, Long>()
    private val callMediaMaxRecent = 512
    private val incomingFiles = ConcurrentHashMap<String, IncomingFileTransfer>()
    private val outgoingTransfers = ConcurrentHashMap<String, OutgoingFileTransfer>()
    private val outgoingReservations = ConcurrentHashMap<String, Long>()
    private val cancelledDirectTransfers = ConcurrentHashMap.newKeySet<String>()
    private val cancelledIncomingTransfers = ConcurrentHashMap<String, Long>()
    private val outgoingSendInFlight = ConcurrentHashMap.newKeySet<String>()
    private val outgoingRetryCounts = ConcurrentHashMap<String, Int>()
    private val random = SecureRandom()
    private val meshQueueDir by lazy { File(filesDir,"locallink_mesh_queue").apply{mkdirs()} }
    private val seenMeshDir by lazy { File(filesDir,"locallink_seen_mesh").apply{mkdirs()} }
    private val seenMeshPackets = MeshSeenPacketTracker(
        maxEntries = MeshLimits.MAX_SEEN_PACKETS,
        retentionMs = MeshLimits.SEEN_RETENTION_MS,
        onEvicted = ::deleteSeenMeshPacketRecord,
    )
    private val seenEphemeralMeshPackets = MeshSeenPacketTracker(
        maxEntries = MeshLimits.MAX_EPHEMERAL_SEEN_PACKETS,
        retentionMs = MeshLimits.EPHEMERAL_SEEN_RETENTION_MS,
    )
    private val meshDuplicatePacketsDropped = AtomicLong(0)
    private val meshFlushLock=Any()
    private val meshQueueSequence=AtomicLong(System.currentTimeMillis())
    private val meshMaxQueueBytes=200L*1024L*1024L
    private val meshMaxQueuePackets=4096
    private val meshPacketTtl=MeshLimits.MAX_TTL
    private var meshMaintenanceThread:Thread?=null
    private val routeTable = MeshRouteTable { transportDeviceId }
    private val meshPeers = MeshPeerRegistry()
    private val routeRecovery = MeshRouteRecoveryTracker(retentionMs = 90_000L)
    private val directRouteVersions = ConcurrentHashMap<String, AtomicLong>()
    private val meshMaxPacketAgeMs = MeshLimits.MAX_PACKET_AGE_MS
    private val meshMaxFutureSkewMs = MeshLimits.MAX_FUTURE_SKEW_MS
    private val meshTransport = object : MeshTransport {
        override val name: String = "peer_tcp"
        override fun isPeerAvailable(nodeId: String): Boolean = activePeerConnection(nodeId) != null
        override fun send(peerNodeId: String, packet: MeshPacket): Boolean = sendPacketToPeerId(peerNodeId, packet)
        override fun disconnect(peerNodeId: String) { try { activePeerConnection(peerNodeId)?.socket?.close() } catch (_: Exception) {} }
        override fun onRouteFailure(destinationNodeId: String, failedNextHopNodeId: String) {
            // Only invalidate the failed hop here. A replacement route is considered
            // recovered after the same live packet is successfully forwarded.
            transportEvent("route_invalidated", mapOf("destination_id" to destinationNodeId, "failed_next_hop" to failedNextHopNodeId, "reason" to "send_failure"))
            broadcastRouteAdvertisement()
            transportEvent("topology", meshTopologySnapshot())
        }
    }
    private val meshRouter by lazy {
        MeshRouter({ transportDeviceId }, routeTable, meshPeers, meshTransport, ::enqueueMeshPacket, meshPacketTtl)
    }
    private val startedAt=System.currentTimeMillis()

    override fun onCreate(){
        super.onCreate();instance=this;createNotificationChannel()
        if(android.os.Build.VERSION.SDK_INT>=29)startForeground(NOTIFICATION_ID,buildNotification(),ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)else startForeground(NOTIFICATION_ID,buildNotification())
        running=true;loadPersistedState();restoreDurableState()
        if(transportRunning){startMeshMaintenance();startLanTransport();transportEvent("state",mapOf("connected" to transportPeers.isNotEmpty(),"transport_active" to true,"group_owner" to transportGroupOwner));if(transportGroupOwner)ensureTransportServer()}
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int{
        when(intent?.action){
            ACTION_CONFIGURE->{val keys=parsePeerKeys(intent.getStringExtra("peer_keys"));configureTransport(intent.getStringExtra("device_id") ?: "",intent.getBooleanExtra("connected",false),intent.getBooleanExtra("group_owner",false),intent.getStringExtra("group_owner_address"),keys)}
            ACTION_UPDATE_KEYS->updatePeerKeysInternal(parsePeerKeys(intent.getStringExtra("peer_keys")))
            ACTION_CONNECTION->if(transportRunning)startOrStopTransportForConnection(intent.getBooleanExtra("connected",false),intent.getBooleanExtra("group_owner",false),intent.getStringExtra("group_owner_address"))
            ACTION_RESUME->resumeTransport(intent.getBooleanExtra("connected",false),intent.getBooleanExtra("group_owner",false),intent.getStringExtra("group_owner_address"))
        };return START_STICKY
    }
    private fun parsePeerKeys(raw:String?):Map<String,String>{val out=mutableMapOf<String,String>();if(raw.isNullOrBlank())return out;try{val j=JSONObject(raw);val it=j.keys();while(it.hasNext()){val k=it.next();val v=j.optString(k);if(validTransportId(k)&&v.isNotBlank())out[k]=v}}catch(_:Exception){};return out}
    override fun onBind(intent:Intent?):IBinder?=null
    private fun createNotificationChannel(){if(android.os.Build.VERSION.SDK_INT<26)return;getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL_ID,"LocalLink peer transport",NotificationManager.IMPORTANCE_LOW).apply{description="Keeps LocalLink peer communication available while the app is in the background";setShowBadge(false)})}
    private fun buildNotification():Notification{val li=packageManager.getLaunchIntentForPackage(packageName);val pi=li?.let{PendingIntent.getActivity(this,2202,it,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)};val b=if(android.os.Build.VERSION.SDK_INT>=26)Notification.Builder(this,CHANNEL_ID)else Notification.Builder(this);return b.setSmallIcon(android.R.drawable.stat_notify_sync).setContentTitle("LocalLink peer network active").setContentText("Offline peer communication is available").setOngoing(true).setCategory(Notification.CATEGORY_SERVICE).setContentIntent(pi).setPriority(Notification.PRIORITY_LOW).build()}

    private fun configureTransport(deviceId:String,connected:Boolean,owner:Boolean,address:String?,keys:Map<String,String>){if(deviceId.isBlank())return;transportDeviceId=deviceId.trim();peerKeys.clear();peerKeys.putAll(keys.filterKeys{validTransportId(it)});transportRunning=true;persistState();startMeshMaintenance();startLanTransport();transportEvent("state",mapOf("connected" to connected,"transport_active" to true,"group_owner" to owner));startOrStopTransportForConnection(connected,owner,address)}
    private fun updatePeerKeysInternal(values:Map<String,String>){peerKeys.clear();values.forEach{(k,v)->if(validTransportId(k)&&v.isNotBlank())peerKeys[k]=v.trim()};persistState()}
    private fun resumeTransport(connected:Boolean,owner:Boolean,address:String?){if(transportDeviceId.isNullOrBlank())return;transportRunning=true;persistState();startMeshMaintenance();startLanTransport();transportEvent("state",mapOf("connected" to connected,"transport_active" to true,"group_owner" to owner));startOrStopTransportForConnection(connected,owner,address)}
    private fun sendTransportInternal(target:String,map:Map<String,Any?>):Boolean{if(!transportRunning||!validTransportId(target))return false;val p=JSONObject();map.forEach{(k,v)->if(k!=null&&v!=null)p.put(k,v)};return sendRoutedPayload(target,p)}
    private fun broadcastTransportInternal(map:Map<String,Any?>):Boolean{val self=transportDeviceId?:return false;var ok=false;for((id,peer) in transportPeers){val p=JSONObject();map.forEach{(k,v)->if(k!=null&&v!=null)p.put(k,v)};p.put("sender_id",self).put("recipient_id",id);if(sendToPeer(peer,p))ok=true};return ok||transportPeers.isEmpty()}
    private fun sendFileTransportInternal(target:String,path:String,fileId:String,messageId:String,fileName:String,contentType:String,cb:(Boolean,String?)->Unit){
        if(!transportRunning){cb(false,"transport is not configured");return}
        if(!validTransportId(target)||!validFileTransferId(fileId)||!validFileTransferId(messageId)){cb(false,"invalid file transfer identifier");return}
        if(!validContentType(contentType)){cb(false,"invalid content type");return}
        val f=File(path)
        if(!f.isFile){cb(false,"selected file is no longer available");return}
        if(f.length()>maxDirectFileSize){cb(false,"direct file size exceeds 50 MiB");return}
        synchronized(outgoingTransfers){
            val existing=outgoingTransfers[fileId]
            if(existing==null){
                if(outgoingReservations.containsKey(fileId)){cb(false,"file transfer is already being prepared");return}
                if(outgoingTransfers.size + outgoingReservations.size>=DirectFileTransferPolicy.MAX_ACTIVE_OUTGOING_TRANSFERS){cb(false,"too many active outgoing file transfers");return}
                val activeBytes=DirectFileTransferPolicy.activeBytes(outgoingTransfers.values.map{it.size}) + DirectFileTransferPolicy.activeBytes(outgoingReservations.values)
                if(activeBytes > DirectFileTransferPolicy.MAX_ACTIVE_TRANSFER_BYTES-f.length()){cb(false,"active outgoing file byte budget exceeded");return}
                outgoingReservations[fileId]=f.length()
            }
        }
        Thread{try{val t=prepareOutgoingTransfer(target,f,fileId,messageId,fileName,contentType);persistOutgoingTransfer(t);sendMissingChunks(t,true);transportEvent("file_queued",mapOf("transfer_id" to t.transferId,"message_id" to messageId,"size" to t.size,"total_chunks" to t.totalChunks));cb(true,null)}catch(e:Exception){cb(false,e.message)}finally{outgoingReservations.remove(fileId)}}.start()
    }

    private fun startOrStopTransportForConnection(connected: Boolean, groupOwner: Boolean, groupOwnerAddress: String?) {
        if (!transportRunning) return
        transportGroupOwner = groupOwner
        transportGroupOwnerAddress = groupOwnerAddress
        persistState()
        if (!connected) {
            stopWifiDirectSockets()
            transportEvent("state", mapOf("connected" to false, "transport_active" to transportRunning, "group_owner" to groupOwner))
            return
        }
        if (groupOwner) {
            closeWifiDirectClientLinks()
            ensureTransportServer()
        } else if (!groupOwnerAddress.isNullOrEmpty()) {
            if (transportServer != null) {
                try { transportServer?.close() } catch (_: Exception) {}
                transportServer = null
            }
            connectTransportToOwner(groupOwnerAddress)
        }
    }

    private fun startLanTransport() {
        if (!transportRunning) return
        if (!acquireLanMulticastLock()) return
        ensureLanServer()
        if (lanDiscoveryThread?.isAlive != true) {
            lanDiscoveryThread = Thread { runLanDiscovery() }.also { it.start() }
        }
    }

    private fun acquireLanMulticastLock(): Boolean {
        if (lanMulticastLock?.isHeld == true) return true
        return try {
            val wifiManager = getSystemService(Context.WIFI_SERVICE) as WifiManager
            lanMulticastLock = wifiManager.createMulticastLock("LocalLinkLanDiscovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            true
        } catch (error: SecurityException) {
            transportEvent(
                "error",
                mapOf(
                    "transport" to MeshTransportPolicy.LAN,
                    "operation" to "multicast_lock",
                    "error" to (error.message ?: "multicast permission denied"),
                ),
            )
            false
        }
    }

    private fun releaseLanMulticastLock() {
        val lock = lanMulticastLock ?: return
        if (lock.isHeld) lock.release()
        lanMulticastLock = null
    }

    private fun ensureLanServer() {
        if (lanServer != null) return
        try {
            val server = ServerSocket(lanTransportPort)
            server.reuseAddress = true
            lanServer = server
            Thread {
                while (transportRunning && lanServer == server) {
                    try {
                        val socket = server.accept()
                        configureSocket(socket)
                        Thread { handleIncomingTransportSafe(socket, MeshTransportPolicy.LAN) }.start()
                    } catch (_: Exception) {
                        if (!transportRunning) break
                    }
                }
            }.start()
        } catch (e: Exception) {
            transportEvent("error", mapOf("error" to (e.message ?: "failed to start LAN peer server"), "transport" to MeshTransportPolicy.LAN, "port" to lanTransportPort))
        }
    }

    private fun runLanDiscovery() {
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket(lanDiscoveryPort).apply {
                reuseAddress = true
                broadcast = true
                soTimeout = 2000
            }
            lanDiscoverySocket = socket
            val receiveBuffer = ByteArray(4096)
            var lastBroadcast = 0L
            while (transportRunning && lanDiscoverySocket == socket) {
                val now = System.currentTimeMillis()
                if (now - lastBroadcast >= MeshTransportPolicy.LAN_BEACON_INTERVAL_MS) {
                    broadcastLanBeacon(socket)
                    lastBroadcast = now
                }
                try {
                    val datagram = DatagramPacket(receiveBuffer, receiveBuffer.size)
                    socket.receive(datagram)
                    handleLanBeacon(String(datagram.data, datagram.offset, datagram.length, Charsets.UTF_8), datagram.address)
                } catch (_: java.net.SocketTimeoutException) {
                    // Continue periodic discovery broadcast.
                }
            }
        } catch (_: Exception) {
        } finally {
            try { socket?.close() } catch (_: Exception) {}
            if (lanDiscoverySocket === socket) lanDiscoverySocket = null
        }
    }

    private fun broadcastLanBeacon(socket: DatagramSocket) {
        val self = transportDeviceId ?: return
        val packet = JSONObject()
            .put("type", "lan_peer_discovery")
            .put("mesh_transport_version", MeshTransportPolicy.DISCOVERY_PROTOCOL_VERSION)
            .put("node_id", self)
            .put("port", lanTransportPort)
            .put("sent_at", System.currentTimeMillis())
        val bytes = packet.toString().toByteArray(Charsets.UTF_8)
        val addresses = lanBroadcastAddresses()
        try {
            addresses.forEach { destination ->
                socket.send(DatagramPacket(bytes, bytes.size, destination, lanDiscoveryPort))
            }
        } catch (e: Exception) {
            transportEvent("error", mapOf(
                "transport" to MeshTransportPolicy.LAN,
                "operation" to "discovery_broadcast",
                "error" to (e.message ?: "LAN discovery broadcast failed"),
            ))
        }
    }

    private fun lanBroadcastAddresses(): List<InetAddress> {
        val addresses = linkedMapOf<String, InetAddress>()
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                if (!networkInterface.isUp || networkInterface.isLoopback) continue
                networkInterface.interfaceAddresses.forEach { interfaceAddress ->
                    val broadcast = interfaceAddress.broadcast ?: return@forEach
                    if (broadcast is InetAddress && broadcast.address.size == 4) {
                        addresses[broadcast.hostAddress ?: broadcast.toString()] = broadcast
                    }
                }
            }
        } catch (_: Exception) {}
        if (addresses.isEmpty()) {
            try {
                val fallback = InetAddress.getByName("255.255.255.255")
                addresses[fallback.hostAddress ?: "255.255.255.255"] = fallback
            } catch (_: Exception) {}
        }
        return addresses.values.toList()
    }

    private fun handleLanBeacon(raw: String, address: InetAddress) {
        try {
            if (raw.toByteArray(Charsets.UTF_8).size > LAN_BEACON_MAX_SIZE) return
            if (address.address.size != 4 || address.isAnyLocalAddress || address.isLoopbackAddress || address.isMulticastAddress) return
            val beacon = JSONObject(raw)
            if (beacon.optString("type") != "lan_peer_discovery") return
            val version = beacon.optInt("mesh_transport_version", -1)
            if (version != MeshTransportPolicy.DISCOVERY_PROTOCOL_VERSION) return
            val self = transportDeviceId ?: return
            val nodeId = beacon.optString("node_id").trim()
            val port = beacon.optInt("port", lanTransportPort)
            val sentAt = beacon.optLong("sent_at", 0L)
            if (!validTransportId(nodeId) || nodeId == self || !MeshTransportPolicy.isValidPort(port)) return
            val now = System.currentTimeMillis()
            if (sentAt <= 0L || sentAt < now - LAN_BEACON_MAX_AGE_MS || sentAt > now + LAN_BEACON_FUTURE_SKEW_MS) return
            val host = address.hostAddress?.trim().orEmpty()
            if (host.isBlank()) return
            val previousBeacon = lastLanBeaconAt.put(nodeId, now)
            if (previousBeacon != null && now - previousBeacon < 250L) return
            lanEndpoints[nodeId] = LanEndpoint(host = host, port = port, lastSeenAt = now)
            val active = activePeerConnection(nodeId)
            if (active == null) meshPeers.discovered(nodeId, MeshTransportPolicy.LAN, now)
            transportEvent("peer_discovered", mapOf(
                "peer_id" to nodeId,
                "node_id" to nodeId,
                "transport" to MeshTransportPolicy.LAN,
                "address" to host,
                "port" to port,
                "last_seen_at" to now,
            ))
            if (active != null) return
            if (self.compareTo(nodeId) < 0 && peerKeys.containsKey(nodeId)) {
                connectLanPeer(nodeId, host, port)
            }
        } catch (_: Exception) {}
    }

    private fun connectLanPeer(nodeId: String, host: String, port: Int = lanTransportPort) {
        val flag = lanConnectInFlight.computeIfAbsent(nodeId) { AtomicBoolean(false) }
        if (!flag.compareAndSet(false, true)) return
        meshPeers.connecting(nodeId, MeshTransportPolicy.LAN)
        transportReconnectAttempts.incrementAndGet()
        Thread {
            var socket: Socket? = null
            try {
                socket = Socket()
                if (!MeshTransportPolicy.isValidPort(port)) throw IllegalArgumentException("invalid LAN peer port")
                socket.connect(InetSocketAddress(host, port), MeshTransportPolicy.SOCKET_CONNECT_TIMEOUT_MS)
                configureSocket(socket)
                val connection = authenticateClient(socket, host, MeshTransportPolicy.LAN, nodeId) ?: run { socket?.close(); return@Thread }
                if (registerPeer(connection)) {
                    Thread { readTransportLoop(connection) }.start()
                }
            } catch (e: Exception) {
                try { socket?.close() } catch (_: Exception) {}
                meshPeers.failed(nodeId, MeshTransportPolicy.LAN)
                transportEvent("transport_connect_failed", mapOf(
                    "transport" to MeshTransportPolicy.LAN,
                    "peer_id" to nodeId,
                    "address" to host,
                    "port" to port,
                    "error" to (e.message ?: "LAN peer connection failed"),
                ))
            } finally {
                flag.set(false)
            }
        }.start()
    }

    private fun ensureTransportServer() {
        if (transportServer != null) return
        try {
            val server = ServerSocket(transportPort)
            server.reuseAddress = true
            transportServer = server
            transportEvent("state", mapOf("connected" to true, "transport_active" to transportRunning, "group_owner" to true))
        Thread { flushMeshQueue() }.start()
            Thread {
                while (transportRunning && transportServer == server) {
                    try {
                        val socket = server.accept()
                        configureSocket(socket)
                        Thread { handleIncomingTransportSafe(socket, MeshTransportPolicy.WIFI_DIRECT) }.start()
                    } catch (_: Exception) {
                        if (!transportRunning) break
                    }
                }
            }.start()
        } catch (e: Exception) {
            transportEvent("error", mapOf("error" to (e.message ?: "failed to start Wi-Fi Direct peer server"), "transport" to MeshTransportPolicy.WIFI_DIRECT, "port" to transportPort))
        }
    }

    private fun connectTransportToOwner(address: String) {
        val normalized = address.trim()
        if (normalized.isEmpty()) return
        if (allPhysicalPeerLinks().any { it.ownerAddress == normalized && it.socket.isConnected && !it.socket.isClosed }) return
        val now = System.currentTimeMillis()
        if (now - lastOwnerConnectAt.get() < 2500L) return
        if (!ownerConnectInFlight.compareAndSet(false, true)) return
        transportGroupOwnerAddress = normalized
        lastOwnerConnectAt.set(now)
        transportReconnectAttempts.incrementAndGet()
        Thread {
            var socket: Socket? = null
            try {
                socket = Socket()
                if (!MeshTransportPolicy.isValidPort(transportPort)) throw IllegalStateException("invalid Wi-Fi Direct peer port")
                socket.connect(InetSocketAddress(normalized, transportPort), MeshTransportPolicy.SOCKET_CONNECT_TIMEOUT_MS)
                configureSocket(socket)
                val connection = authenticateClient(socket, normalized, MeshTransportPolicy.WIFI_DIRECT) ?: run { socket?.close(); return@Thread }
                if (registerPeer(connection)) {
                    Thread { readTransportLoop(connection) }.start()
                }
            } catch (e: Exception) {
                try { socket?.close() } catch (_: Exception) {}
                transportEvent("transport_connect_failed", mapOf(
                    "transport" to MeshTransportPolicy.WIFI_DIRECT,
                    "address" to normalized,
                    "port" to transportPort,
                    "error" to (e.message ?: "Wi-Fi Direct peer connection failed"),
                    "retry_in_ms" to 5000,
                ))
            } finally {
                ownerConnectInFlight.set(false)
            }
        }.start()
    }

    private fun configureSocket(socket: Socket) {
        socket.tcpNoDelay = true
        socket.keepAlive = true
        socket.soTimeout = 15000
    }

    private fun authenticateClient(socket: Socket, ownerAddress: String, transportName: String = MeshTransportPolicy.WIFI_DIRECT, expectedPeerId: String? = null): PeerConnection? {
        val id = transportDeviceId ?: return null
        val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
        val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
        writer.write(JSONObject().put("type", "hello")
            .put("device_id", id)
            .put("node_id", id)
            .put("transport_auth_version", TRANSPORT_AUTH_VERSION)
            .toString())
        writer.newLine()
        writer.flush()
        val challenge = reader.readLine()?.let { JSONObject(it) } ?: return null
        if (challenge.optString("type") != "challenge") return null
        if (challenge.optInt("transport_auth_version", -1) != TRANSPORT_AUTH_VERSION) return null
        val peerId = challenge.optString("peer_id").ifBlank { challenge.optString("node_id") }
        val nonce = challenge.optString("nonce")
        if (expectedPeerId != null && peerId != expectedPeerId) return null
        val key = peerKeys[peerId] ?: return null
        writer.write(JSONObject().put("type", "auth")
            .put("device_id", id)
            .put("node_id", id)
            .put("transport_auth_version", TRANSPORT_AUTH_VERSION)
            .put("proof", hmac(key, "$TRANSPORT_AUTH_VERSION|$nonce|$id|$peerId"))
            .toString())
        writer.newLine()
        writer.flush()
        val auth = reader.readLine()?.let { JSONObject(it) } ?: return null
        if (auth.optString("type") != "auth_ok" || auth.optInt("transport_auth_version", -1) != TRANSPORT_AUTH_VERSION) return null
        socket.soTimeout = 0
        return PeerConnection(peerId, socket, if (transportName == MeshTransportPolicy.WIFI_DIRECT) null else ownerAddress, reader, writer, transportName, socket.inetAddress?.hostAddress)
    }

    private fun acceptHandshake(socket: Socket, transportName: String = MeshTransportPolicy.WIFI_DIRECT): PeerConnection? {
        if (!MeshTransportPolicy.isSupportedTransport(transportName)) return null
        val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
        val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
        val hello = reader.readLine()?.let { JSONObject(it) } ?: return null
        if (hello.optString("type") != "hello") return null
        if (hello.optInt("transport_auth_version", -1) != TRANSPORT_AUTH_VERSION) return null
        val peer = hello.optString("node_id").ifBlank { hello.optString("device_id") }
        val self = transportDeviceId ?: return null
        if (peer.isBlank() || peer == self) return null
        val key = peerKeys[peer] ?: return null
        val nonce = ByteArray(24).also(random::nextBytes)
        val nonceText = Base64.encodeToString(nonce, Base64.NO_WRAP)
        writer.write(JSONObject().put("type", "challenge")
            .put("peer_id", self)
            .put("node_id", self)
            .put("transport_auth_version", TRANSPORT_AUTH_VERSION)
            .put("nonce", nonceText)
            .toString())
        writer.newLine()
        writer.flush()
        val auth = reader.readLine()?.let { JSONObject(it) } ?: return null
        if (auth.optString("node_id").ifBlank { auth.optString("device_id") } != peer ||
            auth.optInt("transport_auth_version", -1) != TRANSPORT_AUTH_VERSION ||
            auth.optString("proof") != hmac(key, "$TRANSPORT_AUTH_VERSION|$nonceText|$peer|$self")) return null
        writer.write(JSONObject().put("type", "auth_ok").put("transport_auth_version", TRANSPORT_AUTH_VERSION).toString())
        writer.newLine()
        writer.flush()
        socket.soTimeout = 0
        return PeerConnection(peer, socket, if (transportName == MeshTransportPolicy.WIFI_DIRECT) null else socket.inetAddress?.hostAddress, reader, writer, transportName, socket.inetAddress?.hostAddress)
    }

    private fun handleIncomingTransportSafe(socket: Socket, transportName: String = MeshTransportPolicy.WIFI_DIRECT) {
        try {
            val connection = acceptHandshake(socket, transportName) ?: run { socket.close(); return }
            if (registerPeer(connection)) {
                readTransportLoop(connection)
            }
        } catch (_: Exception) {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun registerPeer(connection:PeerConnection): Boolean {
        if (!MeshTransportPolicy.isSupportedTransport(connection.transportName)) {
            try { connection.socket.close() } catch (_: Exception) {}
            transportEvent("peer_link_rejected", mapOf(
                "peer_id" to connection.peerId,
                "transport" to connection.transportName,
                "reason" to "unsupported_transport",
            ))
            return false
        }
        val links = peerLinks.computeIfAbsent(connection.peerId) { ConcurrentHashMap() }
        val existingSameTransport = links.put(connection.transportName, connection)
        if (existingSameTransport != null && existingSameTransport !== connection) {
            try { existingSameTransport.socket.close() } catch (_: Exception) {}
        }
        val activeBefore = transportPeers[connection.peerId]
        val active = recomputeActivePeer(connection.peerId)
        if (active == null) {
            links.remove(connection.transportName, connection)
            if (links.isEmpty()) peerLinks.remove(connection.peerId, links)
            try { connection.socket.close() } catch (_: Exception) {}
            return false
        }
        val now=System.currentTimeMillis()
        meshPeers.connected(connection.peerId, active.transportName, now)
        meshPeers.available(connection.peerId, active.transportName, now)
        val self = transportDeviceId ?: ""
        val directVersion = directRouteVersions.computeIfAbsent(connection.peerId) { AtomicLong(now) }.incrementAndGet()
        val previousDirect = routeTable[connection.peerId]
        routeTable.upsert(connection.peerId, MeshRoute(destinationNodeId = connection.peerId, nextHopNodeId = connection.peerId, hopCount = 1, expiresAt = now + 60_000L, lastSeenAt = now, routeVersion = directVersion, path = listOf(self, connection.peerId)))
        val directRecovery = routeRecovery.markRecovered(connection.peerId)
        transportEvent("peer_connected",mapOf(
            "peer_id" to connection.peerId,
            "transport" to connection.transportName,
            "active_transport" to active.transportName,
            "address" to connection.remoteAddress,
            "physical_links" to links.keys.toList().sorted(),
        ))
        if (activeBefore?.transportName != active.transportName && activeBefore != null) {
            transportEvent("peer_transport_selected", mapOf(
                "peer_id" to connection.peerId,
                "previous_transport" to activeBefore.transportName,
                "transport" to active.transportName,
                "reason" to "transport_preference",
            ))
        }
        if (directRecovery != null || previousDirect == null) {
            transportEvent("route_recovered", mapOf(
                "destination_id" to connection.peerId,
                "previous_next_hop" to directRecovery?.failedNextHopNodeId,
                "next_hop_id" to connection.peerId,
                "hop_count" to 1,
                "reason" to if (directRecovery != null) "peer_reconnected" else "direct_peer_connected",
            ))
        }
        transportEvent("topology",meshTopologySnapshot())
        Thread{flushMeshQueue()}.start()
        return true
    }

    private fun closeWifiDirectClientLinks() {
        val affected = mutableSetOf<String>()
        for ((peerId, links) in peerLinks) {
            val connection = links[MeshTransportPolicy.WIFI_DIRECT] ?: continue
            if (connection.ownerAddress == null) continue
            if (!links.remove(MeshTransportPolicy.WIFI_DIRECT, connection)) continue
            affected += peerId
            try { connection.socket.close() } catch (_: Exception) {}
        }
        affected.forEach { peerId ->
            val active = recomputeActivePeer(peerId)
            if (active != null) {
                meshPeers.connected(peerId, active.transportName)
                meshPeers.available(peerId, active.transportName)
                transportEvent("peer_transport_fallback", mapOf(
                    "peer_id" to peerId,
                    "transport" to active.transportName,
                    "reason" to "wifi_direct_group_role_changed",
                ))
            } else {
                meshPeers.disconnected(peerId, MeshTransportPolicy.WIFI_DIRECT)
                handleRoutesAfterPeerDisconnect(peerId, "wifi_direct_group_role_changed")
            }
        }
    }

    private fun activePeerConnection(peerId: String): PeerConnection? {
        val active = transportPeers[peerId]
        if (active != null && !active.socket.isClosed) return active
        return recomputeActivePeer(peerId)
    }

    private fun recomputeActivePeer(peerId: String): PeerConnection? {
        val links = peerLinks[peerId] ?: run {
            transportPeers.remove(peerId)
            return null
        }
        links.entries.removeIf { it.value.socket.isClosed }
        if (links.isEmpty()) {
            peerLinks.remove(peerId, links)
            transportPeers.remove(peerId)
            return null
        }
        val preferred = links.values.minWithOrNull(
            compareByDescending<PeerConnection> { MeshTransportPolicy.transportPriority(it.transportName) }
                .thenByDescending { it.lastSeenAt }
                .thenBy { it.transportName }
        )
        if (preferred != null) transportPeers[peerId] = preferred
        return preferred
    }

    private fun allPhysicalPeerLinks(): List<PeerConnection> = peerLinks.values.flatMap { it.values }.distinctBy { it.socket }

    private fun closePeerLinksForTransport(transportName: String) {
        val affected = mutableSetOf<String>()
        for ((peerId, links) in peerLinks) {
            val connection = links.remove(transportName) ?: continue
            affected += peerId
            try { connection.socket.close() } catch (_: Exception) {}
            recomputeActivePeer(peerId)
        }
        affected.forEach { peerId ->
            val active = recomputeActivePeer(peerId)
            if (active != null) {
                meshPeers.connected(peerId, active.transportName)
                meshPeers.available(peerId, active.transportName)
                transportEvent("peer_transport_fallback", mapOf(
                    "peer_id" to peerId,
                    "transport" to active.transportName,
                    "reason" to "transport_link_closed",
                ))
            } else {
                transportPeers.remove(peerId)
                meshPeers.disconnected(peerId, transportName)
                handleRoutesAfterPeerDisconnect(peerId, "${transportName}_disconnect")
            }
        }
    }

    private fun readTransportLoop(connection: PeerConnection) {
        try {
            while (transportRunning && !connection.socket.isClosed) {
                val line = connection.reader.readLine() ?: break
                connection.lastSeenAt = System.currentTimeMillis()
                if (line.length > 128 * 1024) break
                val packet = JSONObject(line)
                if (packet.toString().toByteArray(Charsets.UTF_8).size > 128 * 1024) break
                when (packet.optString("type")) {
                    "data" -> {
                        val from = packet.optString("sender_id")
                        val receiver = packet.optString("receiver_id")
                        if (from != connection.peerId) break
                        if (receiver != transportDeviceId) break
                        val key = peerKeys[from] ?: break
                        val receiverId = transportDeviceId ?: break
                        activePeerConnection(from)?.let { meshPeers.available(from, it.transportName) }
                        val encrypted = packet.optString("payload")
                        val keyEpoch = packet.optLong("key_epoch", Long.MIN_VALUE)
                        val acceptedEpochs = if (keyEpoch == Long.MIN_VALUE) emptySet() else MeshTransportSessionKeyPolicy.acceptedEpochs()
                        if (keyEpoch !in acceptedEpochs) continue
                        val decrypted = decryptPacket(
                            encrypted,
                            key,
                            senderId = from,
                            receiverId = receiverId,
                            keyEpoch = keyEpoch,
                        ) ?: continue
                        val packet = MeshPacket.fromJson(decrypted) ?: run {
                            transportEvent("mesh_dropped", mapOf(
                                "reason" to "unsupported_mesh_protocol",
                                "peer_id" to from,
                            ))
                            continue
                        }
                        if (packet.nextHopNodeId != null && packet.nextHopNodeId != transportDeviceId) continue
                        transportPacketsReceived.incrementAndGet()
                        transportBytesReceived.addAndGet(encrypted.toByteArray(Charsets.UTF_8).size.toLong())
                        routeDirectPacket(from, packet)
                    }
                    "ping" -> {
                        activePeerConnection(connection.peerId)?.let { meshPeers.available(connection.peerId, it.transportName) }
                        connection.send(JSONObject().put("type", "pong").put("sent_at", System.currentTimeMillis()))
                    }
                    "pong" -> {
                        connection.lastPongAt = System.currentTimeMillis()
                        activePeerConnection(connection.peerId)?.let { meshPeers.available(connection.peerId, it.transportName) }
                    }
                    "route_advertisement" -> updateRoutesFromAdvertisement(connection.peerId, packet)
                    "route_withdrawal" -> handleRouteWithdrawal(connection.peerId, packet)
                }
            }
        } catch (_: Exception) {
        } finally {
            unregisterPeer(connection.peerId, connection.socket)
            transportEvent("peer_disconnected", mapOf("peer_id" to connection.peerId))
            transportEvent("topology", meshTopologySnapshot())
        }
    }

    private fun handleRouteWithdrawal(senderPeerId: String, message: JSONObject) {
        val self = transportDeviceId ?: return
        if (!validTransportId(senderPeerId) || senderPeerId == self) return
        if (message.optString("type") != "route_withdrawal" || message.optString("sender_id").trim() != senderPeerId) return
        val key = peerKeys[senderPeerId] ?: return
        if (!com.sajjad.locallink.mesh.MeshRouteAdvertisementAuthenticator.verify(message, key)) {
            transportEvent("route_withdrawal_rejected", mapOf("peer_id" to senderPeerId, "reason" to "authentication_failed"))
            return
        }
        val destinations = message.optJSONArray("destinations") ?: JSONArray()
        val now = System.currentTimeMillis()
        val decision = routeAdvertisementPolicy.evaluate(
            peerId = senderPeerId,
            sessionId = message.optString("session_id"),
            sequence = message.optLong("control_sequence", -1L),
            sentAt = message.optLong("sent_at", 0L),
            routeCount = destinations.length(),
            now = now,
        )
        if (!decision.accepted) {
            transportEvent("route_withdrawal_rejected", mapOf("peer_id" to senderPeerId, "reason" to decision.reason))
            return
        }
        val failedNextHop = message.optString("failed_next_hop").trim().ifBlank { null }
        if (failedNextHop != null && (!validTransportId(failedNextHop) || failedNextHop != senderPeerId)) return
        val withdrawn = mutableListOf<String>()
        val count = destinations.length()
        for (i in 0 until count) {
            val destination = destinations.optString(i)?.trim().orEmpty()
            if (!validTransportId(destination) || destination == self) continue
            if (routeTable.remove(destination, senderPeerId).isNotEmpty()) withdrawn += destination
        }
        if (withdrawn.isNotEmpty()) {
            routeRecovery.markPeerLost(senderPeerId, withdrawn, now)
            withdrawn.forEach(routeStabilityPolicy::reset)
            transportEvent("route_withdrawn", mapOf(
                "sender_id" to senderPeerId,
                "failed_next_hop" to failedNextHop,
                "destinations" to withdrawn,
            ))
            flushMeshQueue()
            broadcastRouteAdvertisement(excludePeerId = senderPeerId)
        }
    }

    private fun routeDirectPacket(from: String, packet: MeshPacket) {
        val target = packet.destinationNodeId
        val self = transportDeviceId ?: return
        if (!validTransportId(target)) return
        if (packet.sourceNodeId.isBlank() || packet.destinationNodeId.isBlank()) return
        if (packet.sourceNodeId == self && packet.destinationNodeId != self) {
            transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "self_origin_loop"))
            return
        }
        if (!MeshLimits.hasValidHopBudget(packet.ttl, packet.hopCount, meshPacketTtl)) {
            transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "hop_budget_invalid"))
            return
        }
        if (packet.destinationNodeId != self && packet.ttl <= 0) {
            transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "ttl_expired"))
            return
        }
        // Canonical version-1 traffic uses end-to-end origin authentication.
        // Only the final destination can verify the source→destination identity
        // key; relays must rely on their per-hop authenticated/encrypted transport.
        if (packet.protocolVersion != MeshPacket.PROTOCOL_VERSION) {
            transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "unsupported_mesh_protocol"))
            return
        }
        val now = System.currentTimeMillis()
        if (!MeshLimits.isWithinPacketLifetime(packet.createdAt, now, meshMaxPacketAgeMs, meshMaxFutureSkewMs)) {
            transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "packet_age_invalid"))
            return
        }
        val path = packet.payload.optJSONArray(MeshPacket.MESH_PATH_KEY) ?: return
        if (pathContains(path, self)) {
            transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "loop_detected"))
            return
        }
        // Complete MeshRouter validation must succeed before this packet can reserve
        // replay state. Otherwise a malformed packet that can never route could poison
        // the source+packet-id entry and suppress the later valid packet.
        if (!meshRouter.validateForProcessing(packet, incomingPeerId = from)) {
            transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "router_validation"))
            return
        }
        if (packet.destinationNodeId == self) {
            if (!verifyOriginAuth(packet)) {
                transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "origin_auth_failed"))
                return
            }
            // Do not let a forged origin-auth value poison replay state for the
            // later valid packet that carries the same source+packet id.
            if (!markMeshPacketSeen(packet, persist = !isEphemeralCallMediaType(packet.type))) return
        } else {
            if (!markMeshPacketSeen(packet, persist = !isEphemeralCallMediaType(packet.type))) return
        }
        val result = meshRouter.route(packet, from)
        when (result) {
            MeshRouteResult.LOCAL_DELIVERY -> deliverLocalPacket(packet)
            MeshRouteResult.FORWARDED -> transportEvent("mesh_forwarded", mapOf("packet_id" to packet.packetId, "source_id" to packet.sourceNodeId, "destination_id" to packet.destinationNodeId, "hop_count" to packet.hopCount))
            MeshRouteResult.QUEUED -> transportEvent("mesh_queued", mapOf("packet_id" to packet.packetId, "target_id" to packet.destinationNodeId, "reason" to "no_route"))
            MeshRouteResult.NO_ROUTE -> transportEvent("mesh_unroutable", mapOf("packet_id" to packet.packetId, "target_id" to packet.destinationNodeId))
            MeshRouteResult.DROPPED -> transportEvent("mesh_dropped", mapOf("packet_id" to packet.packetId, "reason" to "router_validation"))
        }
    }

    private fun verifyOriginAuth(packet: MeshPacket): Boolean {
        val self = transportDeviceId ?: return false
        if (packet.destinationNodeId != self || packet.sourceNodeId == self) return false
        val key = peerKeys[packet.sourceNodeId] ?: return false
        return MeshPacketAuthentication.verifyOrigin(packet, key)
    }

    private fun buildSignedMeshPacket(target:String,payload:JSONObject):MeshPacket?{
        val self=transportDeviceId ?: return null
        if(!validTransportId(target) || target==self) return null
        val normalized=JSONObject(payload.toString()).apply{
            put("recipient_id",target)
            remove("mesh_version");remove("mesh_packet_id");remove("mesh_origin_id");remove("mesh_next_hop_id");remove("mesh_ttl");remove("mesh_hops");remove("mesh_created_at");remove("origin_auth")
            put(MeshPacket.MESH_PATH_KEY,JSONArray().put(self))
        }
        val mediaType=normalized.optString("type").trim()
        if(!MeshIdPolicy.isValidType(mediaType)) return null
        val unsigned=try{MeshPacket.new(self,target,mediaType,normalized,meshPacketTtl)}catch(_:Exception){return null}
        val destinationKey=peerKeys[target] ?: return null
        return try{unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned,destinationKey))}catch(_:Exception){null}
    }

    private fun sendCallMediaPacket(peerId:String,callId:String,payload:JSONObject):Boolean{
        if(!validTransportId(peerId) || callId.isBlank()) return false
        return sendRoutedPayload(peerId,payload)
    }

    private fun deliverLocalPacket(packet: MeshPacket) {
        val self = transportDeviceId ?: return
        if (!MeshFinalRecipientPolicy.isFinalRecipient(
                sourceNodeId = packet.sourceNodeId,
                destinationNodeId = packet.destinationNodeId,
                nextHopNodeId = packet.nextHopNodeId,
                localNodeId = self,
            )
        ) {
            transportEvent("mesh_dropped", mapOf(
                "packet_id" to packet.packetId,
                "source_id" to packet.sourceNodeId,
                "destination_id" to packet.destinationNodeId,
                "reason" to "local_delivery_not_final_recipient",
            ))
            return
        }
        val payload = packet.toApplicationPayload()
        when (packet.type) {
            "call_media" -> handleIncomingCallMedia(packet)
            "call_video_config" -> handleIncomingCallVideoConfig(packet)
            "call_video_frame" -> handleIncomingCallVideoFrame(packet)
            "direct_file_chunk" -> handleIncomingFileChunk(packet.sourceNodeId, payload)
            "direct_file_progress" -> handleFileProgress(payload)
            "direct_file_resume_request" -> handleFileResumeRequest(payload)
            "direct_file_cancel" -> handleFileCancel(payload)
            else -> transportEvent("message", mapOf(
                "payload" to payload.toString(),
                "sender_id" to packet.sourceNodeId,
                "mesh_final_recipient" to true,
                "mesh_packet_id" to packet.packetId,
                "mesh_destination_id" to self,
                "mesh_hop_count" to packet.hopCount,
            ))
        }
        transportEvent("mesh_delivered", mapOf("packet_id" to packet.packetId, "source_id" to packet.sourceNodeId, "destination_id" to self, "hop_count" to packet.hopCount))
    }

    /**
     * Multi-hop voice media. The packet itself is still routed by MeshRouter;
     * only the call endpoints hold the media key. Relays therefore see routing
     * metadata but never plaintext audio.
     */
    private fun startCallMediaInternal(callId:String, peerId:String, codec:String?) {
        require(callId.length in 1..128) { "invalid call id" }
        require(peerId.length in 1..128) { "invalid peer id" }
        stopCallMediaInternal("")
        val session = CallMediaSession(callId, peerId, codec?.trim()?.lowercase().orEmpty())
        synchronized(callMediaLock) { callMedia = session }
        session.start()
        transportEvent("call_media_started", mapOf("call_id" to callId, "peer_id" to peerId, "sample_rate" to CALL_SAMPLE_RATE, "frame_ms" to CALL_FRAME_MS, "codec" to session.codec))
    }

    private fun stopCallMediaInternal(callId:String) {
        synchronized(callMediaLock) {
            val current = callMedia
            if (current != null && (callId.isBlank() || current.callId == callId)) {
                current.stop()
                callMedia = null
            }
        }
        callMediaRecent.clear()
    }

    private fun setCallMediaMutedInternal(callId:String, muted:Boolean) {
        val current = callMedia
        if (current != null && current.callId == callId) current.setMuted(muted)
    }

    private fun configureCallVideoSurfacesInternal(preview: android.view.Surface, remote: android.view.Surface) {
        callVideoPreviewSurface = preview
        callVideoRemoteSurface = remote
    }

    private fun clearCallVideoSurfacesInternal() {
        callVideoPreviewSurface = null
        callVideoRemoteSurface = null
    }

    private fun startCallVideoInternal(callId:String, peerId:String) {
        require(callId.length in 1..128) { "invalid call id" }
        require(peerId.length in 1..128) { "invalid peer id" }
        val preview = callVideoPreviewSurface ?: throw IllegalStateException("local video surface is not configured")
        val remote = callVideoRemoteSurface ?: throw IllegalStateException("remote video surface is not configured")
        stopCallVideoInternal("")
        val session = CallVideoSession(
            context = this,
            callId = callId,
            peerId = peerId,
            previewSurface = preview,
            remoteSurface = remote,
            sendPacket = { packet -> sendCallMediaPacket(peerId, callId, packet) },
            event = { type, data -> transportEvent(type, data) },
        )
        synchronized(callMediaLock) { callVideo = session }
        session.start()
    }

    private fun stopCallVideoInternal(callId:String) {
        synchronized(callMediaLock) {
            val current = callVideo
            if (current != null && (callId.isBlank() || current.callId == callId)) {
                current.stop()
                callVideo = null
            }
        }
    }

    private fun setCallVideoEnabledInternal(callId:String, enabled:Boolean) {
        val current = callVideo
        if (current != null && current.callId == callId) current.setEnabled(enabled)
    }

    private fun switchCallCameraInternal(callId:String) {
        val current = callVideo
        if (current != null && current.callId == callId) current.switchCamera()
    }

    private fun handleIncomingCallVideoConfig(packet:MeshPacket) {
        val current = callVideo ?: return
        val payload = packet.payload
        if (payload.optString("call_id") != current.callId || packet.sourceNodeId != current.peerId) return
        val encoded = payload.optString("config").trim()
        if (encoded.isBlank()) return
        if (current.onIncomingConfig(encoded, payload.optInt("width", 640), payload.optInt("height", 360), packet.sourceNodeId, packet.destinationNodeId)) {
            transportEvent("call_video_config_received", mapOf("call_id" to current.callId, "peer_id" to current.peerId))
        }
    }

    private fun handleIncomingCallVideoFrame(packet:MeshPacket) {
        val current = callVideo ?: return
        val payload = packet.payload
        if (payload.optString("call_id") != current.callId || packet.sourceNodeId != current.peerId) return
        if (payload.optString("recipient_id").trim() != transportDeviceId) return
        if (payload.optString("sender_id").trim() != packet.sourceNodeId) return
        val sequence = payload.optLong("sequence", -1L)
        if (sequence < 0L || sequence > Long.MAX_VALUE - 1L) return
        val timestamp = payload.optLong("timestamp_ms", 0L)
        if (timestamp <= 0L || kotlin.math.abs(System.currentTimeMillis() - timestamp) > 120_000L) return
        val encoded = payload.optString("video").trim()
        if (encoded.isBlank()) return
        if (current.onIncomingFrame(sequence, timestamp, encoded, packet.sourceNodeId, packet.destinationNodeId)) {
            transportEvent("call_video_received", mapOf("call_id" to current.callId, "sequence" to sequence, "key_frame" to payload.optBoolean("key_frame", false), "hop_count" to packet.hopCount))
        }
    }

    private fun isEphemeralCallMediaType(type:String): Boolean = type == "call_media" || type == "call_video_config" || type == "call_video_frame"

    private fun callMediaStatsInternal(callId:String): Map<String,Any?> {
        val audio = callMedia?.takeIf { it.callId == callId }?.stats() ?: emptyMap()
        val video = callVideo?.takeIf { it.callId == callId }?.stats() ?: emptyMap()
        if (audio.isEmpty() && video.isEmpty()) return emptyMap()
        return audio + video.mapKeys { (k, _) -> if (k == "sent_frames" || k == "received_frames" || k == "dropped_frames") "video_$k" else k }
    }

    private fun handleIncomingCallMedia(packet:MeshPacket) {
        val payload = packet.payload
        val current = callMedia ?: return
        val selfId = transportDeviceId ?: return
        if (payload.optString("call_id") != current.callId) return
        if (packet.sourceNodeId != current.peerId) return
        if (payload.optString("sender_id").trim() != packet.sourceNodeId) return
        if (payload.optString("recipient_id").trim() != selfId) return
        val sequence = payload.optLong("sequence", -1L)
        if (sequence < 0L || sequence > Long.MAX_VALUE - 1L) return
        val timestamp = payload.optLong("timestamp_ms", 0L)
        val now = System.currentTimeMillis()
        if (timestamp <= 0L || kotlin.math.abs(now - timestamp) > 120_000L) return
        val sampleRate = payload.optInt("sample_rate", -1)
        val frameMs = payload.optInt("frame_ms", -1)
        val ttl = payload.optInt("ttl", -1)
        val codec = payload.optString("codec").trim().lowercase()
        if (sampleRate !in 8_000..48_000 || frameMs !in 5..60 || ttl !in 0..32) return
        if (sampleRate != CALL_SAMPLE_RATE || frameMs != CALL_FRAME_MS || codec != current.codec) return
        val encoded = payload.optString("audio_payload").trim()
        if (encoded.isBlank()) return
        val replayKey = "${current.callId}\u0000${packet.sourceNodeId}\u0000$sequence"
        if (callMediaRecent.putIfAbsent(replayKey, now) != null) return
        val audio = try { Base64.decode(encoded, Base64.DEFAULT) } catch (_:Exception) {
            callMediaRecent.remove(replayKey, now)
            return
        }
        if (audio.isEmpty()) {
            callMediaRecent.remove(replayKey, now)
            return
        }
        if (callMediaRecent.size > callMediaMaxRecent) {
            val oldest = callMediaRecent.entries.minByOrNull { it.value }
            if (oldest != null) callMediaRecent.remove(oldest.key, oldest.value)
        }
        current.enqueue(sequence, timestamp, audio)
        transportEvent("call_media_received", mapOf("call_id" to current.callId, "sequence" to sequence, "bytes" to audio.size, "hop_count" to packet.hopCount, "codec" to codec))
    }

    private inner class CallMediaSession(
        val callId:String,
        val peerId:String,
        val requestedCodec:String,
    ) {
        val codec:String = if (requestedCodec == "opus" && CallOpusCodec.isSupported(CALL_SAMPLE_RATE, 1)) "opus" else "pcm_s16le"
        private val running = AtomicBoolean(false)
        private val sequence = AtomicLong(0)
        private val sent = AtomicLong(0)
        private val received = AtomicLong(0)
        private val lost = AtomicLong(0)
        private val dropped = AtomicLong(0)
        @Volatile private var muted = false
        private var recorder:AudioRecord? = null
        private var track:AudioTrack? = null
        private var audioManager:AudioManager? = null
        private var audioFocusRequest:AudioFocusRequest? = null
        private var captureThread:Thread? = null
        private var playbackThread:Thread? = null
        private val playbackLock = Object()
        private val playbackQueue = PriorityQueue<AudioFrame>(compareBy<AudioFrame>{it.sequence})
        private var expectedSequence = 0L
        private var playbackSequenceInitialized = false
        private var lastArrivalMs:Long = 0L
        private var lastSenderTimestampMs:Long = 0L
        private var jitterMs:Double = 0.0
        private var opusEncoder: CallOpusCodec.Encoder? = null
        private var opusDecoder: CallOpusCodec.Decoder? = null

        fun start() {
            if (!running.compareAndSet(false,true)) return
            try {
                if (codec == "opus") {
                    opusEncoder = CallOpusCodec.createEncoder(CALL_SAMPLE_RATE, 1, 24_000)
                    opusDecoder = CallOpusCodec.createDecoder(CALL_SAMPLE_RATE, 1)
                }
                val minRecord = AudioRecord.getMinBufferSize(CALL_SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                if (minRecord <= 0) throw IllegalStateException("AudioRecord is unavailable")
                val bufferSize = maxOf(minRecord, CALL_FRAME_BYTES * 8)
                val r = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, CALL_SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferSize)
                if (r.state != AudioRecord.STATE_INITIALIZED) { r.release(); throw IllegalStateException("AudioRecord initialization failed") }
                val t = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(CALL_SAMPLE_RATE).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setBufferSizeInBytes(maxOf(CALL_FRAME_BYTES * 12, minRecord))
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
                if (t.state != AudioTrack.STATE_INITIALIZED) { r.release(); t.release(); throw IllegalStateException("AudioTrack initialization failed") }
                recorder=r; track=t
                requestCallAudioFocus()
                r.startRecording(); t.play()
                captureThread=Thread { captureLoop() }.also { it.start() }
                playbackThread=Thread { playbackLoop() }.also { it.start() }
            } catch (e: Exception) {
                running.set(false)
                try { recorder?.release() } catch (_:Exception) {}
                try { track?.release() } catch (_:Exception) {}
                recorder=null; track=null
                abandonCallAudioFocus()
                opusEncoder?.close(); opusDecoder?.close(); opusEncoder=null; opusDecoder=null
                throw e
            }
        }

        fun stop() {
            if (!running.compareAndSet(true,false)) return
            try { recorder?.stop() } catch (_:Exception) {}
            try { track?.stop() } catch (_:Exception) {}
            synchronized(playbackLock) { playbackQueue.clear(); playbackLock.notifyAll() }
            captureThread?.interrupt(); playbackThread?.interrupt()
            recorder?.release(); track?.release(); recorder=null; track=null
            abandonCallAudioFocus()
            opusEncoder?.close(); opusDecoder?.close(); opusEncoder=null; opusDecoder=null
            captureThread=null; playbackThread=null
            expectedSequence = 0L
            playbackSequenceInitialized = false
            lastArrivalMs = 0L
            lastSenderTimestampMs = 0L
            jitterMs = 0.0
        }

        private fun requestCallAudioFocus() {
            val manager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            audioManager = manager
            if (android.os.Build.VERSION.SDK_INT >= 26) {
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(false)
                    .build()
                audioFocusRequest = request
                val result = manager.requestAudioFocus(request)
                if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) throw IllegalStateException("Audio focus unavailable")
            } else {
                @Suppress("DEPRECATION")
                val result = manager.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) throw IllegalStateException("Audio focus unavailable")
            }
            manager.mode = AudioManager.MODE_IN_COMMUNICATION
        }

        private fun abandonCallAudioFocus() {
            val manager = audioManager ?: return
            try {
                if (android.os.Build.VERSION.SDK_INT >= 26) {
                    audioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
                } else {
                    @Suppress("DEPRECATION")
                    manager.abandonAudioFocus(null)
                }
            } catch (_: Throwable) {}
            audioFocusRequest = null
            audioManager = null
        }

        private fun captureLoop() {
            val buffer=ByteArray(CALL_FRAME_BYTES)
            while(running.get()) {
                try {
                    val r=recorder?.read(buffer,0,buffer.size,AudioRecord.READ_BLOCKING) ?: -1
                    if(r<=0) { dropped.incrementAndGet(); continue }
                    if (muted) { buffer.fill(0, 0, r); }
                    val data=if(r==buffer.size)buffer.copyOf() else buffer.copyOf(r)
                    val encodedAudio=if (codec == "opus") { opusEncoder?.encode(data) } else data
                    if (encodedAudio == null || encodedAudio.isEmpty()) { dropped.incrementAndGet(); continue }
                    val seq=sequence.getAndIncrement()
                    val ts=System.currentTimeMillis()
                    val encoded=Base64.encodeToString(encodedAudio, Base64.NO_WRAP)
                    val payload=JSONObject().put("type","call_media").put("sender_id",transportDeviceId).put("recipient_id",peerId).put("call_id",callId).put("sequence",seq).put("timestamp_ms",ts).put("sample_rate",CALL_SAMPLE_RATE).put("frame_ms",CALL_FRAME_MS).put("codec",codec).put("ttl",8).put("audio_payload",encoded)
                    if(sendCallMediaPacket(peerId,callId,payload)) sent.incrementAndGet() else dropped.incrementAndGet()
                } catch (_:InterruptedException) { break } catch (_:Exception) { dropped.incrementAndGet(); if(!running.get()) break }
            }
        }

        private fun playbackLoop() {
            while(running.get()) {
                val frame=synchronized(playbackLock) {
                    while(running.get() && playbackQueue.isEmpty()) playbackLock.wait(100)
                    if(!running.get()) return@synchronized null
                    val head=playbackQueue.peek() ?: return@synchronized null
                    val now=System.currentTimeMillis()
                    if (head.sequence > expectedSequence && now - head.receivedAtMs < CALL_JITTER_BUFFER_MS && playbackQueue.size < 4) {
                        playbackLock.wait(10)
                        return@synchronized null
                    }
                    playbackQueue.poll()
                } ?: continue
                if(frame.sequence > expectedSequence) { lost.addAndGet(frame.sequence-expectedSequence); expectedSequence=frame.sequence+1 } else if(frame.sequence < expectedSequence) continue else expectedSequence++
                try {
                    val pcm = if (codec == "opus") opusDecoder?.decode(frame.audio) else frame.audio
                    if (pcm == null || pcm.isEmpty()) { dropped.incrementAndGet(); continue }
                    track?.write(pcm,0,pcm.size,AudioTrack.WRITE_BLOCKING); received.incrementAndGet()
                } catch (_:Exception) { dropped.incrementAndGet() }
            }
        }

        fun setMuted(value:Boolean) { muted=value }

        fun enqueue(seq:Long, timestamp:Long, audio:ByteArray) {
            val arrival = System.currentTimeMillis()
            if (!playbackSequenceInitialized) {
                expectedSequence = seq
                playbackSequenceInitialized = true
            }
            if (lastArrivalMs > 0L && lastSenderTimestampMs > 0L) {
                val arrivalDelta = arrival - lastArrivalMs
                val senderDelta = timestamp - lastSenderTimestampMs
                val deviation = kotlin.math.abs(arrivalDelta - senderDelta).toDouble()
                jitterMs += (deviation - jitterMs) / 16.0
            }
            lastArrivalMs = arrival
            lastSenderTimestampMs = timestamp
            synchronized(playbackLock) {
                if(playbackQueue.size >= CALL_MAX_JITTER_FRAMES) { playbackQueue.poll(); dropped.incrementAndGet() }
                playbackQueue.add(AudioFrame(seq,timestamp,System.currentTimeMillis(),audio)); playbackLock.notifyAll()
            }
        }

        fun stats():Map<String,Any?> {
            val s=sent.get(); val r=received.get(); val l=lost.get(); val total=r+l
            return mapOf("sent_packets" to s, "received_packets" to r, "lost_packets" to l, "dropped_packets" to dropped.get(), "packet_loss_percent" to if(total>0) l*100.0/total else 0.0, "queued_frames" to synchronized(playbackLock){playbackQueue.size}, "jitter_ms" to jitterMs, "codec" to codec, "frame_ms" to CALL_FRAME_MS, "sample_rate" to CALL_SAMPLE_RATE, "muted" to muted)
        }
    }

    private data class AudioFrame(val sequence:Long,val timestampMs:Long,val receivedAtMs:Long,val audio:ByteArray)

    private fun buildRouteAdvertisement(peerId: String): JSONObject {
        val self = transportDeviceId ?: ""
        val now = System.currentTimeMillis()
        val routesJson = JSONArray()
        routeTable.snapshot(now)
            .asSequence()
            .filter { it["destination"].toString() != self && it["state"] == com.sajjad.locallink.mesh.MeshRouteState.ACTIVE.name }
            .sortedWith(compareBy<Map<String, Any?>> { it["cost"] as Int }.thenByDescending { it["route_version"] as Long }.thenBy { it["next_hop"].toString() }.thenBy { it["destination"].toString() })
            .take(MeshLimits.MAX_ROUTE_ADVERTISEMENT_ROUTES)
            .forEach { snapshot ->
                val path = (snapshot["path"] as? List<*>)?.mapNotNull { it?.toString()?.takeIf(String::isNotBlank) } ?: return@forEach
                val destination = snapshot["destination"].toString()
                val hopCount = snapshot["hop_count"] as Int
                if (!validTransportId(destination) || destination == self || path.firstOrNull() != self ||
                    path.distinct().size != path.size || hopCount !in 1..MeshLimits.MAX_HOPS ||
                    path.size != hopCount + 1 || path.size > MeshLimits.MAX_HOPS + 1) return@forEach
                routesJson.put(
                    JSONObject()
                        .put("destination_node_id", destination)
                        .put("hop_count", hopCount)
                        .put("route_version", snapshot["route_version"] as Long)
                        .put("path", JSONArray(path)),
                )
            }
        val unsigned = JSONObject()
            .put("type", "route_advertisement")
            .put("route_protocol_version", ROUTE_ADVERTISEMENT_PROTOCOL_VERSION)
            .put("sender_id", self)
            .put("session_id", routeAdvertisementSessionId)
            .put("advertisement_sequence", routeAdvertisementSequence.incrementAndGet())
            .put("sent_at", now)
            .put("routes", routesJson)
        val key = peerKeys[peerId] ?: return unsigned
        return com.sajjad.locallink.mesh.MeshRouteAdvertisementAuthenticator.withAuth(unsigned, key)
    }

    private fun broadcastRouteAdvertisement(excludePeerId: String? = null, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force) {
            val previous = routeAdvertisementLastSentAt.get()
            if (now - previous < ROUTE_ADVERTISEMENT_INTERVAL_MS) return
            if (!routeAdvertisementLastSentAt.compareAndSet(previous, now)) return
        } else {
            routeAdvertisementLastSentAt.set(now)
        }
        var sent = false
        for ((peerId, peer) in transportPeers) {
            if (peerId == excludePeerId || peer.socket.isClosed) continue
            try {
                peer.send(buildRouteAdvertisement(peerId))
                sent = true
            } catch (_: Exception) {
                transportSendFailures.incrementAndGet()
            }
        }
        if (!sent && transportPeers.isNotEmpty() && !force) routeAdvertisementLastSentAt.set(now)
    }

    private fun updateRoutesFromAdvertisement(peerId: String, advertisement: JSONObject) {
        val self = transportDeviceId ?: return
        if (!validTransportId(peerId) || peerId == self) return
        if (advertisement.optInt("route_protocol_version", -1) != ROUTE_ADVERTISEMENT_PROTOCOL_VERSION) return
        if (advertisement.optString("type") != "route_advertisement") return
        if (advertisement.optString("sender_id").trim() != peerId) return
        val key = peerKeys[peerId] ?: return
        if (!com.sajjad.locallink.mesh.MeshRouteAdvertisementAuthenticator.verify(advertisement, key)) {
            transportEvent("route_advertisement_rejected", mapOf("peer_id" to peerId, "reason" to "authentication_failed"))
            return
        }
        val routes = advertisement.optJSONArray("routes") ?: JSONArray()
        val now = System.currentTimeMillis()
        val decision = routeAdvertisementPolicy.evaluate(
                peerId = peerId,
                sessionId = advertisement.optString("session_id"),
                sequence = advertisement.optLong("advertisement_sequence", -1L),
                sentAt = advertisement.optLong("sent_at", 0L),
                routeCount = routes.length(),
                now = now,
        )
        if (!decision.accepted) {
            transportEvent("route_advertisement_rejected", mapOf("peer_id" to peerId, "reason" to decision.reason))
            return
        }
        val directVersion = directRouteVersions.computeIfAbsent(peerId) { AtomicLong(now) }.get()
        routeTable.upsert(peerId, MeshRoute(destinationNodeId = peerId, nextHopNodeId = peerId, hopCount = 1, expiresAt = now + 60_000L, lastSeenAt = now, routeVersion = directVersion, path = listOf(self, peerId)))
        var accepted = 0
        val count = routes.length()
        for (i in 0 until count) {
            val item = routes.optJSONObject(i) ?: continue
            val destination = item.optString("destination_node_id").trim()
            val advertisedHops = item.optInt("hop_count", -1)
            val version = item.optLong("route_version", -1L)
            val advertisedPath = jsonStringList(item.optJSONArray("path"))
            if (!validTransportId(destination) || destination == self || destination == peerId) continue
            if (version <= 0L || version > now + MeshLimits.MAX_ROUTE_VERSION_FUTURE_SKEW_MS) continue
            if (advertisedHops < 1 || advertisedHops > MeshLimits.MAX_HOPS - 1) continue
            if (advertisedPath.size < 2 || advertisedPath.firstOrNull() != peerId || advertisedPath.lastOrNull() != destination) continue
            if (advertisedHops != advertisedPath.size - 1) continue
            if (advertisedPath.size > MeshLimits.MAX_HOPS || advertisedPath.distinct().size != advertisedPath.size) continue
            val fullPath = buildList { add(self); addAll(advertisedPath) }
            if (fullPath.distinct().size != fullPath.size || fullPath.size != advertisedHops + 2) continue
            val currentRoutes = routeTable.allFor(destination, now)
            val currentMaxVersion = currentRoutes.maxOfOrNull { it.routeVersion }
            if (currentMaxVersion != null && version > currentMaxVersion + MeshLimits.MAX_ROUTE_VERSION_ADVANCE_MS) continue
            val candidate = MeshRoute(
                destinationNodeId = destination,
                nextHopNodeId = peerId,
                hopCount = advertisedHops + 1,
                expiresAt = now + 30_000L,
                lastSeenAt = now,
                routeVersion = version,
                path = fullPath,
            )
            val previousBest = routeTable[destination]
            val stability = routeStabilityPolicy.beforeChange(destination, previousBest, candidate, now)
            if (!stability.accepted) {
                transportEvent("route_advertisement_rejected", mapOf("peer_id" to peerId, "destination_id" to destination, "reason" to stability.reason))
                continue
            }
            if (routeTable.upsert(destination, candidate)) {
                accepted++
                val currentBest = routeTable[destination]
                if (previousBest != null && currentBest != null && previousBest.nextHopNodeId != currentBest.nextHopNodeId) {
                    routeStabilityPolicy.recordAcceptedChange(destination, previousBest.nextHopNodeId, currentBest.nextHopNodeId, now)
                    routeRecovery.markRecovered(destination)
                    transportEvent("route_changed", mapOf("destination_id" to destination, "previous_next_hop" to previousBest.nextHopNodeId, "next_hop_id" to currentBest.nextHopNodeId, "hop_count" to currentBest.hopCount))
                } else if (previousBest == null && currentBest != null) {
                    val recovery = routeRecovery.markRecovered(destination)
                    transportEvent("route_recovered", mapOf(
                        "destination_id" to destination,
                        "next_hop_id" to currentBest.nextHopNodeId,
                        "hop_count" to currentBest.hopCount,
                        "reason" to if (recovery != null) "advertisement_after_disconnect" else "new_route",
                    ))
                }
            }
        }
        transportEvent("route_update", mapOf("peer_id" to peerId, "advertised_routes" to count, "accepted_routes" to accepted))
        if (accepted > 0) broadcastRouteAdvertisement(excludePeerId = peerId)
        transportEvent("topology", meshTopologySnapshot())
    }

    private fun jsonStringList(value: JSONArray?): List<String> {
        if (value == null) return emptyList()
        return buildList(value.length()) {
            for (i in 0 until value.length()) {
                value.optString(i).trim().takeIf { it.isNotBlank() }?.let(::add)
            }
        }
    }

    private fun pruneRoutes() {
        val now = System.currentTimeMillis()
        val affected = routeTable.prune(now) { peerId ->
            transportPeers[peerId]?.socket?.isClosed == false
        }
        affected.forEach { destination ->
            transportEvent("route_removed", mapOf("destination_id" to destination, "reason" to "stale_or_unavailable_next_hop"))
            val replacement = routeTable[destination]
            if (replacement != null) {
                routeRecovery.markRecovered(destination)
                transportEvent("route_recovered", mapOf(
                    "destination_id" to destination,
                    "next_hop_id" to replacement.nextHopNodeId,
                    "hop_count" to replacement.hopCount,
                    "reason" to "alternate_after_prune",
                ))
            }
        }
        routeRecovery.prune(now).forEach { entry ->
            transportEvent("route_recovery_expired", mapOf(
                "destination_id" to entry.destinationNodeId,
                "failed_next_hop" to entry.failedNextHopNodeId,
                "reason" to "recovery_timeout",
            ))
        }
        if (affected.isNotEmpty()) {
            broadcastRouteAdvertisement()
            flushMeshQueue()
        }
    }

    private fun sendRoutedPayload(target: String, payload: JSONObject): Boolean {
        val self = transportDeviceId ?: return false
        if (!validTransportId(target) || target == self) return false
        val normalized = JSONObject(payload.toString()).apply {
            // Wire routing fields are owned exclusively by MeshPacket. A caller cannot
            // spoof source/path/TTL/packet identity by putting mesh fields in its payload.
            put("recipient_id", target)
            remove("mesh_version")
            remove("mesh_packet_id")
            remove("mesh_origin_id")
            remove("mesh_next_hop_id")
            remove("mesh_ttl")
            remove("mesh_hops")
            remove("mesh_created_at")
            remove("origin_auth")
            put(MeshPacket.MESH_PATH_KEY, JSONArray().put(self))
        }
        val mediaType = normalized.optString("type").trim()
        if (!MeshIdPolicy.isValidType(mediaType)) return false
        val unsigned = try {
            MeshPacket.new(
                sourceNodeId = self,
                destinationNodeId = target,
                type = mediaType,
                payload = normalized,
                ttl = meshPacketTtl,
            )
        } catch (_: IllegalArgumentException) {
            return false
        }
        val destinationKey = peerKeys[target] ?: return false
        val packet = try {
            unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, destinationKey))
        } catch (_: IllegalArgumentException) {
            return false
        }
        val isLiveMedia = mediaType == "call_media" || mediaType == "call_video_config" || mediaType == "call_video_frame"
        val before = if (isLiveMedia) routeTable[target] else null
        val result = meshRouter.route(packet)
        val after = if (isLiveMedia) routeTable[target] else null
        if (isLiveMedia) {
            val base = mapOf(
                "call_id" to normalized.optString("call_id"),
                "destination_id" to target,
                "media_type" to mediaType,
            )
            when (result) {
                MeshRouteResult.FORWARDED, MeshRouteResult.LOCAL_DELIVERY -> {
                    if (before?.nextHopNodeId != after?.nextHopNodeId || before?.hopCount != after?.hopCount) {
                        transportEvent("call_media_route_changed", base + mapOf(
                            "previous_next_hop" to before?.nextHopNodeId,
                            "next_hop_id" to after?.nextHopNodeId,
                            "hop_count" to after?.hopCount,
                        ))
                    }
                }
                MeshRouteResult.NO_ROUTE, MeshRouteResult.DROPPED -> {
                    transportEvent("call_media_route_degraded", base + mapOf(
                        "previous_next_hop" to before?.nextHopNodeId,
                        "reason" to if (result == MeshRouteResult.NO_ROUTE) "no_route" else "router_drop",
                    ))
                }
                MeshRouteResult.QUEUED -> {
                    // Live media must never enter durable store-and-forward. A queued result
                    // is treated as degraded rather than reporting a successful media send.
                    transportEvent("call_media_route_degraded", base + mapOf(
                        "previous_next_hop" to before?.nextHopNodeId,
                        "reason" to "live_media_queued_unexpectedly",
                    ))
                }
            }
        }
        return when (result) {
            MeshRouteResult.FORWARDED,
            MeshRouteResult.LOCAL_DELIVERY -> true
            MeshRouteResult.QUEUED -> !isLiveMedia
            MeshRouteResult.NO_ROUTE,
            MeshRouteResult.DROPPED -> false
        }
    }

    private fun sendPacketToPeerId(peerNodeId: String, packet: MeshPacket): Boolean {
        val peer = activePeerConnection(peerNodeId) ?: return false
        return sendToPeer(peer, packet)
    }

    private fun sendToPeer(peer: PeerConnection, packet: MeshPacket): Boolean {
        val self = transportDeviceId ?: return false
        val key = peerKeys[peer.peerId] ?: return false
        return try {
            if (packet.nextHopNodeId != peer.peerId) return false
            val keyEpoch = MeshTransportSessionKeyPolicy.currentEpoch()
            val encrypted = encryptPacket(
                packet.toJson(),
                key,
                senderId = self,
                receiverId = peer.peerId,
                hopAad = MeshPacketAuthentication.hopIdentityAad(self, peer.peerId, keyEpoch),
                keyEpoch = keyEpoch,
            )
            val frame = JSONObject().put("type", "data").put("sender_id", self).put("receiver_id", peer.peerId).put("key_epoch", keyEpoch).put("payload", encrypted)
            peer.send(frame)
            transportPacketsSent.incrementAndGet()
            transportBytesSent.addAndGet(encrypted.toByteArray(Charsets.UTF_8).size.toLong())
            true
        } catch (_: Exception) {
            transportSendFailures.incrementAndGet()
            unregisterPeer(peer.peerId, peer.socket)
            false
        }
    }

    private fun sendToPeer(peer: PeerConnection, payload: JSONObject): Boolean {
        val self = transportDeviceId ?: return false
        val target = payload.optString("recipient_id").trim().ifBlank { peer.peerId }
        if (!validTransportId(target) || target == self || target != peer.peerId) return false
        val normalized = JSONObject(payload.toString()).apply {
            put("recipient_id", target)
            remove("mesh_version")
            remove("mesh_packet_id")
            remove("mesh_origin_id")
            remove("mesh_next_hop_id")
            remove("mesh_ttl")
            remove("mesh_hops")
            remove("mesh_created_at")
            remove("origin_auth")
            put(MeshPacket.MESH_PATH_KEY, JSONArray().put(self))
        }
        val type = normalized.optString("type").trim()
        val packet = try {
            MeshPacket.new(
                sourceNodeId = self,
                destinationNodeId = target,
                type = type,
                payload = normalized,
                ttl = meshPacketTtl,
                nextHopNodeId = peer.peerId,
            )
        } catch (_: IllegalArgumentException) {
            return false
        }
        val destinationKey = peerKeys[target] ?: return false
        return try {
            sendToPeer(peer, packet.withOriginAuth(MeshPacketAuthentication.signOrigin(packet, destinationKey)))
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun pathContains(path: org.json.JSONArray, id: String): Boolean {
        for (i in 0 until path.length()) if (path.optString(i) == id) return true
        return false
    }

    private fun isStoreForwardable(type: String): Boolean = type == "direct_message" || type == "direct_file_chunk"

    private fun markMeshPacketSeen(packet: MeshPacket, persist:Boolean = true):Boolean{
        val source = packet.sourceNodeId.trim()
        val id = packet.packetId.trim()
        val now = System.currentTimeMillis()
        if (!MeshIdPolicy.isValid(source) || !MeshIdPolicy.isValid(id)) return false
        val ephemeral = isEphemeralCallMediaType(packet.type)
        val tracker = if (ephemeral) seenEphemeralMeshPackets else seenMeshPackets
        val firstSeen = tracker.markSeen(source, id, now)
        if (!firstSeen) {
            val duplicates = meshDuplicatePacketsDropped.incrementAndGet()
            transportEvent("mesh_duplicate_dropped", mapOf(
                "packet_id" to id,
                "source_id" to source,
                "duplicate_count" to duplicates,
            ))
            return false
        }
        if (persist) persistSeenMeshPacket(source, id, now)
        return true
    }

    private fun meshQueueSecretKey(): javax.crypto.SecretKey {
        val alias = "locallink_mesh_queue_v2"
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(alias)) {
            val generator = javax.crypto.KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(false)
                .build()
            generator.init(spec)
            generator.generateKey()
        }
        return ks.getKey(alias, null) as javax.crypto.SecretKey
    }

    private fun encryptMeshAtRest(value: String): String {
        val iv = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, meshQueueSecretKey(), GCMParameterSpec(128, iv))
        return Base64.encodeToString(iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    private fun decryptMeshAtRest(value: String): String? {
        return try {
            val all = Base64.decode(value, Base64.DEFAULT)
            if (all.size < 13) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, meshQueueSecretKey(), GCMParameterSpec(128, all.copyOfRange(0, 12)))
            String(cipher.doFinal(all.copyOfRange(12, all.size)), Charsets.UTF_8)
        } catch (_: Exception) { null }
    }

    private fun enqueueMeshPacket(packet: MeshPacket): Boolean {
        if (!isStoreForwardable(packet.type)) return false
        if (!MeshLimits.hasValidHopBudget(packet.ttl, packet.hopCount, meshPacketTtl)) return false
        if (!MeshLimits.isWithinPacketLifetime(packet.createdAt)) return false
        val target = packet.destinationNodeId
        val serialized = packet.toJson().toString()
        synchronized(meshFlushLock) {
            meshQueueDir.mkdirs()
            val files = meshQueueDir.listFiles { file -> file.extension == "json" }?.sortedBy { it.name } ?: emptyList()
            if (files.any { queuedPacketId(it) == packet.packetId }) return false
            val bytes = files.sumOf { it.length() }
            if (files.size >= meshMaxQueuePackets || bytes + serialized.toByteArray(Charsets.UTF_8).size > meshMaxQueueBytes) {
                transportEvent("mesh_queue_full", mapOf("target_id" to target, "queued_packets" to files.size, "queued_bytes" to bytes))
                return false
            }
            val id=meshQueueSequence.incrementAndGet();val now=System.currentTimeMillis();val packetExpiry=MeshLimits.packetExpiryAt(packet.createdAt);val record=JSONObject().put("target_id",target).put("packet_id",packet.packetId).put("queued_at",now).put("expires_at",minOf(packetExpiry, now + MeshLimits.MAX_PACKET_AGE_MS)).put("attempts",0).put("retry_after",now).put("payload_enc",encryptMeshAtRest(serialized))
            val file = File(meshQueueDir, "${System.currentTimeMillis()}_${id.toString().padStart(8, '0')}_${UUID.randomUUID()}.json")
            file.writeText(record.toString(), Charsets.UTF_8)
            transportEvent("mesh_queued", mapOf("target_id" to target, "packet_id" to packet.packetId, "queued_packets" to files.size + 1))
            transportEvent("topology", meshTopologySnapshot())
            return true
        }
    }

    private fun queuedPacketId(file: File): String = try {
        JSONObject(file.readText(Charsets.UTF_8)).optString("packet_id").trim()
    } catch (_: Exception) { "" }

    private fun flushMeshQueue() {
        synchronized(meshFlushLock) {
            if (!transportRunning) return
            val now = System.currentTimeMillis()
            val files = meshQueueDir.listFiles { file -> file.extension == "json" }?.sortedBy { it.name } ?: return
            for (file in files) {
                try {
                    val record = JSONObject(file.readText(Charsets.UTF_8))
                    val target = record.optString("target_id").trim()
                    val packetId = record.optString("packet_id").trim()
                    val expiresAt = record.optLong("expires_at", 0L)
                    val retryAfter = record.optLong("retry_after", 0L)
                    if (expiresAt > 0L && now >= expiresAt) {
                        file.delete()
                        transportEvent("mesh_expired", mapOf("target_id" to target, "packet_id" to packetId))
                        continue
                    }
                    if (retryAfter > now) continue
                    val payloadText = if (record.has("payload_enc")) decryptMeshAtRest(record.optString("payload_enc")) else record.optString("payload")
                    if (payloadText.isNullOrEmpty()) { file.delete(); continue }
                    val packet = MeshPacket.fromJson(JSONObject(payloadText)) ?: run {
                        file.delete()
                        transportEvent("mesh_dropped", mapOf(
                            "target_id" to target,
                            "packet_id" to packetId,
                            "reason" to "unsupported_mesh_protocol",
                        ))
                        continue
                    }
                    val self = transportDeviceId
                    val refreshedPacket = if (self != null && packet.sourceNodeId == self) {
                        val destinationKey = peerKeys[packet.destinationNodeId]
                        if (destinationKey != null) {
                            try {
                                packet.withOriginAuth(MeshPacketAuthentication.signOrigin(packet, destinationKey))
                            } catch (_: IllegalArgumentException) {
                                null
                            }
                        } else null
                    } else packet
                    if (refreshedPacket == null) {
                        transportEvent("mesh_dropped", mapOf(
                            "target_id" to target,
                            "packet_id" to packet.packetId,
                            "reason" to "missing_destination_key",
                        ))
                        continue
                    }
                    val readyPacket = refreshedPacket
                    if (!validTransportId(target) || readyPacket.destinationNodeId != target) {
                        file.delete(); continue
                    }
                    if (readyPacket.packetId != packetId || !MeshLimits.hasValidHopBudget(readyPacket.ttl, readyPacket.hopCount, meshPacketTtl) || !MeshLimits.isWithinPacketLifetime(readyPacket.createdAt, now)) {
                        file.delete()
                        transportEvent("mesh_dropped", mapOf("target_id" to target, "packet_id" to readyPacket.packetId, "reason" to "hop_or_age_invalid"))
                        continue
                    }
                    val result = meshRouter.route(readyPacket, allowQueue = false)
                    if (result == MeshRouteResult.FORWARDED || result == MeshRouteResult.LOCAL_DELIVERY) {
                        file.delete()
                        transportEvent("mesh_forwarded", mapOf("target_id" to target, "packet_id" to readyPacket.packetId))
                    } else {
                        val attempts = record.optInt("attempts", 0) + 1
                        if (attempts >= 30) {
                            file.delete()
                            transportEvent("mesh_retry_exhausted", mapOf("target_id" to target, "packet_id" to readyPacket.packetId, "attempts" to attempts))
                            continue
                        }
                        val delay = (1000L shl attempts.coerceAtMost(6)).coerceAtMost(60_000L)
                        record.put("packet_id", readyPacket.packetId).put("attempts", attempts).put("retry_after", now + delay)
                        file.writeText(record.toString(), Charsets.UTF_8)
                        transportEvent("mesh_retry_scheduled", mapOf("target_id" to target, "packet_id" to readyPacket.packetId, "attempts" to attempts, "retry_after_ms" to delay))
                    }
                } catch (_: Exception) {
                    file.delete()
                }
            }
            transportEvent("topology", meshTopologySnapshot())
        }
    }

    private fun refreshDirectRoutes() {
        val now = System.currentTimeMillis()
        val self = transportDeviceId ?: return
        for (peer in transportPeers.values.toList()) {
            if (peer.socket.isClosed) continue
            val path = listOf(self, peer.peerId)
            val version = directRouteVersions[peer.peerId]?.get() ?: now
            routeTable.upsert(peer.peerId, MeshRoute(destinationNodeId = peer.peerId, nextHopNodeId = peer.peerId, hopCount = 1, expiresAt = now + 60_000L, lastSeenAt = now, routeVersion = version, path = path))
            meshPeers.available(peer.peerId, peer.transportName, now)
        }
    }

    private fun startMeshMaintenance() {
        if (meshMaintenanceThread?.isAlive == true) return
        meshMaintenanceThread = Thread {
            while (transportRunning) {
                try {
                    cleanupSeenMeshPackets()
                    refreshDirectRoutes()
                    flushMeshQueue()
                    if (!transportGroupOwner) {
                        val owner = transportGroupOwnerAddress
                        if (!owner.isNullOrEmpty() && transportPeers.values.none { it.ownerAddress == owner && !it.socket.isClosed }) {
                            connectTransportToOwner(owner)
                        }
                    }
                    val now = System.currentTimeMillis()
                    if (now - routeAdvertisementLastSentAt.get() >= ROUTE_ADVERTISEMENT_INTERVAL_MS) {
                        broadcastRouteAdvertisement()
                    }
                    for ((nodeId, endpoint) in lanEndpoints) {
                        if (now - endpoint.lastSeenAt > MeshTransportPolicy.LAN_ENDPOINT_RETENTION_MS && activePeerConnection(nodeId) == null) {
                            lanEndpoints.remove(nodeId, endpoint)
                            lastLanBeaconAt.remove(nodeId)
                            transportEvent("peer_expired", mapOf(
                                "peer_id" to nodeId,
                                "transport" to MeshTransportPolicy.LAN,
                                "reason" to "discovery_timeout",
                            ))
                            meshPeers.unavailable(nodeId, MeshTransportPolicy.LAN, now)
                            handleRoutesAfterPeerDisconnect(nodeId, "lan_discovery_timeout")
                            continue
                        }
                        if (!transportPeers.containsKey(nodeId) && (transportDeviceId ?: "").compareTo(nodeId) < 0 && peerKeys.containsKey(nodeId)) {
                            connectLanPeer(nodeId, endpoint.host, endpoint.port)
                        }
                    }
                    sendResumeRequests()
                    for (peer in allPhysicalPeerLinks()) {
                        try {
                            peer.lastPingAt = now
                            peer.send(JSONObject().put("type", "ping").put("sent_at", now))
                            if (now - peer.lastPongAt > MeshTransportPolicy.HEARTBEAT_TIMEOUT_MS) {
                                transportHeartbeatTimeouts.incrementAndGet()
                                transportEvent("transport_heartbeat_timeout", mapOf(
                                    "peer_id" to peer.peerId,
                                    "transport" to peer.transportName,
                                    "last_pong_at" to peer.lastPongAt,
                                ))
                                unregisterPeer(peer.peerId, peer.socket)
                            }
                        } catch (_: Exception) {
                            transportSendFailures.incrementAndGet()
                            unregisterPeer(peer.peerId, peer.socket)
                        }
                    }
                    Thread.sleep(MeshTransportPolicy.HEARTBEAT_INTERVAL_MS)
                } catch (_: InterruptedException) {
                    break
                } catch (_: Exception) {
                }
            }
        }.also { it.start() }
    }

    private fun cleanupSeenMeshPackets(){
        val now=System.currentTimeMillis()
        seenMeshPackets.cleanup(now)
        seenEphemeralMeshPackets.cleanup(now)
        // Remove any orphaned durable records left by an interrupted write or older build.
        seenMeshDir.listFiles()?.forEach{if(now-it.lastModified()>MeshLimits.SEEN_RETENTION_MS)try{it.delete()}catch(_:Exception){}}
        meshQueueDir.listFiles()?.forEach{if(it.extension=="json"&&now-it.lastModified()>48*60*60*1000L)try{it.delete()}catch(_:Exception){}}
        val d=File(filesDir,"locallink_direct_files")
        d.listFiles()?.forEach{f->
            val staleCutoff = if (f.name.startsWith(".done_")) DirectFileTransferPolicy.COMPLETION_MARKER_RETENTION_MS else DirectFileTransferPolicy.IDLE_TIMEOUT_MS
            if((f.name.endsWith(".part")||f.name.endsWith(".meta.json")||f.name.endsWith(".out.json")||f.name.startsWith(".done_"))&&now-f.lastModified()>staleCutoff)try{f.delete()}catch(_:Exception){}
            // Native direct-file delivery creates a plaintext final file only until
            // Flutter receives the event and converts it to protected storage.
            // Never retain an orphaned plaintext final file after a process crash.
            if(!f.name.startsWith(".done_")&&!f.name.endsWith(".part")&&!f.name.endsWith(".meta.json")&&!f.name.endsWith(".out.json")&&!f.name.endsWith(".enc")&&now-f.lastModified()>DirectFileTransferPolicy.IDLE_TIMEOUT_MS){
                try{f.delete()}catch(_:Exception){}
            }
        }
        cancelledIncomingTransfers.entries.toList().forEach { (id, expiresAt) -> if (now >= expiresAt) cancelledIncomingTransfers.remove(id, expiresAt) }
        incomingFiles.entries.toList().forEach { (id, transfer) ->
            if (now - transfer.updatedAt > DirectFileTransferPolicy.IDLE_TIMEOUT_MS) {
                if (incomingFiles.remove(id, transfer)) {
                    try { transfer.file.close() } catch (_: Exception) {}
                    try { File(transfer.path).delete() } catch (_: Exception) {}
                    deleteIncomingMeta(transfer)
                    transportEvent("file_expired", mapOf("transfer_id" to id, "message_id" to transfer.messageId, "file_id" to transfer.fileId))
                }
            }
        }
        pruneRoutes()
    }

    private fun clearTransportStorage() {
        synchronized(meshFlushLock) {
            meshQueueDir.listFiles()?.forEach { try { it.delete() } catch (_: Exception) {} }
            val directDir = File(filesDir, "locallink_direct_files")
            directDir.listFiles()?.forEach { try { it.delete() } catch (_: Exception) {} }
            incomingFiles.values.forEach { try { it.file.close() } catch (_: Exception) {} }
            incomingFiles.clear()
            seenMeshPackets.clear();seenEphemeralMeshPackets.clear();routeRecovery.clear();meshDuplicatePacketsDropped.set(0);seenMeshDir.listFiles()?.forEach{try{it.delete()}catch(_:Exception){}};outgoingTransfers.clear();outgoingReservations.clear();cancelledIncomingTransfers.clear();routeTable.clear()
            try {
                val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                if (ks.containsAlias("locallink_mesh_queue_v2")) ks.deleteEntry("locallink_mesh_queue_v2")
                if (ks.containsAlias(STATE_KEY_ALIAS)) ks.deleteEntry(STATE_KEY_ALIAS)
            } catch (_: Exception) {}
            transportBytesSent.set(0)
            transportBytesReceived.set(0)
            transportPacketsSent.set(0)
            transportPacketsReceived.set(0)
            transportReconnectAttempts.set(0)
            transportSendFailures.set(0)
            transportHeartbeatTimeouts.set(0)
            try { getSharedPreferences(PREFS, MODE_PRIVATE).edit().clear().apply() } catch (_: Exception) {}
            transportEvent("topology", meshTopologySnapshot())
        }
    }

    private fun meshQueueStats(): Pair<Int, Long> {
        val files = meshQueueDir.listFiles { file -> file.extension == "json" } ?: return Pair(0, 0L)
        return Pair(files.size, files.sumOf { it.length() })
    }

    private fun meshTopologySnapshot(): Map<String, Any?> {
        val stats = meshQueueStats()
        val peers = transportPeers.values.map { peer ->
            val links = peerLinks[peer.peerId]?.values.orEmpty()
            mapOf(
                "peer_id" to peer.peerId,
                "node_id" to peer.peerId,
                "direct" to true,
                "authenticated" to true,
                "transport" to peer.transportName,
                "active_transport" to peer.transportName,
                "available_transports" to links.map { it.transportName }.distinct().sorted(),
                "physical_link_count" to links.size,
                "address" to peer.remoteAddress,
                "group_owner" to (peer.transportName == MeshTransportPolicy.WIFI_DIRECT && peer.ownerAddress == null),
                "connected_at" to peer.connectedAt,
            )
        }.sortedBy { it["peer_id"].toString() }
        return mapOf(
            "device_id" to transportDeviceId,
            "node_id" to transportDeviceId,
            "transport_active" to transportRunning,
            "transport_connected" to (transportRunning && transportPeers.isNotEmpty()),
            "lan_active" to (transportRunning && lanServer != null),
            "wifi_direct_peer_count" to peers.count { it["transport"] == MeshTransportPolicy.WIFI_DIRECT },
            "group_owner" to transportGroupOwner,
            "peer_count" to peers.size,
            "queued_packets" to stats.first,
            "queued_bytes" to stats.second,
            "bytes_sent" to transportBytesSent.get(),
            "bytes_received" to transportBytesReceived.get(),
            "packets_sent" to transportPacketsSent.get(),
            "packets_received" to transportPacketsReceived.get(),
            "reconnect_attempts" to transportReconnectAttempts.get(),
            "send_failures" to transportSendFailures.get(),
            "heartbeat_timeouts" to transportHeartbeatTimeouts.get(),
            "lan_discovery_endpoint_count" to lanEndpoints.size,
            "background_service" to LocalLinkTransportService.isRunning(),
            "service_uptime_ms" to (System.currentTimeMillis()-startedAt),
            "routes" to routeTable.snapshot(),
            "recovering_routes" to routeRecovery.snapshot(),
            "outgoing_transfers" to outgoingTransfers.values.map {
                mapOf(
                    "transfer_id" to it.transferId,
                    "recipient_id" to it.recipientId,
                    "size" to it.size,
                    "total_chunks" to it.totalChunks,
                    "acked_chunks" to (it.totalChunks - missingChunkCount(it)),
                    "retry_attempts" to (outgoingRetryCounts[it.transferId] ?: 0),
                )
            },
            "incoming_transfers" to incomingFiles.values.map{mapOf("transfer_id" to it.transferId,"sender_id" to it.senderId,"total_chunks" to it.totalChunks,"received_chunks" to it.received.count{b->b})},
            "peers" to peers.map { peer ->
                val nodeId = peer["peer_id"].toString()
                peer + mapOf(
                    "state" to (meshPeers.get(nodeId)?.state?.name ?: "CONNECTED"),
                    "last_seen_at" to (meshPeers.get(nodeId)?.lastSeenAt ?: peer["connected_at"]),
                )
            },
            "mesh_peers" to meshPeers.all().map { mapOf(
                "node_id" to it.nodeId,
                "state" to it.state.name,
                "transport" to it.transport,
                "last_seen_at" to it.lastSeenAt,
                "connected_at" to it.connectedAt,
            ) },
        )
    }




    private fun sha256File(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n <= 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun handleIncomingFileChunk(from: String, payload: JSONObject) {
        val self = transportDeviceId ?: return
        if (payload.optString("recipient_id") != self) return
        val transferId = payload.optString("transfer_id").trim()
        val fileId = payload.optString("file_id").trim()
        val messageId = payload.optString("message_id").trim()
        val originSenderId = payload.optString("sender_id").trim()
        if (!validFileTransferId(transferId) || !validFileTransferId(fileId) || !validFileTransferId(messageId) || !validTransportId(originSenderId)) return
        val fileName = safeFileName(payload.optString("file_name").trim().ifEmpty { "attachment" })
        val contentType = payload.optString("content_type", "application/octet-stream")
        val size = payload.optLong("size", -1L)
        val sha = payload.optString("sha256").trim().lowercase()
        val index = payload.optInt("chunk_index", -1)
        val totalChunks = payload.optInt("total_chunks", -1)
        if (transferId.isEmpty() || fileId.isEmpty() || messageId.isEmpty() || originSenderId.isEmpty() || size < 0 || size > maxDirectFileSize || index < 0 || totalChunks < 1 || index >= totalChunks || sha.length != 64) return
        val cancelledUntil=cancelledIncomingTransfers[transferId]
        if(cancelledUntil!=null){
            if(System.currentTimeMillis()<cancelledUntil) return
            cancelledIncomingTransfers.remove(transferId,cancelledUntil)
        }
        val encodedData = payload.optString("data", "")
        if (encodedData.isEmpty()) return
        if (!validContentType(contentType)) return
        val data = try { Base64.decode(encodedData, Base64.DEFAULT) } catch (_:Exception) { return }
        synchronized(incomingFiles) {
            if (incomingFiles.size >= DirectFileTransferPolicy.MAX_ACTIVE_INCOMING_TRANSFERS && !incomingFiles.containsKey(transferId)) return
            if (transferId.isNotEmpty() && size >= 0L) {
                val activeBytes=DirectFileTransferPolicy.activeBytes(incomingFiles.values.map{it.size})
                if (!incomingFiles.containsKey(transferId) && activeBytes > DirectFileTransferPolicy.MAX_ACTIVE_TRANSFER_BYTES-size) return
            }
            val stale = incomingFiles.values.filter { System.currentTimeMillis() - it.updatedAt > 5 * 60 * 1000L }
            stale.forEach { staleTransfer ->
                try { staleTransfer.file.close() } catch (_: Exception) {}
                try { File(staleTransfer.path).delete() } catch (_: Exception) {}
                incomingFiles.remove(staleTransfer.transferId)
            }
            val expectedChunks = try { DirectFileTransferPolicy.expectedChunks(size) } catch (_: Exception) { return }
            if (totalChunks != expectedChunks) return
            val offset = index.toLong() * directChunkSize
            val maxChunk = (size - offset).coerceAtLeast(0L).coerceAtMost(directChunkSize.toLong())
            if (size == 0L && (index != 0 || data.isNotEmpty())) return
            if (size > 0L && (offset < 0L || offset >= size || data.isEmpty() || data.size.toLong() > maxChunk || offset + data.size > size)) return
            if (isCompletedTransfer(transferId, sha)) return
            val transfer = incomingFiles[transferId] ?: createIncomingTransfer(transferId, fileId, messageId, originSenderId, fileName, contentType, size, sha, totalChunks)
            if (transfer.senderId != originSenderId || transfer.fileId != fileId || transfer.messageId != messageId || transfer.fileName != fileName || transfer.contentType != contentType || transfer.totalChunks != totalChunks || transfer.size != size || transfer.sha256 != sha) return
            if (transfer.received[index]) {
                transfer.updatedAt = System.currentTimeMillis()
                persistIncomingTransfer(transfer)
                sendRoutedPayload(originSenderId,JSONObject().put("type","direct_file_progress").put("sender_id",self).put("recipient_id",originSenderId).put("transfer_id",transferId).put("sha256",sha).put("received_chunks",bitsetEncode(transfer.received)).put("total_chunks",totalChunks))
                return
            }
            try {
                transfer.file.seek(offset)
                transfer.file.write(data)
                transfer.file.fd.sync()
                transfer.received[index]=true;transfer.updatedAt=System.currentTimeMillis();persistIncomingTransfer(transfer);val receivedCount=transfer.received.count{it};sendRoutedPayload(originSenderId,JSONObject().put("type","direct_file_progress").put("sender_id",self).put("recipient_id",originSenderId).put("transfer_id",transferId).put("sha256",sha).put("received_chunks",bitsetEncode(transfer.received)).put("total_chunks",totalChunks))
                transportEvent("file_progress", mapOf("transfer_id" to transferId, "message_id" to messageId, "received" to receivedCount, "total_chunks" to totalChunks, "bytes" to transfer.file.length(), "total" to size))
                if (receivedCount != totalChunks) return
                transfer.file.fd.sync()
                transfer.file.close()
                val actual = File(transfer.path)
                if (actual.length() != size || sha256File(actual) != sha) {
                    actual.delete()
                    incomingFiles.remove(transferId)
                    return
                }
                val finalDir = File(filesDir, "locallink_direct_files").apply { mkdirs() }
                val finalFile = File(finalDir, "${transferId}_${safeFileName(fileName)}")
                if (finalFile.exists()) finalFile.delete()
                if (!actual.renameTo(finalFile)) {
                    actual.copyTo(finalFile, overwrite = true)
                    actual.delete()
                }
                incomingFiles.remove(transferId);deleteIncomingMeta(transfer);File(finalDir,".done_${transferId}_${sha}").writeText("ok",Charsets.UTF_8)
                transportEvent("file_received", mapOf(
                    "transfer_id" to transferId, "message_id" to messageId, "file_id" to fileId,
                    "sender_id" to originSenderId, "recipient_id" to self, "file_name" to fileName,
                    "content_type" to contentType, "size" to size, "sha256" to sha, "path" to finalFile.absolutePath
                ))
                sendRoutedPayload(originSenderId, JSONObject().put("type", "direct_file_ack").put("sender_id", self).put("recipient_id", originSenderId).put("transfer_id", transferId).put("file_id", fileId).put("message_id", messageId).put("sha256", sha))
            } catch (_: Exception) {
                try { transfer.file.close() } catch (_: Exception) {}
                incomingFiles.remove(transferId)
            }
        }
    }

    private fun isCompletedTransfer(transferId: String, sha256: String): Boolean {
        val dir = File(filesDir, "locallink_direct_files")
        if (!dir.exists()) return false
        return dir.listFiles { file -> file.name.startsWith(".done_${transferId}_") && file.name.endsWith(sha256) }?.isNotEmpty() == true
    }

    private fun createIncomingTransfer(transferId:String,fileId:String,messageId:String,senderId:String,fileName:String,contentType:String,size:Long,sha256:String,totalChunks:Int):IncomingFileTransfer{
        incomingFiles[transferId]?.let{return it};val dir=File(filesDir,"locallink_direct_files").apply{mkdirs()};val part=File(dir,"$transferId.part");val meta=File(dir,"$transferId.meta.json")
        if(meta.exists()&&part.exists())try{val j=JSONObject(meta.readText());if(j.optString("sha256")==sha256&&j.optString("sender_id")==senderId){val t=IncomingFileTransfer(transferId,fileId,messageId,senderId,fileName,contentType,size,sha256,totalChunks,part.absolutePath,RandomAccessFile(part,"rw"),bitsetDecode(j.optString("received"),totalChunks),j.optLong("updated_at",System.currentTimeMillis()));incomingFiles[transferId]=t;return t}}catch(_:Exception){}
        val raf=RandomAccessFile(part,"rw");if(size>0&&raf.length()!=size)raf.setLength(size);val t=IncomingFileTransfer(transferId,fileId,messageId,senderId,fileName,contentType,size,sha256,totalChunks,part.absolutePath,raf,BooleanArray(totalChunks),System.currentTimeMillis());incomingFiles[transferId]=t;persistIncomingTransfer(t);return t
    }

    private fun validTransportId(value: String): Boolean {
        return value.length in 1..128 && value.none { it.isISOControl() || it == '/' || it == '\\' }
    }

    private fun validFileTransferId(value: String): Boolean {
        if (value.length !in 2..128) return false
        for ((index, ch) in value.withIndex()) {
            val allowed = ch.isLetterOrDigit() || ch == '_' || ch == '-' || ch == '.'
            if (!allowed || (index == 0 && ch == '.')) return false
        }
        return value != "." && value != ".."
    }

    private fun validContentType(value: String): Boolean {
        if (value.isBlank() || value.length > 256) return false
        return value.none { it.isISOControl() || it == '|' }
    }

    private fun safeFileName(name: String): String {
        val clean = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return clean.take(160).ifEmpty { "attachment" }
    }

    private fun encryptPacket(payload: JSONObject, key: String, senderId: String, receiverId: String, hopAad: ByteArray, keyEpoch: Long): String {
        val keyBytes = MeshTransportSessionKeyPolicy.deriveKey(
            sharedKey = key,
            senderNodeId = senderId,
            receiverNodeId = receiverId,
            epoch = keyEpoch,
        )
        val iv = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(128, iv))
        cipher.updateAAD(hopAad)
        val encrypted = cipher.doFinal(payload.toString().toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv + encrypted, Base64.NO_WRAP)
    }

    /**
     * Per-hop authenticated decryption. The outer sender/receiver identities
     * are authenticated as AEAD associated data, while the complete canonical
     * MeshPacket envelope is covered by AES-GCM as ciphertext.
     */
    private fun decryptPacket(encoded: String, key: String, senderId: String, receiverId: String, keyEpoch: Long): JSONObject? {
        return try {
            val all = Base64.decode(encoded, Base64.DEFAULT)
            if (all.size < 13) return null
            val iv = all.copyOfRange(0, 12)
            val ciphertext = all.copyOfRange(12, all.size)
            val keyBytes = MeshTransportSessionKeyPolicy.deriveKey(key, senderId, receiverId, keyEpoch)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(128, iv))
            cipher.updateAAD(MeshPacketAuthentication.hopIdentityAad(senderId, receiverId, keyEpoch))
            JSONObject(String(cipher.doFinal(ciphertext), Charsets.UTF_8))
        } catch (_: Exception) { null }
    }

    private fun derivedKey(key: String, label: String): ByteArray =
        MessageDigestDigest.sha256("$label|$key".toByteArray(Charsets.UTF_8))

    private fun hmac(key: String, input: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(derivedKey(key, "locallink-hop-hmac-v1"), "HmacSHA256"))
        return mac.doFinal(input.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun transportEvent(type: String, data: Map<String, Any?> = emptyMap()) {
        listener?.onTransportEvent(type, mapOf("type" to type, *data.entries.map { it.key to it.value }.toTypedArray()))
    }

    private fun unregisterPeer(peerId: String, socket: Socket) {
        val links = peerLinks[peerId]
        val currentLink = links?.entries?.firstOrNull { it.value.socket === socket }?.value
        if (currentLink == null) {
            // A stale connection must never tear down a newer connection for the same node.
            try { socket.close() } catch (_: Exception) {}
            return
        }
        links.remove(currentLink.transportName, currentLink)
        if (links.isEmpty()) peerLinks.remove(peerId, links)
        val previousActive = transportPeers[peerId]
        val active = recomputeActivePeer(peerId)
        if (active != null) {
            meshPeers.connected(peerId, active.transportName)
            meshPeers.available(peerId, active.transportName)
            if (previousActive?.socket === socket || previousActive?.transportName != active.transportName) {
                transportEvent("peer_transport_fallback", mapOf(
                    "peer_id" to peerId,
                    "previous_transport" to previousActive?.transportName,
                    "transport" to active.transportName,
                    "reason" to "physical_link_failed",
                ))
            }
            transportEvent("topology", meshTopologySnapshot())
            try { socket.close() } catch (_: Exception) {}
            return
        }
        transportPeers.remove(peerId)
        meshPeers.disconnected(peerId, currentLink.transportName)
        handleRoutesAfterPeerDisconnect(peerId, "peer_disconnected")
        transportEvent("topology", meshTopologySnapshot())
        try { socket.close() } catch (_: Exception) {}
    }

    /** Invalidates routes using a lost direct peer and starts recovery immediately. */
    private fun handleRoutesAfterPeerDisconnect(peerId: String, reason: String) {
        if (!validTransportId(peerId)) return
        val now = System.currentTimeMillis()
        val affectedRoutes = routeTable.removeVia(peerId)
        val recoveryDestinations = routeRecovery.markPeerLost(peerId, affectedRoutes, now)
        affectedRoutes.forEach { destination ->
            transportEvent("route_invalidated", mapOf(
                "destination_id" to destination,
                "failed_next_hop" to peerId,
                "reason" to reason,
            ))
            val replacement = routeTable[destination]
            if (replacement != null && replacement.nextHopNodeId != peerId) {
                routeRecovery.markRecovered(destination)
                transportEvent("route_recovered", mapOf(
                    "destination_id" to destination,
                    "previous_next_hop" to peerId,
                    "next_hop_id" to replacement.nextHopNodeId,
                    "hop_count" to replacement.hopCount,
                    "reason" to "alternate_route_after_disconnect",
                ))
            } else {
                transportEvent("route_recovery_started", mapOf(
                    "destination_id" to destination,
                    "failed_next_hop" to peerId,
                    "reason" to reason,
                ))
            }
        }
        if (recoveryDestinations.isNotEmpty()) {
            broadcastRouteWithdrawal(peerId, recoveryDestinations)
            broadcastRouteAdvertisement(excludePeerId = peerId)
            // Never call flushMeshQueue synchronously from send/receive paths; a send failure
            // may already hold meshFlushLock. Serialize the retry on a separate worker.
            Thread { flushMeshQueue() }.start()
        }
    }


    private fun broadcastRouteWithdrawal(failedNextHopId: String, destinations: Collection<String>) {
        if (destinations.isEmpty()) return
        val self = transportDeviceId ?: return
        val list = JSONArray()
        destinations.filter { validTransportId(it) }.distinct().take(128).forEach { list.put(it) }
        if (list.length() == 0) return
        val base = JSONObject()
            .put("type", "route_withdrawal")
            .put("sender_id", self)
            .put("session_id", routeAdvertisementSessionId)
            .put("control_sequence", routeAdvertisementSequence.incrementAndGet())
            .put("sent_at", System.currentTimeMillis())
            .put("failed_next_hop", failedNextHopId)
            .put("destinations", list)
        for ((peerId, peer) in transportPeers) {
            if (peer.socket.isClosed) continue
            val key = peerKeys[peerId] ?: continue
            val message = com.sajjad.locallink.mesh.MeshRouteAdvertisementAuthenticator.withAuth(base, key)
            try { peer.send(message) } catch (_: Exception) {
                transportSendFailures.incrementAndGet()
            }
        }
    }

    private fun stopWifiDirectSockets() {
        closePeerLinksForTransport(MeshTransportPolicy.WIFI_DIRECT)
        try { transportServer?.close() } catch (_: Exception) {}
        transportServer = null
    }

    private fun stopTransportSockets() {
        allPhysicalPeerLinks().forEach { try { it.socket.close() } catch (_: Exception) {} }
        peerLinks.clear()
        try { lanServer?.close() } catch (_: Exception) {}
        lanServer = null
        try { lanDiscoverySocket?.close() } catch (_: Exception) {}
        lanDiscoverySocket = null
        releaseLanMulticastLock()
        lanDiscoveryThread?.interrupt()
        lanDiscoveryThread = null
        lanEndpoints.clear()
        lastLanBeaconAt.clear()
        routeAdvertisementLastSentAt.set(0L)
        routeAdvertisementPolicy.clear()
        routeStabilityPolicy.clear()
        lanConnectInFlight.clear()
        meshPeers.clear()
        incomingFiles.values.forEach { try { it.file.close() } catch (_: Exception) {} }
        incomingFiles.clear()
        transportPeers.clear();peerLinks.clear();routeTable.clear()
        try { transportServer?.close() } catch (_: Exception) {}
        transportServer = null
    }


    private data class IncomingFileTransfer(
        val transferId: String,
        val fileId: String,
        val messageId: String,
        val senderId: String,
        val fileName: String,
        val contentType: String,
        val size: Long,
        val sha256: String,
        val totalChunks: Int,
        val path: String,
        val file: RandomAccessFile,
        val received: BooleanArray,
        var updatedAt: Long,
    )

    private data class LanEndpoint(
        val host: String,
        val port: Int,
        val lastSeenAt: Long,
    )

    private data class PeerConnection(
        val peerId: String,
        val socket: Socket,
        val ownerAddress: String?,
        val reader: BufferedReader,
        val writer: BufferedWriter,
        val transportName: String = MeshTransportPolicy.WIFI_DIRECT,
        val remoteAddress: String? = null,
        val connectedAt: Long = System.currentTimeMillis(),
        @Volatile var lastSeenAt: Long = connectedAt,
        @Volatile var lastPongAt: Long = connectedAt,
        @Volatile var lastPingAt: Long = 0L,
    ) {
        @Synchronized fun send(json: JSONObject) {
            writer.write(json.toString())
            writer.newLine()
            writer.flush()
        }
    }

    private object MessageDigestDigest {
        fun sha256(input: ByteArray): ByteArray = java.security.MessageDigest.getInstance("SHA-256").digest(input)
    }
    private data class OutgoingFileTransfer(val transferId:String,val fileId:String,val messageId:String,val senderId:String,val recipientId:String,val filePath:String,val fileName:String,val contentType:String,val size:Long,val sha256:String,val totalChunks:Int,val acknowledged:BooleanArray,var updatedAt:Long)

    private fun stopTransportExplicit(){stopCallMediaInternal("");transportRunning=false;meshMaintenanceThread?.interrupt();meshMaintenanceThread=null;stopTransportSockets();transportGroupOwner=false;transportGroupOwnerAddress=null;ownerConnectInFlight.set(false);routeTable.clear();routeRecovery.clear();persistState();transportEvent("state",mapOf("connected" to false,"transport_active" to false,"service" to "stopped"))}

    private fun createStateKey():javax.crypto.SecretKey{val ks=KeyStore.getInstance("AndroidKeyStore").apply{load(null)};if(!ks.containsAlias(STATE_KEY_ALIAS)){val g=javax.crypto.KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");g.init(KeyGenParameterSpec.Builder(STATE_KEY_ALIAS,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setUserAuthenticationRequired(false).build());g.generateKey()};return ks.getKey(STATE_KEY_ALIAS,null) as javax.crypto.SecretKey}
    private fun persistState(){try{val j=JSONObject().put("active",transportRunning).put("device_id",transportDeviceId).put("group_owner",transportGroupOwner).put("group_owner_address",transportGroupOwnerAddress);val k=JSONObject();peerKeys.forEach{(a,b)->k.put(a,b)};j.put("peer_keys",k);val iv=ByteArray(12).also(random::nextBytes);val c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,createStateKey(),GCMParameterSpec(128,iv));getSharedPreferences(PREFS,MODE_PRIVATE).edit().putString(STATE_BLOB,Base64.encodeToString(iv+c.doFinal(j.toString().toByteArray(Charsets.UTF_8)),Base64.NO_WRAP)).apply()}catch(_:Exception){}}
    private fun loadPersistedState(){try{val b=getSharedPreferences(PREFS,MODE_PRIVATE).getString(STATE_BLOB,null)?:return;val a=Base64.decode(b,Base64.DEFAULT);if(a.size<28)return;val c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,createStateKey(),GCMParameterSpec(128,a.copyOfRange(0,12)));val j=JSONObject(String(c.doFinal(a.copyOfRange(12,a.size)),Charsets.UTF_8));transportRunning=j.optBoolean("active",false);transportDeviceId=j.optString("device_id").takeIf{it.isNotBlank()};transportGroupOwner=j.optBoolean("group_owner",false);transportGroupOwnerAddress=j.optString("group_owner_address").takeIf{it.isNotBlank()};peerKeys.clear();j.optJSONObject("peer_keys")?.let{k->val it=k.keys();while(it.hasNext()){val id=it.next();val v=k.optString(id);if(validTransportId(id)&&v.isNotBlank())peerKeys[id]=v}}}catch(_:Exception){}}
    private fun restoreDurableState(){loadSeenMeshPackets();restoreIncomingTransfers();restoreOutgoingTransfers()}
    private fun seenFileFor(key:String)=File(seenMeshDir,Base64.encodeToString(key.toByteArray(),Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)+".seen")
    private fun loadSeenMeshPackets(){
        val now=System.currentTimeMillis()
        seenMeshDir.listFiles()?.forEach{f->
            if(now-f.lastModified()>MeshLimits.SEEN_RETENTION_MS){f.delete();return@forEach}
            try{
                val key=String(Base64.decode(f.name.removeSuffix(".seen"),Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING))
                val separator=key.indexOf('\u0000')
                if(separator>0 && separator<key.length-1){
                    val source=key.substring(0,separator)
                    val packet=key.substring(separator+1)
                    if (!seenMeshPackets.restore(source,packet,f.lastModified(),now)) f.delete()
                } else {
                    // Packet-only replay records from pre-AUDIT-003 builds are obsolete because
                    // legacy wire packets are now rejected. Delete them instead of reintroducing
                    // a legacy compatibility path.
                    f.delete()
                }
            }catch(_:Exception){f.delete()}
        }
    }
    private fun persistSeenMeshPacket(sourceNodeId:String,packetId:String,now:Long){
        try{
            val key=seenMeshPackets.keyFor(sourceNodeId,packetId)
            val f=seenFileFor(key)
            if(!f.exists())f.writeText("$now")
            f.setLastModified(now)
        }catch(_:Exception){}
    }
    private fun deleteSeenMeshPacketRecord(key:String, evictedAt:Long){
        try {
            val file = seenFileFor(key)
            if (file.exists() && file.lastModified() <= evictedAt) file.delete()
        } catch (_:Exception) {}
    }
    private fun bitsetEncode(bits:BooleanArray):String{val b=ByteArray((bits.size+7)/8);bits.forEachIndexed{i,v->if(v)b[i/8]=(b[i/8].toInt() or (1 shl i%8)).toByte()};return Base64.encodeToString(b,Base64.NO_WRAP)}
    private fun bitsetDecode(s:String,total:Int):BooleanArray{
        val o=BooleanArray(total)
        try{
            if(total<0) return o
            val b=Base64.decode(s,Base64.DEFAULT)
            val expected=(total+7)/8
            if(b.size!=expected) return o
            for(i in 0 until total) o[i]=(b[i/8].toInt() and (1 shl i%8))!=0
        }catch(_:Exception){}
        return o
    }
    private fun outgoingMetaFile(id:String)=File(filesDir,"locallink_direct_files/$id.out.json")
    private fun atomicWriteText(target: File, text: String) {
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, target.name + ".tmp")
        java.io.FileOutputStream(temp).use { out ->
            out.write(text.toByteArray(Charsets.UTF_8))
            out.flush()
            out.fd.sync()
        }
        if (!temp.renameTo(target)) {
            temp.delete()
            throw IllegalStateException("failed to commit transfer metadata")
        }
    }

    private fun persistOutgoingTransfer(t:OutgoingFileTransfer){
        atomicWriteText(outgoingMetaFile(t.transferId), JSONObject().put("transfer_id",t.transferId).put("file_id",t.fileId).put("message_id",t.messageId).put("sender_id",t.senderId).put("recipient_id",t.recipientId).put("file_path",t.filePath).put("file_name",t.fileName).put("content_type",t.contentType).put("size",t.size).put("sha256",t.sha256).put("total_chunks",t.totalChunks).put("acknowledged",bitsetEncode(t.acknowledged)).put("updated_at",t.updatedAt).toString())
}
    private fun deleteOutgoingMeta(t:OutgoingFileTransfer){try{outgoingMetaFile(t.transferId).delete()}catch(_:Exception){}}
    private fun restoreOutgoingTransfers(){
        val d=File(filesDir,"locallink_direct_files").apply{mkdirs()}
        val now=System.currentTimeMillis()
        d.listFiles{f->f.name.endsWith(".out.json")}?.forEach{f->try{
            val j=JSONObject(f.readText())
            val total=j.optInt("total_chunks")
            val transferId=j.optString("transfer_id")
            val fileId=j.optString("file_id")
            val messageId=j.optString("message_id")
            val senderId=j.optString("sender_id")
            val recipientId=j.optString("recipient_id")
            val size=j.optLong("size",-1)
            val sha=j.optString("sha256").lowercase()
            val updatedAt=j.optLong("updated_at",f.lastModified())
            if(!validFileTransferId(transferId) || !validFileTransferId(fileId) || !validFileTransferId(messageId) ||
                !validTransportId(senderId) || !validTransportId(recipientId) ||
                !DirectFileTransferPolicy.validTransferSize(size) || sha.length!=64 ||
                total != DirectFileTransferPolicy.expectedChunks(size) ||
                now-updatedAt>DirectFileTransferPolicy.IDLE_TIMEOUT_MS){f.delete();return@forEach}
            if(outgoingTransfers.size>=DirectFileTransferPolicy.MAX_ACTIVE_OUTGOING_TRANSFERS ||
                DirectFileTransferPolicy.activeBytes(outgoingTransfers.values.map{it.size}) > DirectFileTransferPolicy.MAX_ACTIVE_TRANSFER_BYTES-size){return@forEach}
            val source=File(j.optString("file_path"))
            if(!source.isFile || source.length()!=size || sha256File(source)!=sha){f.delete();return@forEach}
            val t=OutgoingFileTransfer(transferId,fileId,messageId,senderId,recipientId,source.absolutePath,safeFileName(j.optString("file_name")),j.optString("content_type","application/octet-stream"),size,sha,total,bitsetDecode(j.optString("acknowledged"),total),updatedAt)
            outgoingTransfers[t.transferId]=t
        }catch(_:Exception){f.delete()}}
    }

    private fun persistIncomingTransfer(t:IncomingFileTransfer){
        val m=File(t.path.removeSuffix(".part")+".meta.json")
        atomicWriteText(m, JSONObject().put("transfer_id",t.transferId).put("file_id",t.fileId).put("message_id",t.messageId).put("sender_id",t.senderId).put("file_name",t.fileName).put("content_type",t.contentType).put("size",t.size).put("sha256",t.sha256).put("total_chunks",t.totalChunks).put("path",t.path).put("received",bitsetEncode(t.received)).put("updated_at",t.updatedAt).toString())
}
    private fun deleteIncomingMeta(t:IncomingFileTransfer){try{File(t.path.removeSuffix(".part")+".meta.json").delete()}catch(_:Exception){}}
    private fun isInsideDirectory(file: File, directory: File): Boolean {
        return try {
            val root = directory.canonicalFile
            val candidate = file.canonicalFile
            candidate.path == root.path || candidate.path.startsWith(root.path + File.separator)
        } catch (_: Exception) { false }
    }

    private fun restoreIncomingTransfers(){
        val d=File(filesDir,"locallink_direct_files").apply{mkdirs()}
        d.listFiles{f->f.name.endsWith(".meta.json")}?.forEach{f->try{
            val j=JSONObject(f.readText())
            val total=j.optInt("total_chunks")
            val transferId=j.optString("transfer_id")
            val fileId=j.optString("file_id")
            val messageId=j.optString("message_id")
            val senderId=j.optString("sender_id")
            val size=j.optLong("size",-1)
            val sha=j.optString("sha256").lowercase()
            if(!validFileTransferId(transferId) || !validFileTransferId(fileId) || !validFileTransferId(messageId) ||
                !validTransportId(senderId) || !DirectFileTransferPolicy.validTransferSize(size) || sha.length!=64 ||
                total != DirectFileTransferPolicy.expectedChunks(size)) { f.delete(); return@forEach }
            val part=File(j.optString("path"))
            if(!isInsideDirectory(part,d) || !part.isFile || part.length()!=size){f.delete();try{part.delete()}catch(_:Exception){};return@forEach}
            if(incomingFiles.size>=DirectFileTransferPolicy.MAX_ACTIVE_INCOMING_TRANSFERS ||
                DirectFileTransferPolicy.activeBytes(incomingFiles.values.map{it.size}) > DirectFileTransferPolicy.MAX_ACTIVE_TRANSFER_BYTES-size){return@forEach}
            val t=IncomingFileTransfer(transferId,fileId,messageId,senderId,safeFileName(j.optString("file_name")),j.optString("content_type","application/octet-stream"),size,sha,total,part.absolutePath,RandomAccessFile(part,"rw"),bitsetDecode(j.optString("received"),total),j.optLong("updated_at",f.lastModified()))
            incomingFiles[t.transferId]=t
        }catch(_:Exception){f.delete()}}
    }

    private fun prepareOutgoingTransfer(target:String,file:File,fileId:String,messageId:String,fileName:String,contentType:String):OutgoingFileTransfer{
        val existing=outgoingTransfers[fileId]
        if(existing!=null&&existing.recipientId==target&&existing.filePath==file.absolutePath&&existing.sha256==sha256File(file))return existing
        val sha=sha256File(file)
        val size=file.length()
        val total=DirectFileTransferPolicy.expectedChunks(size)
        val t=OutgoingFileTransfer(fileId,fileId,messageId,transportDeviceId!!,target,file.absolutePath,safeFileName(fileName),contentType,size,sha,total,BooleanArray(total),System.currentTimeMillis())
        outgoingTransfers[fileId]=t
        cancelledDirectTransfers.remove(t.transferId)
        outgoingRetryCounts.remove(t.transferId)
        return t
    }
    private fun missingChunkCount(t:OutgoingFileTransfer)=t.acknowledged.count{!it}
    private fun sendMissingChunks(t:OutgoingFileTransfer,onlyMissing:Boolean){
        if(!outgoingSendInFlight.add(t.transferId)) return
        try {
            if(cancelledDirectTransfers.contains(t.transferId)){
                deleteOutgoingMeta(t);outgoingTransfers.remove(t.transferId);outgoingRetryCounts.remove(t.transferId);cancelledDirectTransfers.remove(t.transferId)
                transportEvent("file_cancelled",mapOf("transfer_id" to t.transferId,"message_id" to t.messageId,"file_id" to t.fileId));return
            }
            val f=File(t.filePath)
            if(!f.isFile||f.length()!=t.size||sha256File(f)!=t.sha256){
                deleteOutgoingMeta(t);outgoingTransfers.remove(t.transferId);outgoingRetryCounts.remove(t.transferId)
                transportEvent("file_failed",mapOf("transfer_id" to t.transferId,"message_id" to t.messageId,"reason" to "source_changed_or_missing"));return
            }
            val attempt=outgoingRetryCounts.merge(t.transferId,1,Int::plus) ?: 1
            if(attempt>DirectFileTransferPolicy.MAX_RETRY_ATTEMPTS){
                deleteOutgoingMeta(t);outgoingTransfers.remove(t.transferId);outgoingRetryCounts.remove(t.transferId)
                transportEvent("file_failed",mapOf("transfer_id" to t.transferId,"message_id" to t.messageId,"reason" to "retry_limit_exceeded"));return
            }
            var sentAny=false
            FileInputStream(f).use{input->
                val buf=ByteArray(directChunkSize);var idx=0
                while(true){
                    if(cancelledDirectTransfers.contains(t.transferId)){cancelledDirectTransfers.remove(t.transferId);transportEvent("file_cancelled",mapOf("transfer_id" to t.transferId,"message_id" to t.messageId,"file_id" to t.fileId));return}
                    val n=input.read(buf);if(n<=0)break
                    if(onlyMissing&&t.acknowledged[idx]){idx++;continue}
                    val data=if(n==buf.size)buf else buf.copyOf(n)
                    val payload=JSONObject().put("type","direct_file_chunk").put("sender_id",t.senderId).put("recipient_id",t.recipientId).put("transfer_id",t.transferId).put("file_id",t.fileId).put("message_id",t.messageId).put("file_name",t.fileName).put("content_type",t.contentType).put("size",t.size).put("sha256",t.sha256).put("chunk_index",idx).put("total_chunks",t.totalChunks).put("data",Base64.encodeToString(data, Base64.NO_WRAP))
                    if(!sendRoutedPayload(t.recipientId,payload))break
                    sentAny=true;idx++
                }
            }
            if(t.size==0L&&!t.acknowledged[0]){
                val p=JSONObject().put("type","direct_file_chunk").put("sender_id",t.senderId).put("recipient_id",t.recipientId).put("transfer_id",t.transferId).put("file_id",t.fileId).put("message_id",t.messageId).put("file_name",t.fileName).put("content_type",t.contentType).put("size",0).put("sha256",t.sha256).put("chunk_index",0).put("total_chunks",1).put("data","");sendRoutedPayload(t.recipientId,p);sentAny=true
            }
            if(!sentAny) transportEvent("file_retry_scheduled",mapOf("transfer_id" to t.transferId,"attempt" to attempt))
            t.updatedAt=System.currentTimeMillis();persistOutgoingTransfer(t)
        } finally {
            outgoingSendInFlight.remove(t.transferId)
        }
    }

    private fun cancelFileTransportInternal(fileId:String){
        val id=fileId.trim()
        if(!validFileTransferId(id)) return
        cancelledDirectTransfers.add(id)
        val outgoing=outgoingTransfers.remove(id)
        if(outgoing!=null){
            deleteOutgoingMeta(outgoing)
            outgoingRetryCounts.remove(outgoing.transferId)
            outgoingSendInFlight.remove(outgoing.transferId)
            try { sendRoutedPayload(outgoing.recipientId,JSONObject().put("type","direct_file_cancel").put("sender_id",outgoing.senderId).put("recipient_id",outgoing.recipientId).put("transfer_id",outgoing.transferId).put("file_id",outgoing.fileId).put("message_id",outgoing.messageId).put("sha256",outgoing.sha256)) } catch (_:Exception) {}
        }
        val incoming=incomingFiles.remove(id)
        incoming?.let { try { it.file.close() } catch (_:Exception) {}; try { File(it.path).delete() } catch (_:Exception) {}; deleteIncomingMeta(it) }
        if(outgoing==null) cancelledDirectTransfers.remove(id)
        transportEvent("file_cancelled", mapOf("transfer_id" to id))
    }

    private fun handleFileCancel(p:JSONObject){
        val id=p.optString("transfer_id").trim()
        val self=transportDeviceId?:return
        if(!validFileTransferId(id)||p.optString("recipient_id")!=self) return
        val t=incomingFiles[id]?:return
        if(p.optString("sender_id")!=t.senderId||p.optString("file_id")!=t.fileId||p.optString("message_id")!=t.messageId||p.optString("sha256")!=t.sha256) return
        incomingFiles.remove(id)
        cancelledIncomingTransfers[id]=System.currentTimeMillis()+DirectFileTransferPolicy.IDLE_TIMEOUT_MS
        try{t.file.close()}catch(_:Exception){}
        try{File(t.path).delete()}catch(_:Exception){}
        deleteIncomingMeta(t)
        transportEvent("file_cancelled",mapOf("transfer_id" to id,"message_id" to t.messageId,"file_id" to t.fileId,"sender_id" to t.senderId,"recipient_id" to self))
    }

    private fun handleFileProgress(p:JSONObject){
        val id=p.optString("transfer_id")
        val t=outgoingTransfers[id]?:return
        if(p.optString("sender_id")!=t.recipientId||p.optString("sha256")!=t.sha256||p.optInt("total_chunks",-1)!=t.totalChunks)return
        val bits=bitsetDecode(p.optString("received_chunks"),t.totalChunks)
        for(i in bits.indices)if(bits[i])t.acknowledged[i]=true
        if(bits.any{it}) outgoingRetryCounts[t.transferId]=0
        t.updatedAt=System.currentTimeMillis()
        if(missingChunkCount(t)==0){deleteOutgoingMeta(t);outgoingTransfers.remove(id);outgoingRetryCounts.remove(id);outgoingSendInFlight.remove(id);transportEvent("file_sent",mapOf("transfer_id" to t.transferId,"message_id" to t.messageId,"file_id" to t.fileId,"size" to t.size,"sha256" to t.sha256))}
        else{persistOutgoingTransfer(t);transportEvent("file_progress",mapOf("transfer_id" to t.transferId,"message_id" to t.messageId,"acked_chunks" to t.totalChunks-missingChunkCount(t),"total_chunks" to t.totalChunks));Thread{sendMissingChunks(t,true)}.start()}
    }
    private fun handleFileResumeRequest(p:JSONObject){
        val id=p.optString("transfer_id")
        val t=incomingFiles[id]?:return
        if(p.optString("sender_id")!=t.senderId||p.optString("recipient_id")!=transportDeviceId||p.optString("sha256")!=t.sha256||p.optInt("total_chunks",-1)!=t.totalChunks)return
        sendRoutedPayload(t.senderId,JSONObject().put("type","direct_file_progress").put("sender_id",transportDeviceId).put("recipient_id",t.senderId).put("transfer_id",t.transferId).put("sha256",t.sha256).put("received_chunks",bitsetEncode(t.received)).put("total_chunks",t.totalChunks))
    }
    private fun sendResumeRequests(){for(t in outgoingTransfers.values.toList())try{sendRoutedPayload(t.recipientId,JSONObject().put("type","direct_file_resume_request").put("sender_id",transportDeviceId).put("recipient_id",t.recipientId).put("transfer_id",t.transferId).put("sha256",t.sha256).put("total_chunks",t.totalChunks))}catch(_:Exception){}}

    override fun onDestroy(){stopCallVideoInternal("");stopCallMediaInternal("");meshMaintenanceThread?.interrupt();meshMaintenanceThread=null;stopTransportSockets();running=false;if(instance===this)instance=null;super.onDestroy()}
}
