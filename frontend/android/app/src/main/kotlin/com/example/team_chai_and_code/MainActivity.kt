package com.example.team_chai_and_code

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var indexBridge: AppSearchIndexBridge
    private lateinit var indexChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        indexBridge = AppSearchIndexBridge(this)
        indexChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "teamChaiAndCode/local_index")
        indexChannel.setMethodCallHandler(indexBridge)
    }

    override fun onDestroy() {
        indexChannel.setMethodCallHandler(null)
        indexBridge.close()
        super.onDestroy()
    }
}
