package com.garagemanager.app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Flutter "Start Server" button to Termux's RUN_COMMAND API, so the app can
 * kick off the on-device backend (Garage_backend/deploy/start-garage.sh, run via Termux:Boot)
 * without the user having to open Termux manually.
 *
 * Requires, on the phone, in Termux:
 *   ~/.termux/termux.properties containing `allow-external-apps=true` (+ termux-reload-settings)
 * and this app holding the com.termux.permission.RUN_COMMAND permission (requested at runtime
 * below, like any other dangerous permission).
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "garage_manager/termux"
    private val RUN_COMMAND_PERMISSION = "com.termux.permission.RUN_COMMAND"
    private val PERMISSION_REQUEST_CODE = 4821

    // Path Termux:Boot already runs on power-on — see Garage_backend/TERMUX_SETUP.md.
    private val START_SCRIPT_PATH =
        "/data/data/com.termux/files/home/.termux/boot/start-garage.sh"

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> startTermuxServer(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun startTermuxServer(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, RUN_COMMAND_PERMISSION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            // Ask for it; the outcome is delivered to onRequestPermissionsResult below.
            pendingResult = result
            ActivityCompat.requestPermissions(this, arrayOf(RUN_COMMAND_PERMISSION), PERMISSION_REQUEST_CODE)
            return
        }
        sendRunCommandIntent(result)
    }

    private fun sendRunCommandIntent(result: MethodChannel.Result) {
        try {
            val intent = Intent()
            intent.setClassName("com.termux", "com.termux.app.RunCommandService")
            intent.action = "com.termux.RUN_COMMAND"
            intent.putExtra("com.termux.RUN_COMMAND_PATH", START_SCRIPT_PATH)
            intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success("started")
        } catch (e: Exception) {
            result.error("TERMUX_ERROR", "Could not reach Termux: ${e.message}", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val result = pendingResult
        pendingResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            result?.let { sendRunCommandIntent(it) }
        } else {
            result?.error("PERMISSION_DENIED", "RUN_COMMAND permission was not granted.", null)
        }
    }
}
