package com.smartmpc.app

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class MainActivity : FlutterActivity() {
    private val channelName = "smart_mpc/preferences"
    private var channel: MethodChannel? = null
    private var pendingUpload: UploadConfig? = null
    private var latestDeepLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        latestDeepLink = deepLinkFrom(intent)
        super.onCreate(savedInstanceState)
    }

    override fun getRenderMode(): RenderMode {
        return RenderMode.texture
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("smart_mpc", MODE_PRIVATE)

                when (call.method) {
                    "loadConfig" -> {
                        result.success(
                            mapOf(
                                "baseUrl" to prefs.getString("baseUrl", ""),
                                "pairingToken" to prefs.getString("pairingToken", ""),
                                "deviceId" to prefs.getString("deviceId", ""),
                                "deviceToken" to prefs.getString("deviceToken", ""),
                                "pcId" to prefs.getString("pcId", ""),
                                "quickAction" to prefs.getString("quickAction", "send_file"),
                                "deviceName" to readableDeviceName()
                            )
                        )
                    }
                    "saveConfig" -> {
                        val args = call.arguments as Map<*, *>
                        prefs.edit()
                            .putString("baseUrl", args["baseUrl"] as? String ?: "")
                            .putString("pairingToken", args["pairingToken"] as? String ?: "")
                            .putString("deviceId", args["deviceId"] as? String ?: "")
                            .putString("deviceToken", args["deviceToken"] as? String ?: "")
                            .putString("pcId", args["pcId"] as? String ?: "")
                            .putString("quickAction", args["quickAction"] as? String ?: "send_file")
                            .apply()
                        result.success(true)
                    }
                    "clearConfig" -> {
                        prefs.edit().clear().apply()
                        result.success(true)
                    }
                    "pickAndUploadFiles" -> {
                        val args = call.arguments as Map<*, *>
                        pendingUpload = UploadConfig(
                            baseUrl = args["baseUrl"] as? String ?: "",
                            deviceId = args["deviceId"] as? String ?: "",
                            deviceToken = args["deviceToken"] as? String ?: "",
                        )
                        openFilePicker()
                        result.success(true)
                    }
                    "downloadToDownloads" -> {
                        val args = call.arguments as Map<*, *>
                        val downloadId = downloadToDownloads(
                            url = args["url"] as? String ?: "",
                            filename = args["filename"] as? String ?: "smart-mpc-file",
                            deviceId = args["deviceId"] as? String ?: "",
                            deviceToken = args["deviceToken"] as? String ?: "",
                        )
                        result.success(downloadId)
                    }
                    "consumeInitialDeepLink" -> {
                        val link = latestDeepLink ?: prefs.getString(NfcLaunchActivity.PREF_PENDING_DEEP_LINK, null)
                        latestDeepLink = null
                        if (link != null) {
                            prefs.edit().remove(NfcLaunchActivity.PREF_PENDING_DEEP_LINK).apply()
                        }
                        result.success(link)
                    }
                    "runTapAction" -> {
                        startActivity(Intent(this, NfcLaunchActivity::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val link = deepLinkFrom(intent) ?: return
        latestDeepLink = link
        channel?.invokeMethod("deepLink", link)
    }

    private fun deepLinkFrom(intent: Intent?): String? {
        return intent?.getStringExtra(NfcLaunchActivity.EXTRA_DEEP_LINK) ?: intent?.dataString
    }

    private fun readableDeviceName(): String {
        val manufacturer = Build.MANUFACTURER.trim()
        val model = Build.MODEL.trim()
        return if (model.lowercase().startsWith(manufacturer.lowercase())) {
            model
        } else {
            "$manufacturer $model"
        }
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(intent, REQUEST_PICK_FILES)
    }

    @Deprecated("Deprecated in Android API, still fine for this simple bridge.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FILES) return

        val config = pendingUpload
        pendingUpload = null

        if (resultCode != RESULT_OK || data == null || config == null) {
            channel?.invokeMethod("nativeStatus", "File selection cancelled")
            return
        }

        val uris = selectedUris(data)
        if (uris.isEmpty()) {
            channel?.invokeMethod("nativeStatus", "No file selected")
            return
        }

        Thread {
            val message = runCatching {
                uploadFiles(config, uris)
                "${uris.size} file(s) sent to PC"
            }.getOrElse { error ->
                "File upload failed: ${error.message ?: "unknown error"}"
            }
            runOnUiThread {
                channel?.invokeMethod("nativeStatus", message)
            }
        }.start()
    }

    private fun selectedUris(data: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        val clipData = data.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let { uris.add(it) }
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        return uris
    }

    private fun uploadFiles(config: UploadConfig, uris: List<Uri>) {
        if (config.baseUrl.isBlank() || config.deviceId.isBlank() || config.deviceToken.isBlank()) {
            throw IllegalStateException("Missing trusted PC config")
        }

        for (uri in uris) {
            uploadFile(config, uri)
        }
    }

    private fun uploadFile(config: UploadConfig, uri: Uri) {
        val filename = fileName(uri)
        val encodedName = URLEncoder.encode(filename, Charsets.UTF_8.name())
        val connection = URL("${config.baseUrl.trimEnd('/')}/api/files?filename=$encodedName")
            .openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 5000
        connection.readTimeout = 60000
        connection.doOutput = true
        connection.setChunkedStreamingMode(0)
        connection.setRequestProperty("Content-Type", "application/octet-stream")
        connection.setRequestProperty("X-Device-Id", config.deviceId)
        connection.setRequestProperty("X-Device-Token", config.deviceToken)

        contentResolver.openInputStream(uri)?.use { input ->
            connection.outputStream.use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Cannot read selected file")

        val responseCode = connection.responseCode
        val responseStream = if (responseCode in 200..299) connection.inputStream else connection.errorStream
        val responseText = responseStream?.bufferedReader()?.use { it.readText() }.orEmpty()
        if (responseCode !in 200..299) throw IllegalStateException("HTTP $responseCode")

        val response = JSONObject(responseText)
        if (!response.optBoolean("ok", false)) {
            throw IllegalStateException(response.optString("error", "Upload failed"))
        }
    }

    private fun fileName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = cursor.getString(index)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        return "upload-${System.currentTimeMillis()}"
    }

    private fun downloadToDownloads(
        url: String,
        filename: String,
        deviceId: String,
        deviceToken: String,
    ): Long {
        if (url.isBlank()) throw IllegalArgumentException("Missing download URL")
        if (deviceId.isBlank() || deviceToken.isBlank()) throw IllegalArgumentException("Missing device auth")

        val safeName = filename
            .replace(Regex("""[\\/:*?"<>|]"""), "_")
            .ifBlank { "smart-mpc-file" }
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(safeName)
            .setDescription("Smart MPC")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeName)
            .addRequestHeader("X-Device-Id", deviceId)
            .addRequestHeader("X-Device-Token", deviceToken)

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        return manager.enqueue(request)
    }

    private data class UploadConfig(
        val baseUrl: String,
        val deviceId: String,
        val deviceToken: String,
    )

    companion object {
        private const val REQUEST_PICK_FILES = 7291
    }
}
