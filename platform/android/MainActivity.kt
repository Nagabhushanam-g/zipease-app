package com.zipease.zipease

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.net.URLConnection

/** Streams app-private output to a user-selected document/folder via Android SAF. */
class MainActivity : FlutterActivity() {
    private val channelName = "com.zipease.zipease/exports"
    private val requestCodeExport = 7402
    private var pendingResult: MethodChannel.Result? = null
    private var exportSource: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "exportPath") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("BUSY", "Another export is already in progress", null)
                    return@setMethodCallHandler
                }
                val suppliedPath = call.argument<String>("path")
                val source = suppliedPath?.let { File(it).canonicalFile }
                if (source == null || !source.exists() || !isWithinPrivateStorage(source)) {
                    result.error("INVALID_SOURCE", "Output is not in ZipEase private storage", null)
                    return@setMethodCallHandler
                }
                val proposedName = call.argument<String>("fileName") ?: source.name
                val safeName = proposedName.substringAfterLast('/').substringAfterLast('\\')
                if (safeName.isEmpty() || safeName == "." || safeName == "..") {
                    result.error("INVALID_NAME", "Invalid export file name", null)
                    return@setMethodCallHandler
                }
                val intent = if (source.isDirectory) {
                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                } else {
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                        putExtra(Intent.EXTRA_TITLE, safeName)
                    }
                }
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                pendingResult = result
                exportSource = source
                try {
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, requestCodeExport)
                } catch (e: Exception) {
                    pendingResult = null
                    exportSource = null
                    result.error("PICKER_FAILED", e.message ?: "Could not open file picker", null)
                }
            }
    }

    private fun isWithinPrivateStorage(file: File): Boolean {
        val resolved = file.canonicalPath
        return listOf(cacheDir, filesDir).any { root ->
            resolved.startsWith(root.canonicalPath + File.separator)
        }
    }

    @Deprecated("Uses Android's Activity result callback for SAF")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestCodeExport) return
        val result = pendingResult ?: return
        val source = exportSource
        pendingResult = null
        exportSource = null
        val target = data?.data
        if (resultCode != Activity.RESULT_OK || source == null || target == null) {
            result.success(false)
            return
        }
        Thread {
            try {
                if (source.isDirectory) {
                    val root = DocumentsContract.buildDocumentUriUsingTree(
                        target, DocumentsContract.getTreeDocumentId(target))
                    copyDirectory(source, root, source.canonicalFile)
                } else {
                    streamFile(source, target)
                }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SAVE_FAILED", e.message ?: "Unable to write to selected destination", null)
                }
            }
        }.start()
    }

    private fun copyDirectory(directory: File, targetParent: Uri, allowedRoot: File) {
        val rootPath = allowedRoot.canonicalPath
        for (child in (directory.listFiles() ?: throw IllegalStateException("Folder could not be listed")).sortedBy { it.name }) {
            val resolved = child.canonicalFile
            if (resolved.path != rootPath && !resolved.path.startsWith(rootPath + File.separator)) {
                throw SecurityException("Linked content outside extracted directory is not allowed")
            }
            if (child.isDirectory) {
                val newFolder = DocumentsContract.createDocument(
                    contentResolver, targetParent,
                    DocumentsContract.Document.MIME_TYPE_DIR, child.name)
                    ?: throw IllegalStateException("Could not create folder: ${child.name}")
                copyDirectory(child, newFolder, allowedRoot)
            } else if (child.isFile) {
                val mime = URLConnection.guessContentTypeFromName(child.name) ?: "application/octet-stream"
                val created = DocumentsContract.createDocument(
                    contentResolver, targetParent, mime, child.name)
                    ?: throw IllegalStateException("Could not create file: ${child.name}")
                streamFile(child, created)
            }
        }
    }

    private fun streamFile(source: File, target: Uri) {
        val output = contentResolver.openOutputStream(target, "wt")
            ?: throw IllegalStateException("Could not open output")
        output.use { stream ->
            FileInputStream(source).use { input -> input.copyTo(stream, bufferSize = 64 * 1024) }
        }
    }
}
