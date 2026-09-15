package pro.xbxx.xingbo_app

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(engine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(engine)
        io.flutter.plugin.common.MethodChannel(engine.dartExecutor.binaryMessenger, "xingbo/links")
            .setMethodCallHandler { call, result ->
                val value = call.arguments as? String
                val uri = value?.let { android.net.Uri.parse(it) }
                if (call.method != "open" || uri == null || uri.scheme !in listOf("https", "http") || uri.host.isNullOrEmpty()) {
                    result.error("invalid", "链接无效", null)
                } else {
                    try { startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, uri)); result.success(null) }
                    catch (e: Exception) { result.error("unavailable", "无法打开浏览器", null) }
                }
            }
    }
}
