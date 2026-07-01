package com.smartmpc.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class NfcLaunchActivity : Activity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var titleView: TextView
    private lateinit var messageView: TextView
    private lateinit var progressView: ProgressBar
    private var started = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showLaunchScreen()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) startProcessing()
    }

    private fun startProcessing() {
        if (started) return
        started = true
        mainHandler.postDelayed({ runSelectedAction() }, 250)
    }

    private fun runSelectedAction() {
        when (quickAction()) {
            QUICK_SEND_FILE -> openFilePicker()
            QUICK_PULL_CLIPBOARD -> processQuickAction("Pulling clipboard") { pullPcClipboard() }
            QUICK_REQUEST_FILES -> openMainAppForAction("request_files")
            QUICK_OPEN_CHROME -> processQuickAction("Opening Chrome") { sendCommand("open_chrome") }
            QUICK_LOCK_PC -> processQuickAction("Locking PC") { sendCommand("lock_pc") }
            QUICK_SLEEP_PC -> processQuickAction("Sleeping PC") { sendCommand("sleep_pc") }
            else -> openFilePicker()
        }
    }

    private fun openFilePicker() {
        updateStatus("Choose file", "Select file to send to PC.", true)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(intent, REQUEST_PICK_FILES)
    }

    @Deprecated("Deprecated in Android API, still fine for this simple Activity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FILES) return

        if (resultCode != RESULT_OK || data == null) {
            updateStatus("Cancelled", "No file selected.", false)
            finishAfterDelay(900)
            return
        }

        val uris = selectedUris(data)
        if (uris.isEmpty()) {
            updateStatus("Cancelled", "No file selected.", false)
            finishAfterDelay(900)
            return
        }

        processFiles(uris)
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

    private fun processFiles(uris: List<Uri>) {
        updateStatus("Sending file", "Uploading ${uris.size} file(s) to PC.", true)
        Thread {
            val result = runCatching { uploadFiles(uris) }
                .getOrElse { TapResult("File failed", it.message ?: "Unknown error") }

            mainHandler.post {
                updateStatus(result.title, result.message, false)
                finishAfterDelay(1700)
            }
        }.start()
    }

    private fun processQuickAction(title: String, action: () -> TapResult) {
        updateStatus(title, "Sending action to PC.", true)
        Thread {
            val result = runCatching { action() }
                .getOrElse { TapResult("Action failed", it.message ?: "Unknown error") }

            mainHandler.post {
                updateStatus(result.title, result.message, false)
                finishAfterDelay(1300)
            }
        }.start()
    }

    private fun openMainAppForAction(action: String) {
        updateStatus("Opening app", "Loading selected action.", true)
        val deepLink = "$DEFAULT_DEEP_LINK?action=$action"
        getSharedPreferences(PREF_NAME, MODE_PRIVATE)
            .edit()
            .putString(PREF_PENDING_DEEP_LINK, deepLink)
            .apply()

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra(EXTRA_DEEP_LINK, deepLink)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
        finishAfterDelay(250)
    }

    private fun showLaunchScreen() {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.rgb(16, 20, 23))
            setPadding(48, 48, 48, 48)
        }

        progressView = ProgressBar(this).apply { isIndeterminate = true }
        titleView = TextView(this).apply {
            text = "Smart MPC"
            setTextColor(Color.rgb(232, 237, 240))
            textSize = 20f
            gravity = Gravity.CENTER
            setPadding(0, 28, 0, 0)
        }
        messageView = TextView(this).apply {
            text = "Reading tap action..."
            setTextColor(Color.rgb(154, 168, 175))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, 10, 0, 0)
        }

        layout.addView(progressView)
        layout.addView(titleView)
        layout.addView(messageView)
        setContentView(layout)
    }

    private fun updateStatus(title: String, message: String, loading: Boolean) {
        titleView.text = title
        messageView.text = message
        progressView.visibility = if (loading) android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun quickAction(): String {
        return getSharedPreferences(PREF_NAME, MODE_PRIVATE)
            .getString("quickAction", QUICK_SEND_FILE)
            .orEmpty()
    }

    private fun connectionConfig(): ConnectionConfig {
        val prefs = getSharedPreferences(PREF_NAME, MODE_PRIVATE)
        val baseUrl = prefs.getString("baseUrl", "")?.trim().orEmpty().trimEnd('/')
        val deviceId = prefs.getString("deviceId", "")?.trim().orEmpty()
        val deviceToken = prefs.getString("deviceToken", "")?.trim().orEmpty()

        if (baseUrl.isEmpty() || deviceId.isEmpty() || deviceToken.isEmpty()) {
            throw IllegalStateException("Open the app and trust this phone first.")
        }

        return ConnectionConfig(baseUrl, deviceId, deviceToken)
    }

    private fun sendCommand(commandId: String): TapResult {
        val config = connectionConfig()
        val body = JSONObject()
            .put("type", "command")
            .put("source", "nfc")
            .put("payload", JSONObject().put("command_id", commandId))

        postIntent(config.baseUrl, config.deviceId, config.deviceToken, body)

        return when (commandId) {
            "lock_pc" -> TapResult("PC locked", "Lock command sent.")
            "sleep_pc" -> TapResult("Sleep requested", "Sleep command sent.")
            "open_chrome" -> TapResult("Chrome opened", "Open Chrome command sent.")
            else -> TapResult("Command sent", commandId)
        }
    }

    private fun pullPcClipboard(): TapResult {
        val config = connectionConfig()
        val text = getClipboardFromPc(config.baseUrl, config.deviceId, config.deviceToken)
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("PC Clipboard", text))
        return if (text.isEmpty()) {
            TapResult("Clipboard empty", "PC clipboard is empty.")
        } else {
            TapResult("Clipboard copied", "PC clipboard copied to phone.")
        }
    }

    private fun uploadFiles(uris: List<Uri>): TapResult {
        val config = connectionConfig()

        var uploaded = 0
        for (uri in uris) {
            uploadFile(config, uri)
            uploaded += 1
        }

        return TapResult("File sent", "$uploaded file(s) sent to PC.")
    }

    private fun uploadFile(config: ConnectionConfig, uri: Uri) {
        val filename = fileName(uri)
        val encodedName = URLEncoder.encode(filename, Charsets.UTF_8.name())
        val connection = URL("${config.baseUrl}/api/files?filename=$encodedName").openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 5000
        connection.readTimeout = 60000
        connection.doOutput = true
        connection.setChunkedStreamingMode(0)
        connection.setRequestProperty("Content-Type", "application/octet-stream")
        connection.setRequestProperty("X-Device-Id", config.deviceId)
        connection.setRequestProperty("X-Device-Token", config.deviceToken)

        contentResolver.openInputStream(uri)?.use { input ->
            connection.outputStream.use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("Cannot read selected file")

        checkJsonResponse(connection)
    }

    private fun getClipboardFromPc(baseUrl: String, deviceId: String, deviceToken: String): String {
        val connection = URL("$baseUrl/api/clipboard").openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 5000
        connection.readTimeout = 8000
        connection.setRequestProperty("X-Device-Id", deviceId)
        connection.setRequestProperty("X-Device-Token", deviceToken)

        val response = checkJsonResponse(connection)
        return response.optString("text", "")
    }

    private fun postIntent(baseUrl: String, deviceId: String, deviceToken: String, body: JSONObject) {
        val connection = URL("$baseUrl/api/intent").openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 5000
        connection.readTimeout = 8000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setRequestProperty("X-Device-Id", deviceId)
        connection.setRequestProperty("X-Device-Token", deviceToken)

        connection.outputStream.use { output ->
            output.write(body.toString().toByteArray(Charsets.UTF_8))
        }

        checkJsonResponse(connection)
    }

    private fun checkJsonResponse(connection: HttpURLConnection): JSONObject {
        val responseCode = connection.responseCode
        val responseStream = if (responseCode in 200..299) connection.inputStream else connection.errorStream
        val responseText = responseStream?.bufferedReader()?.use { it.readText() }.orEmpty()
        if (responseCode !in 200..299) {
            throw IllegalStateException("HTTP $responseCode")
        }

        val response = JSONObject(responseText)
        if (!response.optBoolean("ok", false)) {
            throw IllegalStateException(response.optString("error", "Request failed"))
        }
        return response
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

    private fun finishAfterDelay(delayMs: Long) {
        mainHandler.postDelayed({ finish() }, delayMs)
    }

    private data class ConnectionConfig(
        val baseUrl: String,
        val deviceId: String,
        val deviceToken: String,
    )

    private data class TapResult(
        val title: String,
        val message: String,
    )

    companion object {
        const val EXTRA_DEEP_LINK = "smart_mpc_deep_link"
        const val PREF_PENDING_DEEP_LINK = "pendingDeepLink"
        private const val REQUEST_PICK_FILES = 7291
        private const val PREF_NAME = "smart_mpc"
        private const val DEFAULT_DEEP_LINK = "smartmpc://tap"
        private const val QUICK_SEND_FILE = "send_file"
        private const val QUICK_PULL_CLIPBOARD = "pull_clipboard"
        private const val QUICK_REQUEST_FILES = "request_files"
        private const val QUICK_OPEN_CHROME = "open_chrome"
        private const val QUICK_LOCK_PC = "lock_pc"
        private const val QUICK_SLEEP_PC = "sleep_pc"
    }
}
