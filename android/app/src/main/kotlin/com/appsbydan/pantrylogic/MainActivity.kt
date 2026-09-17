package com.appsbydan.pantrylogic

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pantry_logic/actions").setMethodCallHandler { call, result ->
            try {
                val value = call.arguments as? String ?: ""
                when (call.method) {
                    "openUrl" -> {
                        val uri = Uri.parse(value)
                        require(uri.scheme == "https")
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    }
                    "share" -> {
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, value)
                        }, "Share shopping list"))
                        result.success(null)
                    }
                    "shareRecipe" -> {
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, value)
                        }, "Share recipe"))
                        result.success(null)
                    }
                    "printRecipe" -> {
                        printRecipe(value)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("UNAVAILABLE", "No app can open this action.", null) }
        }
    }

    private fun printRecipe(text: String) {
        val printManager = getSystemService(PRINT_SERVICE) as PrintManager
        val adapter = object : PrintDocumentAdapter() {
            override fun onLayout(
                oldAttributes: PrintAttributes?,
                newAttributes: PrintAttributes,
                cancellationSignal: CancellationSignal,
                callback: LayoutResultCallback,
                extras: Bundle?
            ) {
                if (cancellationSignal.isCanceled) {
                    callback.onLayoutCancelled()
                    return
                }
                callback.onLayoutFinished(
                    PrintDocumentInfo.Builder("pantry_logic_recipe.pdf")
                        .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                        .setPageCount(1)
                        .build(),
                    oldAttributes != newAttributes
                )
            }

            override fun onWrite(
                pages: Array<PageRange>,
                destination: ParcelFileDescriptor,
                cancellationSignal: CancellationSignal,
                callback: WriteResultCallback
            ) {
                try {
                    if (cancellationSignal.isCanceled) {
                        destination.close()
                        callback.onWriteCancelled()
                        return
                    }
                    ParcelFileDescriptor.AutoCloseOutputStream(destination).use { output ->
                        output.write(createPdf(text))
                    }
                    callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                } catch (error: Exception) {
                    callback.onWriteFailed(error.message)
                }
            }
        }
        printManager.print(
            "Pantry Logic recipe",
            adapter,
            PrintAttributes.Builder().build()
        )
    }

    /** Creates a dependency-free, one-page PDF for Android's print spooler. */
    private fun createPdf(text: String): ByteArray {
        val lines = mutableListOf<String>()
        for (sourceLine in text.replace("\r", "").split("\n")) {
            var line = sourceLine
            while (line.length > 96) {
                lines.add(line.take(96))
                line = line.drop(96)
            }
            lines.add(line)
        }
        val content = buildString {
            append("BT /F1 10 Tf 50 742 Td ")
            lines.take(54).forEachIndexed { index, line ->
                if (index > 0) append(" 0 -13 Td ")
                val safe = line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
                    .map { if (it.code in 32..126) it else '?' }
                    .joinToString("")
                append("($safe) Tj")
            }
            append(" ET")
        }
        val objects = listOf(
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length ${content.toByteArray(Charsets.US_ASCII).size} >>\nstream\n$content\nendstream",
        )
        val pdf = StringBuilder("%PDF-1.4\n")
        val offsets = mutableListOf<Int>()
        for ((index, objectText) in objects.withIndex()) {
            offsets.add(pdf.toString().toByteArray(Charsets.US_ASCII).size)
            pdf.append("${index + 1} 0 obj\n$objectText\nendobj\n")
        }
        val xrefOffset = pdf.toString().toByteArray(Charsets.US_ASCII).size
        pdf.append("xref\n0 ${objects.size + 1}\n0000000000 65535 f \n")
        offsets.forEach { offset ->
            pdf.append(offset.toString().padStart(10, '0')).append(" 00000 n \n")
        }
        pdf.append("trailer\n<< /Size ${objects.size + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n")
        return pdf.toString().toByteArray(Charsets.US_ASCII)
    }
}
