package com.smartmpc.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class WebRtcMediaService : Service() {
    private lateinit var mediaSession: MediaSession
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var isForeground = false
    private var isPlaying = true
    private var mediaTitle = DEFAULT_TITLE

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        mediaSession = MediaSession(this, MEDIA_SESSION_TAG).apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = dispatch(COMMAND_PLAY)

                override fun onPause() = dispatch(COMMAND_PAUSE)

                override fun onStop() {
                    dispatch(COMMAND_STOP)
                    stopSession()
                }
            })
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                mediaTitle = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { DEFAULT_TITLE }
                isPlaying = intent.getBooleanExtra(EXTRA_PLAYING, true)
                startSession()
            }

            ACTION_UPDATE -> {
                mediaTitle = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { mediaTitle }
                isPlaying = intent.getBooleanExtra(EXTRA_PLAYING, isPlaying)
                if (isForeground) updateSession() else stopSelf(startId)
            }

            ACTION_PLAY -> if (isForeground) dispatch(COMMAND_PLAY) else stopSelf(startId)
            ACTION_PAUSE -> if (isForeground) dispatch(COMMAND_PAUSE) else stopSelf(startId)
            ACTION_STOP -> {
                dispatch(COMMAND_STOP)
                stopSession()
            }

            else -> if (!isForeground) stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseLocks()
        mediaSession.isActive = false
        mediaSession.release()
        super.onDestroy()
    }

    private fun startSession() {
        acquireLocks()
        mediaSession.isActive = true
        updateMetadata()
        updatePlaybackState()
        startForeground(NOTIFICATION_ID, buildNotification())
        isForeground = true
    }

    private fun updateSession() {
        updateMetadata()
        updatePlaybackState()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun stopSession() {
        if (isForeground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            isForeground = false
        }
        releaseLocks()
        mediaSession.isActive = false
        stopSelf()
    }

    private fun dispatch(command: String) {
        WebRtcMediaCommandBridge.dispatch(command)
    }

    private fun updateMetadata() {
        mediaSession.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, mediaTitle)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, APP_NAME)
                .build(),
        )
    }

    private fun updatePlaybackState() {
        val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        mediaSession.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_STOP,
                )
                .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (isPlaying) 1f else 0f)
                .build(),
        )
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val toggleAction = if (isPlaying) ACTION_PAUSE else ACTION_PLAY
        val toggleIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val toggleLabel = if (isPlaying) "Pause" else "Play"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.drawable.ic_stat_smart_mpc)
            .setContentTitle(mediaTitle)
            .setContentText(if (isPlaying) "Streaming from PC" else "Stream paused")
            .setContentIntent(contentIntent)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setOnlyAlertOnce(true)
            .setOngoing(isPlaying)
            .addAction(
                Notification.Action.Builder(
                    toggleIcon,
                    toggleLabel,
                    servicePendingIntent(toggleAction, 1),
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    servicePendingIntent(ACTION_STOP, 2),
                ).build(),
            )
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1),
            )
            .build()
    }

    private fun servicePendingIntent(action: String, requestCode: Int): PendingIntent {
        return PendingIntent.getService(
            this,
            requestCode,
            Intent(this, WebRtcMediaService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "PC audio stream",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Playback controls for audio streamed from the PC"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(false)
            },
        )
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:webrtc-audio",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }

        if (wifiLock?.isHeld != true) {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifiManager.createWifiLock(mode, "$packageName:webrtc-audio").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wifiLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        wifiLock = null
    }

    companion object {
        const val ACTION_START = "com.smartmpc.app.webrtc.START"
        const val ACTION_UPDATE = "com.smartmpc.app.webrtc.UPDATE"
        const val ACTION_PLAY = "com.smartmpc.app.webrtc.PLAY"
        const val ACTION_PAUSE = "com.smartmpc.app.webrtc.PAUSE"
        const val ACTION_STOP = "com.smartmpc.app.webrtc.STOP"
        const val EXTRA_PLAYING = "playing"
        const val EXTRA_TITLE = "title"

        private const val COMMAND_PLAY = "play"
        private const val COMMAND_PAUSE = "pause"
        private const val COMMAND_STOP = "stop"
        private const val APP_NAME = "Smart MPC"
        private const val DEFAULT_TITLE = "PC Audio"
        private const val MEDIA_SESSION_TAG = "SmartMPCWebRtcAudio"
        private const val NOTIFICATION_CHANNEL_ID = "smart_mpc_webrtc_audio"
        private const val NOTIFICATION_ID = 7312
    }
}
