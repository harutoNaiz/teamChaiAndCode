package com.example.team_chai_and_code

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/** Periodically re-scans only URI trees for which the user granted access. */
class LocalIndexWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : Worker(appContext, parameters) {
    override fun doWork(): Result {
        val index = AppSearchIndexBridge(applicationContext)
        return try {
            LocalScannerBridge(applicationContext, index).scanPersistedSources()
            Result.success()
        } catch (_: SecurityException) {
            Result.failure()
        } catch (_: Exception) {
            Result.retry()
        } finally {
            index.close()
        }
    }

    companion object {
        private const val UNIQUE_NAME = "team_chai_incremental_index"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<LocalIndexWorker>(15, TimeUnit.MINUTES)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiresStorageNotLow(true)
                        .setRequiresBatteryNotLow(true)
                        .build()
                )
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }
    }
}
