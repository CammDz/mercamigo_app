package com.mercamigo.mercamigo_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /** Resultado pendiente de la peticion del permiso de camara. */
    private var pendingPermission: MethodChannel.Result? = null

    /**
     * Canal propio para **consultar** el estado del permiso de camara.
     *
     * No se pide el permiso desde aqui: el plugin `mobile_scanner` ya lo
     * solicita. Este canal solo sirve para distinguir entre "todavia no se ha
     * pedido", "denegado" y "denegado de forma permanente" (bloqueado), y
     * asi poder ofrecer abrir Ajustes.
     *
     * La excepcion es `requestCameraPermission`: la foto del producto se
     * puede tomar con la camara del telefono y ahi si hace falta pedir el
     * permiso desde la app.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cameraPermission" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.CAMERA
                        ) == PackageManager.PERMISSION_GRANTED

                        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                        val asked = prefs.getBoolean(KEY_CAMERA_ASKED, false)

                        if (granted) {
                            result.success("granted")
                        } else if (!asked) {
                            // Todavía no se ha mostrado nunca el diálogo.
                            result.success("pending")
                        } else {
                            // `true` = se puede volver a preguntar al usuario.
                            val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(
                                this,
                                Manifest.permission.CAMERA
                            )
                            result.success(if (canAskAgain) "denied" else "blocked")
                        }
                    }
                    "requestCameraPermission" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.CAMERA
                        ) == PackageManager.PERMISSION_GRANTED

                        if (granted) {
                            result.success("granted")
                        } else {
                            getSharedPreferences(PREFS, MODE_PRIVATE)
                                .edit()
                                .putBoolean(KEY_CAMERA_ASKED, true)
                                .apply()
                            pendingPermission = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.CAMERA),
                                REQUEST_CAMERA
                            )
                        }
                    }
                    "openAppSettings" -> {
                        // Abre los ajustes de la app para cambiar el permiso.
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null)
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Respuesta del usuario al permiso de camara. */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CAMERA) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(
                this,
                Manifest.permission.CAMERA
            )
            pendingPermission?.success(
                when {
                    granted -> "granted"
                    canAskAgain -> "denied"
                    else -> "blocked"
                }
            )
            pendingPermission = null
        }
    }

    companion object {
        private const val CHANNEL = "com.mercamigo/permisos"
        private const val REQUEST_CAMERA = 4201
        private const val PREFS = "mercamigo_permisos"
        private const val KEY_CAMERA_ASKED = "camara_pedida"
    }
}
