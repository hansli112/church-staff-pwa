package app.marthasit

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Alternate app icons, for supporters and churches with their own: one
    // launcher activity-alias per icon (AndroidManifest.xml), exactly one
    // enabled.
    private val icons = listOf("Default", "Green", "Purple", "Night", "Zhuwei")

    private fun alias(name: String) = ComponentName(packageName, "$packageName.Icon$name")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // The channel pushes arrive on (the manifest's
    // default_notification_channel_id), named in the phone's language;
    // without it they land on Firebase's own, which settings list as
    // "Miscellaneous". Creating it again renames it when the language changes.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "duties", getString(R.string.notification_channel), NotificationManager.IMPORTANCE_DEFAULT)
        channel.description = getString(R.string.notification_channel_description)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "martha/app_icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "current" -> {
                    val enabled = icons.firstOrNull {
                        packageManager.getComponentEnabledSetting(alias(it)) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    }
                    result.success(if (enabled == null || enabled == "Default") null else enabled)
                }
                "set" -> {
                    val wanted = (call.arguments as String?) ?: "Default"
                    if (wanted !in icons) {
                        result.error("unknown_icon", wanted, null)
                        return@setMethodCallHandler
                    }
                    // Enable the new one first so the app always has a
                    // launcher entry.
                    packageManager.setComponentEnabledSetting(
                        alias(wanted), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                    for (other in icons.filter { it != wanted }) {
                        packageManager.setComponentEnabledSetting(
                            alias(other), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Notifications turned off: the system does not ask again, so this
        // app's notification settings are the way back.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "martha/settings").setMethodCallHandler { call, result ->
            when (call.method) {
                "notifications" -> {
                    // Android 7 and below have no page for notifications
                    // alone, nor do some makers' phones: the app's own page
                    // holds them.
                    val pages = listOfNotNull(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else null,
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
                    )
                    val opened = pages.any {
                        try {
                            startActivity(it)
                            true
                        } catch (_: ActivityNotFoundException) {
                            false
                        }
                    }
                    if (opened) result.success(null) else result.error("no_settings", null, null)
                }
                // The number on the icon (#89): launchers count the
                // notifications showing, each with the number its push
                // brought. Everything read: none of them is news.
                "badge" -> {
                    if ((call.arguments as? Int ?: 0) == 0) {
                        getSystemService(NotificationManager::class.java).cancelAll()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
