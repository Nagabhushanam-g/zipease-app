package com.zipease.zipease

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.URLConnection
import java.util.UUID

/** Streams app-private output to a user-selected document/folder via Android SAF. */
class MainActivity : FlutterActivity() {
    private val channelName = "com.zipease.zipease/exports"
    private val requestCodeExport = 7402
    private val requestCodeZipImport = 7403
    private var pendingZipResult: MethodChannel.Result? = null
    private var pendingResult: MethodChannel.Result? = null
    private var exportSource: File? = null
    private var exportDisplayName: String? = null
    private var incomingZipChannel: MethodChannel? = null
    private var dartOpenWithReady = false
    private var pendingOpenedZip: Map<String, String>? = null
    private var pendingOpenedZipError: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        acceptExternalZipIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptExternalZipIntent(intent)
    }

    private fun acceptExternalZipIntent(intent: Intent?) {
        if (intent == null) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            }
            else -> null
        } ?: return
        Thread {
            try {
                val imported = copyAndVerifyZip(uri)
                runOnUiThread {
                    if (dartOpenWithReady) {
                        incomingZipChannel?.invokeMethod("openedZip", imported)
                    } else {
                        pendingOpenedZip = imported
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    val message = error.message ?: "Unable to open ZIP from another app"
                    if (dartOpenWithReady) {
                        incomingZipChannel?.invokeMethod("openedZipError", message)
                    } else {
                        pendingOpenedZipError = message
                    }
                }
            }
        }.start()
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingZipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.zipease.zipease/open_with"
        )
        incomingZipChannel?.setMethodCallHandler { call, result ->
            if (call.method != "takePendingZip") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            dartOpenWithReady = true
            val next = pendingOpenedZip
            val problem = pendingOpenedZipError
            pendingOpenedZip = null
            pendingOpenedZipError = null
            result.success(
                next ?: if (problem != null) mapOf("error" to problem) else null
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "pickZip" || call.method == "pickZipAllFiles") {
                    openZipPicker(result, call.method == "pickZipAllFiles")
                    return@setMethodCallHandler
                }
                if (call.method == "fileAction") {
                    openExternalFileAction(call, result)
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
                        type = mimeForFile(safeName)
                        putExtra(Intent.EXTRA_TITLE, safeName)
                    }
                }
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                pendingResult = result
                exportSource = source
                exportDisplayName = safeName
                try {
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, requestCodeExport)
                } catch (e: Exception) {
                    pendingResult = null
                    exportSource = null
                    exportDisplayName = null
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

    /** Import a ZIP from any granted content:// or accessible file:// URI.
     * Shared by in-app pickers and Android's external Open with intent.
     */
    private fun copyAndVerifyZip(uri: Uri): Map<String, String> {
        var destination: File? = null
        try {
            val displayName = try {
                contentResolver.query(
                    uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
            } catch (_: Exception) {
                null
            } ?: uri.lastPathSegment ?: "selected.zip"
            val safeName = displayName.substringAfterLast('/')
                .substringAfterLast('\\').ifBlank { "selected.zip" }

            val importedFile = File.createTempFile("zipease_selected_", ".zip", cacheDir)
            destination = importedFile
            val stream = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Unable to read the ZIP from this app")
            stream.use { input ->
                FileOutputStream(importedFile).use { output ->
                    val buffer = ByteArray(65536)
                    var total = 0L
                    val limit = 1024L * 1024 * 1024
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count.toLong()
                        if (total > limit) {
                            throw IllegalArgumentException("ZIP exceeds the 1 GiB import limit")
                        }
                        output.write(buffer, 0, count)
                    }
                }
            }
            val signature = ByteArray(4)
            val read = FileInputStream(importedFile).use { it.read(signature) }
            val validZip = read == 4 &&
                signature[0] == 0x50.toByte() && signature[1] == 0x4B.toByte() &&
                ((signature[2] == 0x03.toByte() && signature[3] == 0x04.toByte()) ||
                 (signature[2] == 0x05.toByte() && signature[3] == 0x06.toByte()) ||
                 (signature[2] == 0x07.toByte() && signature[3] == 0x08.toByte()))
            if (!validZip) {
                throw IllegalArgumentException("Not a ZIP archive. Please select a .zip file.")
            }
            return mapOf("path" to importedFile.absolutePath, "name" to safeName)
        } catch (error: Exception) {
            destination?.delete()
            throw error
        }
    }

    /** Android in-app file picker result. */
    private fun importSelectedZip(resultCode: Int, data: Intent?) {
        val result = pendingZipResult ?: return
        pendingZipResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        Thread {
            try {
                val imported = copyAndVerifyZip(uri)
                runOnUiThread { result.success(imported) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "ZIP_IMPORT_FAILED",
                        error.message ?: "Cannot read selected ZIP",
                        null
                    )
                }
            }
        }.start()
    }


    /** The user explicitly chose Open with, Share, or Install from My Files.
     * Make a shareable copy under cache/zipease_outgoing and expose it only
     * through a read-only FileProvider content URI, never file:// or root-path.
     */
    private fun openExternalFileAction(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        val kind = call.argument<String>("action")
        val rawPath = call.argument<String>("path")
        val rawName = call.argument<String>("fileName")
        if (kind !in setOf("open", "share", "install") || rawPath == null || rawName == null) {
            result.error("INVALID_ACTION", "Invalid file action", null)
            return
        }
        val source = try { File(rawPath).canonicalFile } catch (_: Exception) { null }
        if (source == null || !source.isFile || !isWithinPrivateStorage(source)) {
            result.error("INVALID_SOURCE", "File is not in ZipEase private storage", null)
            return
        }
        val filename = rawName.substringAfterLast('/').substringAfterLast('\\')
        if (filename.isBlank() || filename == "." || filename == "..") {
            result.error("INVALID_NAME", "Invalid file name", null)
            return
        }
        if (kind == "install" && !filename.endsWith(".apk", ignoreCase = true)) {
            result.error("INVALID_APK", "Only .apk files can be installed", null)
            return
        }

        if (kind == "install" &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()) {
            try {
                val settings = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
                startActivity(settings)
                result.success("permission_required")
            } catch (error: Exception) {
                result.error("INSTALL_PERMISSION", "Enable install permission in Android settings.", null)
            }
            return
        }

        Thread {
            try {
                val outgoingRoot = File(cacheDir, "zipease_outgoing")
                if (!outgoingRoot.exists() && !outgoingRoot.mkdirs()) {
                    throw IllegalStateException("Unable to prepare temporary file sharing")
                }
                // Older temporary copies are expendable. Keep recent shares
                // until consumers have finished using their granted URI.
                val oldest = System.currentTimeMillis() - 48L * 60 * 60 * 1000
                outgoingRoot.listFiles()?.forEach { old ->
                    if (old.lastModified() < oldest) old.deleteRecursively()
                }
                val session = File(outgoingRoot, UUID.randomUUID().toString())
                if (!session.mkdirs()) {
                    throw IllegalStateException("Unable to create share folder")
                }
                val target = File(session, filename).canonicalFile
                if (!target.path.startsWith(session.canonicalPath + File.separator)) {
                    throw SecurityException("Invalid shared file name")
                }
                FileInputStream(source).use { input ->
                    FileOutputStream(target).use { output ->
                        input.copyTo(output, bufferSize = 64 * 1024)
                    }
                }
                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.zipease_files",
                    target
                )
                runOnUiThread {
                    try {
                        val mime = mimeForFile(filename)
                        val actionIntent = when (kind) {
                            "share" -> Intent(Intent.ACTION_SEND).apply {
                                type = mime
                                putExtra(Intent.EXTRA_STREAM, uri)
                            }
                            "install" -> Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                            }
                            else -> Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, mime)
                            }
                        }
                        actionIntent.clipData = ClipData.newRawUri(filename, uri)
                        actionIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (kind == "install") {
                            startActivity(actionIntent)
                        } else {
                            val title = if (kind == "share") "Share file" else "Open with"
                            val chooser = Intent.createChooser(actionIntent, title)
                            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(chooser)
                        }
                        result.success("launched")
                    } catch (error: Exception) {
                        result.error(
                            "NO_HANDLER",
                            error.message ?: "No compatible app available",
                            null
                        )
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "FILE_ACTION_FAILED",
                        error.message ?: "Unable to prepare selected file",
                        null
                    )
                }
            }
        }.start()
    }

    private fun isWithinPrivateStorage(file: File): Boolean {
        val resolved = file.canonicalPath
        // PathProvider stores persistent Flutter documents in app_flutter.
        // ZipEase's My Files library must be exportable just like cache output.
        val flutterDocuments = File(applicationInfo.dataDir, "app_flutter")
        return listOf(cacheDir, filesDir, flutterDocuments).any { root ->
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
        val displayName = exportDisplayName
        pendingResult = null
        exportSource = null
        exportDisplayName = null
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
                    // Never flatten an extracted ZIP into the chosen folder.
                    // Create a separate parent folder named for its source ZIP.
                    val folder = DocumentsContract.createDocument(
                        contentResolver, root, DocumentsContract.Document.MIME_TYPE_DIR,
                        displayName ?: source.name
                    ) ?: throw IllegalStateException("Could not create extracted ZIP folder")
                    copyDirectory(source, folder, source.canonicalFile)
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

    /** Correct file type when saving individual extracted files. */
    private fun mimeForFile(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "zip" -> "application/zip"
            "apk" -> "application/vnd.android.package-archive"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "ppt" -> "application/vnd.ms-powerpoint"
            "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            "pdf" -> "application/pdf"
            "csv" -> "text/csv"
            "txt" -> "text/plain"
            "mp4" -> "video/mp4"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "7z" -> "application/x-7z-compressed"
            "rar" -> "application/vnd.rar"
            else -> URLConnection.guessContentTypeFromName(name)
                ?: "application/octet-stream"
        }
    }

    private fun copyDirectory(directory: File, targetParent: Uri, allowedRoot: File) {
        val rootPath = allowedRoot.canonicalPath
        for (child in (directory.listFiles() ?: throw IllegalStateException("Folder could not be listed")).sortedBy { it.name }) {
            // Older ZipEase versions stored an internal metadata marker
            // inside the extracted root. Do not export that extra file.
            if (directory.canonicalFile == allowedRoot &&
                child.name == ".zipease_source.json") continue
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
                val mime = mimeForFile(child.name)
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
