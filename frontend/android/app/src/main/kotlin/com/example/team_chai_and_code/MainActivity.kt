package com.example.team_chai_and_code

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var indexBridge: AppSearchIndexBridge
    private lateinit var indexChannel: MethodChannel
    private lateinit var scannerBridge: LocalScannerBridge
    private lateinit var scannerChannel: MethodChannel
    private lateinit var localModelBridge: LocalModelBridge
    private lateinit var localModelChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        indexBridge = AppSearchIndexBridge(this)
        indexChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "teamChaiAndCode/local_index")
        indexChannel.setMethodCallHandler(indexBridge)

        scannerBridge = LocalScannerBridge(this, indexBridge)
        scannerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "teamChaiAndCode/local_scanner")
        scannerChannel.setMethodCallHandler(scannerBridge)

        localModelBridge = LocalModelBridge(this)
        localModelChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "teamChaiAndCode/local_model")
        localModelChannel.setMethodCallHandler(localModelBridge)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::scannerBridge.isInitialized) {
            scannerBridge.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        indexChannel.setMethodCallHandler(null)
        scannerChannel.setMethodCallHandler(null)
        localModelChannel.setMethodCallHandler(null)
        localModelBridge.close()
        indexBridge.close()
        super.onDestroy()
    }
}
