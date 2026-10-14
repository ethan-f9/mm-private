package com.ethanmt.personal_finance_manager

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Jembatan ke Android Storage Access Framework untuk backup:
 * pilih folder sekali (izin disimpan permanen), lalu tulis/daftar/hapus file di
 * folder itu tanpa dialog lagi. Tidak memakai plugin pihak ketiga.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.ethanmt.personal_finance_manager/backup_storage"
        private const val REQUEST_PICK_TREE = 4101
    }

    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> pickFolder(result)
                    "describeFolder" -> describeFolder(call, result)
                    "writeFile" -> writeFile(call, result)
                    "listFiles" -> listFiles(call, result)
                    "deleteFile" -> deleteFile(call, result)
                    "releaseFolder" -> releaseFolder(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "Pemilih folder sedang terbuka", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
            // Petunjuk lokasi awal: folder Download (hanya saran, boleh diabaikan sistem).
            putExtra(
                "android.provider.extra.INITIAL_URI",
                Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload")
            )
        }
        startActivityForResult(intent, REQUEST_PICK_TREE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_TREE) return

        val result = pendingPick ?: return
        pendingPick = null

        val uri = data?.data
        if (resultCode == Activity.RESULT_OK && uri != null) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                result.success(uri.toString())
            } catch (e: Exception) {
                result.error("permission", e.message, null)
            }
        } else {
            result.success(null)
        }
    }

    /** Nama dan id dokumen folder, atau null kalau izin hilang / folder sudah tidak ada. */
    private fun describeFolder(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        if (treeUriString == null) {
            result.error("args", "treeUri kosong", null)
            return
        }
        try {
            val treeUri = Uri.parse(treeUriString)
            val hasWrite = contentResolver.persistedUriPermissions.any {
                it.uri == treeUri && it.isWritePermission
            }
            if (!hasWrite) {
                result.success(null)
                return
            }
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
            val folderName = displayName(docUri)
            if (folderName == null) {
                result.success(null)
                return
            }
            result.success(mapOf("name" to folderName, "documentId" to docId))
        } catch (e: Exception) {
            result.success(null)
        }
    }

    private fun writeFile(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        val fileName = call.argument<String>("fileName")
        val content = call.argument<String>("content")
        if (treeUriString == null || fileName == null || content == null) {
            result.error("args", "Argumen tidak lengkap", null)
            return
        }
        Thread {
            try {
                val treeUri = Uri.parse(treeUriString)
                val parent = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    DocumentsContract.getTreeDocumentId(treeUri)
                )
                val fileUri = DocumentsContract.createDocument(
                    contentResolver, parent, "application/json", fileName
                ) ?: throw IllegalStateException("Gagal membuat file di folder tujuan")
                val stream = contentResolver.openOutputStream(fileUri, "wt")
                    ?: throw IllegalStateException("Gagal membuka file untuk ditulis")
                stream.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                val savedName = displayName(fileUri) ?: fileName
                runOnUiThread { result.success(savedName) }
            } catch (e: Exception) {
                runOnUiThread { result.error("write_failed", e.message, null) }
            }
        }.start()
    }

    private fun listFiles(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        if (treeUriString == null) {
            result.error("args", "treeUri kosong", null)
            return
        }
        try {
            val treeUri = Uri.parse(treeUriString)
            val parentId = DocumentsContract.getTreeDocumentId(treeUri)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
            val items = ArrayList<Map<String, String>>()
            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME
                ),
                null, null, null
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    items.add(
                        mapOf(
                            "documentId" to (cursor.getString(0) ?: ""),
                            "name" to (cursor.getString(1) ?: "")
                        )
                    )
                }
            }
            result.success(items)
        } catch (e: Exception) {
            result.error("list_failed", e.message, null)
        }
    }

    private fun deleteFile(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        val documentId = call.argument<String>("documentId")
        if (treeUriString == null || documentId == null) {
            result.error("args", "Argumen tidak lengkap", null)
            return
        }
        try {
            val docUri = DocumentsContract.buildDocumentUriUsingTree(
                Uri.parse(treeUriString),
                documentId
            )
            DocumentsContract.deleteDocument(contentResolver, docUri)
            result.success(null)
        } catch (e: Exception) {
            result.error("delete_failed", e.message, null)
        }
    }

    private fun releaseFolder(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        if (treeUriString != null) {
            try {
                contentResolver.releasePersistableUriPermission(
                    Uri.parse(treeUriString),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (e: Exception) {
                // Izin sudah tidak ada; tidak masalah.
            }
        }
        result.success(null)
    }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }
}
