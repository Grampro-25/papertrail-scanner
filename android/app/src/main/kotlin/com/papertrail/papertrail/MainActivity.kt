package com.papertrail.papertrail

import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "papertrail/pdf").setMethodCallHandler { call, result ->
            if (call.method != "export") { result.notImplemented(); return@setMethodCallHandler }
            val pages = call.argument<List<String>>("pages") ?: emptyList()
            val name = call.argument<String>("name") ?: "Document"
            worker.execute {
                try {
                    require(pages.isNotEmpty()) { "No pages to export" }
                    val folder = File(cacheDir, "exports").apply { mkdirs() }
                    folder.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86400000 }?.forEach { it.delete() }
                    val safe = name.replace(Regex("[^\\p{L}\\p{N} ._-]"), "_").take(80).ifBlank { "Document" }
                    val output = File(folder, "$safe-${System.currentTimeMillis()}.pdf")
                    val pdf = PdfDocument()
                    try {
                        pages.forEachIndexed { index, path ->
                            val bitmap = BitmapFactory.decodeFile(path) ?: error("Cannot read page ${index + 1}")
                            try {
                                val landscape = bitmap.width > bitmap.height
                                val width = if (landscape) 842 else 595
                                val height = if (landscape) 595 else 842
                                val page = pdf.startPage(PdfDocument.PageInfo.Builder(width, height, index + 1).create())
                                val scale = minOf((width - 32f) / bitmap.width, (height - 32f) / bitmap.height)
                                val w = bitmap.width * scale; val h = bitmap.height * scale
                                page.canvas.drawBitmap(bitmap, null, RectF((width-w)/2, (height-h)/2, (width+w)/2, (height+h)/2), Paint(Paint.FILTER_BITMAP_FLAG))
                                pdf.finishPage(page)
                            } finally { bitmap.recycle() }
                        }
                        output.outputStream().use { pdf.writeTo(it) }
                    } finally { pdf.close() }
                    runOnUiThread { result.success(output.absolutePath) }
                } catch (e: Exception) { runOnUiThread { result.error("PDF_EXPORT", e.message, null) } }
            }
        }
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
}
