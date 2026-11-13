package com.zipease.zipease

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.URLConnection

/** Streams app-private output to a user-selected document/folder via Android SAF. */
class MainActivity : FlutterActivity() {
    private val channelName = "com.zipease.zipease/exports"
    private val requestCodeExport = 7402
    private val requestCodeZipImport = 7403
    private var pendingZipResult: MethodChannel.Result? = null
    private var pendingResult: MethodChannel.Result? = null
    private var exportSource: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "pickZip" || call.method == "pickZipAllFiles") {
                    openZipPicker(result, call.method == "pickZipAllFiles")
                    return@setMethodCallHandler
                }
                if (call.method != "exportPath") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null || pendingZipResult != null) {
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


    /**
     * Two modes are offered because OEM file managers sometimes browse a ZIP
     * as if it were a directory, showing "No files" for its APK contents.
     *
     * GET_CONTENT is designed for importing a private copy of a document.
     * If a provider mislabels the ZIP MIME type, users may instead select it
     * through the unrestricted OPEN_DOCUMENT "Browse all files" fallback.
     */
    private fun openZipPicker(result: MethodChannel.Result, browseAllFiles: Boolean) {
        if (pendingResult != null || pendingZipResult != null) {
            result.error("BUSY", "Another file selection is already running", null)
            return
        }
        val intent = if (browseAllFiles) {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_GET_CONTENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/zip",
                        "application/x-zip-compressed",
                        "application/x-zip",
                        "application/octet-stream"
                    )
                )
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        pendingZipResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(Intent.createChooser(intent, "Select ZIP archive"), requestCodeZipImport)
        } catch (e: Exception) {
            pendingZipResult = null
            result.error("PICKER_FAILED", e.message ?: "Unable to open document picker", null)
        }
    }

    /** Copy the SAF content URI into app storage, then verify its ZIP signature.
     * This avoids assuming the provider returned a readable filesystem path.
     */
    private fun importSelectedZip(resultCode: Int, data: Intent?) {
        val result = pendingZipResult ?: return
        pendingZipResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        Thread {
            var destination: File? = null
            try {
                val displayName = contentResolver.query(
                    uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                } ?: "selected.zip"
                val safeName = displayName.substringAfterLast('/')
                    .substringAfterLast('\\').ifBlank { "selected.zip" }

                val importedFile = File.createTempFile("zipease_selected_", ".zip", cacheDir)
                destination = importedFile
                val source = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Unable to read the selected document")
                source.use { input ->
                    FileOutputStream(importedFile).use { output ->
                        val buffer = ByteArray(65536)
                        var bytesReadTotal = 0L
                        val maxInputBytes = 1024L * 1024 * 1024
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            bytesReadTotal += count.toLong()
                            if (bytesReadTotal > maxInputBytes) {
                                throw IllegalArgumentException("ZIP exceeds the 1 GiB import limit")
                            }
                            output.write(buffer, 0, count)
                        }
                    }
                }
                val signature = ByteArray(4)
                val readCount = FileInputStream(importedFile).use { it.read(signature) }
                val validZip = readCount == 4 &&
                    signature[0] == 0x50.toByte() && signature[1] == 0x4B.toByte() &&
                    ((signature[2] == 0x03.toByte() && signature[3] == 0x04.toByte()) ||
                     (signature[2] == 0x05.toByte() && signature[3] == 0x06.toByte()) ||
                     (signature[2] == 0x07.toByte() && signature[3] == 0x08.toByte()))
                if (!validZip) throw IllegalArgumentException(
                    "This document is not a valid ZIP file. Choose a .zip archive from Downloads."
                )
                val importedPath = importedFile.absolutePath
                runOnUiThread {
                    result.success(mapOf("path" to importedPath, "name" to safeName))
                }
            } catch (e: Exception) {
                destination?.delete()
                runOnUiThread {
                    result.error("ZIP_IMPORT_FAILED", e.message ?: "Cannot read selected ZIP", null)
                }
            }
        }.start()
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
        if (requestCode == requestCodeZipImport) {
            importSelectedZip(resultCode, data)
            return
        }
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
