package com.smartmpc.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.Process
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

class AudioReceiverService : Service() {
    @Volatile private var audioRunning = false
    private var audioReceiverThread: Thread? = null
    private var audioPlaybackThread: Thread? = null
    private var audioSocket: DatagramSocket? = null
    private var audioTrack: AudioTrack? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopAudioReceiver()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val port = intent?.getIntExtra(EXTRA_PORT, AUDIO_PORT) ?: AUDIO_PORT
                startForeground(NOTIFICATION_ID, notification())
                startAudioReceiver(port)
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        stopAudioReceiver()
        super.onDestroy()
    }

    private fun startAudioReceiver(port: Int) {
        stopAudioReceiver()
        audioRunning = true
        acquireLocks()

        val minBuffer = AudioTrack.getMinBufferSize(
            AUDIO_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(AUDIO_SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(minBuffer)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()
        audioTrack = track
        track.play()
        val queue = ArrayBlockingQueue<ByteArray>(AUDIO_QUEUE_CAPACITY)

        audioReceiverThread = Thread {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            runCatching {
                val socket = DatagramSocket(port)
                audioSocket = socket
                val buffer = ByteArray(minBuffer * 2)
                val packet = DatagramPacket(buffer, buffer.size)
                while (audioRunning) {
                    socket.receive(packet)
                    val audioPacket = copyAudioPayload(packet) ?: continue
                    if (!queue.offer(audioPacket.pcm)) {
                        queue.poll()
                        queue.offer(audioPacket.pcm)
                    }
                }
            }
        }.apply {
            name = "smart-mpc-audio-receiver"
            isDaemon = true
            start()
        }

        audioPlaybackThread = Thread {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            var lastPcm: ByteArray? = null
            var concealedPackets = 0
            while (audioRunning) {
                val pcm = queue.poll(AUDIO_PACKET_MS, TimeUnit.MILLISECONDS)
                if (pcm == null) {
                    val fallback = lastPcm
                    if (fallback != null && concealedPackets < MAX_CONCEALED_PACKETS) {
                        writeAudio(track, softenedCopy(fallback), 0, fallback.size)
                        concealedPackets += 1
                    }
                } else {
                    lastPcm = pcm
                    concealedPackets = 0
                    writeAudio(track, pcm, 0, pcm.size)
                }
            }
        }.apply {
            name = "smart-mpc-audio-playback"
            isDaemon = true
            start()
        }
    }

    private data class AudioPacket(val pcm: ByteArray)

    private fun copyAudioPayload(packet: DatagramPacket): AudioPacket? {
        var offset = packet.offset
        var length = packet.length
        val data = packet.data
        if (length > AUDIO_HEADER_BYTES &&
            data[offset] == 'S'.code.toByte() &&
            data[offset + 1] == 'M'.code.toByte() &&
            data[offset + 2] == 'A'.code.toByte() &&
            data[offset + 3] == '1'.code.toByte()
        ) {
            offset += AUDIO_HEADER_BYTES
            length -= AUDIO_HEADER_BYTES
        }
        if (length <= 0) return null
        return AudioPacket(data.copyOfRange(offset, offset + length))
    }

    private fun softenedCopy(data: ByteArray): ByteArray {
        val copy = ByteArray(data.size)
        var index = 0
        while (index + 1 < data.size) {
            val sample = ((data[index + 1].toInt() shl 8) or (data[index].toInt() and 0xFF)).toShort()
            val softened = (sample * 0.72).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            copy[index] = (softened and 0xFF).toByte()
            copy[index + 1] = ((softened shr 8) and 0xFF).toByte()
            index += 2
        }
        return copy
    }

    private fun writeAudio(track: AudioTrack, data: ByteArray, offset: Int, length: Int): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            track.write(data, offset, length, AudioTrack.WRITE_BLOCKING)
        } else {
            track.write(data, offset, length)
        }
    }

    private fun stopAudioReceiver() {
        audioRunning = false
        audioSocket?.close()
        audioReceiverThread?.join(500)
        audioPlaybackThread?.join(500)
        releaseAudioResources()
    }

    private fun acquireLocks() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "SmartMPC:AudioStream",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val wifiMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
        } else {
            WifiManager.WIFI_MODE_FULL_HIGH_PERF
        }
        wifiLock = wifiManager.createWifiLock(wifiMode, "SmartMPC:AudioWifi").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseAudioResources() {
        audioSocket?.close()
        audioSocket = null
        try {
            audioTrack?.stop()
        } catch (_: IllegalStateException) {
        } finally {
            audioTrack?.release()
            audioTrack = null
        }
        audioReceiverThread = null
        audioPlaybackThread = null
        releaseLocks()
    }

    private fun releaseLocks() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        if (wifiLock?.isHeld == true) wifiLock?.release()
        wifiLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Smart MPC Audio",
            NotificationManager.IMPORTANCE_LOW,
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun notification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Smart MPC audio stream")
                .setContentText("Streaming PC audio")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            Notification.Builder(this)
                .setContentTitle("Smart MPC audio stream")
                .setContentText("Streaming PC audio")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    companion object {
        const val ACTION_START = "com.smartmpc.app.audio.START"
        const val ACTION_STOP = "com.smartmpc.app.audio.STOP"
        const val EXTRA_PORT = "port"
        private const val CHANNEL_ID = "smart_mpc_audio"
        private const val NOTIFICATION_ID = 38360
        private const val AUDIO_PORT = 8081
        private const val AUDIO_SAMPLE_RATE = 16000
        private const val AUDIO_HEADER_BYTES = 8
        private const val AUDIO_QUEUE_CAPACITY = 5
        private const val AUDIO_PACKET_MS = 16L
        private const val MAX_CONCEALED_PACKETS = 5
    }
}
