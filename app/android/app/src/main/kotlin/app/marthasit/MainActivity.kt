package app.marthasit

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Alternate app icons for supporters: one launcher activity-alias per
    // icon (AndroidManifest.xml), exactly one enabled.
    private val icons = listOf("Default", "Green", "Purple", "Night")

    private fun alias(name: String) = ComponentName(packageName, "$packageName.Icon$name")

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
    }
}
