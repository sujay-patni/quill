package app.quill.reader

import android.app.Activity
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.provider.DocumentsContract
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream

// Readium's reader view needs a FlutterFragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    private val pickFolderRequest = 4101
    private var pendingPick: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val bookIo = Executors.newSingleThreadExecutor()
    private val comicIo = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native reader: a book file's bytes, on its own thread so cover building never delays an open.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.quill/books").setMethodCallHandler { call, result ->
            if (call.method != "read" && call.method != "cbrToCbz") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uri = Uri.parse(call.argument<String>("uri").orEmpty())
            val out = call.argument<String>("out").orEmpty()
            // Rewriting a large comic takes a while; it has its own thread so no other book waits for it.
            (if (call.method == "read") bookIo else comicIo).execute {
                try {
                    val value: Any =
                        if (call.method == "read") open(uri).use { readCapped(it, 512 shl 20) } else cbrToCbz(uri, File(out))
                    runOnUiThread { result.success(value) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("book", e.message ?: e.javaClass.simpleName, null) }
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.quill/folders").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pickFolder(result)
                "hasAccess" -> result.success(hasAccess(call.argument<String>("uri").orEmpty()))
                "scan" -> {
                    val uri = call.argument<String>("uri").orEmpty()
                    io.execute {
                        try {
                            val files = scan(Uri.parse(uri))
                            runOnUiThread { result.success(files) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("scan", e.message ?: "Unable to read this folder.", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Reader: screen brightness, keep-awake and volume-key page turns while a book is open.
        reader =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.quill/reader").apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "brightness" -> {
                            // -1 hands brightness back to the system.
                            val v = (call.arguments as? Double ?: -1.0).toFloat()
                            window.attributes =
                                window.attributes.apply {
                                    screenBrightness =
                                        if (v < 0) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else v.coerceIn(0.01f, 1f)
                                }
                            result.success(null)
                        }
                        "battery" -> {
                            val manager = getSystemService(BATTERY_SERVICE) as android.os.BatteryManager
                            result.success(manager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY))
                        }
                        "systemBrightness" -> {
                            // Approximate: Android stores 0..255 (adaptive brightness is non-linear).
                            val raw =
                                android.provider.Settings.System.getInt(
                                    contentResolver,
                                    android.provider.Settings.System.SCREEN_BRIGHTNESS,
                                    128,
                                )
                            result.success((raw / 255.0).coerceIn(0.02, 1.0))
                        }
                        "keepAwake" -> {
                            if (call.arguments == true) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(null)
                        }
                        "volumeKeys" -> {
                            volumeKeys = call.arguments == true
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        // Moon Reader migration: pick a .mrstd backup, then read only the allowlisted parts.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.quill/moon").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pickFile(result)
                "read" -> {
                    val uri = Uri.parse(call.argument<String>("uri").orEmpty())
                    io.execute {
                        try {
                            val value = readMoonBackup(uri)
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("moon", e.message ?: e.javaClass.simpleName, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Backups: save a file from Quill's cache where the reader chooses, or copy a chosen file in.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.quill/backup").setMethodCallHandler { call, result ->
            when (call.method) {
                "save" ->
                    saveDocument(
                        call.argument<String>("path").orEmpty(),
                        call.argument<String>("name").orEmpty(),
                        call.argument<String>("mime") ?: "application/octet-stream",
                        result,
                    )
                "open" -> openDocument(result)
                // A web page in the browser (or the app that handles it, such as Goodreads).
                "openUrl" -> {
                    val uri = Uri.parse(call.argument<String>("url").orEmpty())
                    val opened =
                        uri.scheme == "https" &&
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                true
                            } catch (e: Exception) {
                                false
                            }
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.quill/covers").setMethodCallHandler { call, result ->
            if (call.method == "pickImage") {
                pickImage(result)
                return@setMethodCallHandler
            }
            val uri = Uri.parse(call.argument<String>("uri").orEmpty())
            val out = call.argument<String>("out").orEmpty()
            val maxWidth = call.argument<Int>("maxWidth") ?: 480
            coverIo.execute {
                try {
                    val value: Any? =
                        when (call.method) {
                            "zipIndex" -> zipIndex(uri)
                            "zipImage" -> zipImage(uri, call.argument<String>("entry").orEmpty(), maxWidth, File(out))
                            "pdfImage" -> pdfImage(uri, maxWidth, File(out))
                            "cbrImage" -> cbrImage(uri, maxWidth, File(out))
                            // A cover the user chose: any image file, scaled down and saved as JPEG.
                            "imageFile" -> writeJpeg(decodeScaled(open(uri).use { readCapped(it, 40 shl 20) }, maxWidth), File(out))
                            else -> null
                        }
                    runOnUiThread { if (call.method in coverMethods) result.success(value) else result.notImplemented() }
                } catch (e: Exception) {
                    runOnUiThread { result.error("cover", e.message ?: e.javaClass.simpleName, null) }
                }
            }
        }
    }

    private var reader: MethodChannel? = null
    private var volumeKeys = false

    // While reading, volume down turns forward and volume up turns back (Moon Reader defaults).
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val forward =
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> true
                KeyEvent.KEYCODE_VOLUME_UP -> false
                else -> return super.dispatchKeyEvent(event)
            }
        if (!volumeKeys) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) reader?.invokeMethod("volumeKey", forward)
        return true
    }

    // Covers: books are only read. Results are small JPEGs written into Quill's own storage.
    private val coverIo = Executors.newSingleThreadExecutor()
    private val coverMethods = setOf("zipIndex", "zipImage", "pdfImage", "cbrImage", "imageFile")
    private val pickImageRequest = 4103
    private var pendingImage: MethodChannel.Result? = null

    private fun pickImage(result: MethodChannel.Result) {
        if (pendingImage != null) {
            result.error("busy", "A picker is already open.", null)
            return
        }
        pendingImage = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("image/*")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivityForResult(intent, pickImageRequest)
    }

    private fun open(uri: Uri): InputStream =
        if (uri.scheme == "content") {
            requireNotNull(contentResolver.openInputStream(uri)) { "Cannot open book." }
        } else {
            File(requireNotNull(uri.path)).inputStream()
        }

    // One pass: every entry name, plus the small text files that locate an EPUB's cover.
    private fun zipIndex(uri: Uri): Map<String, Any> {
        val names = mutableListOf<String>()
        val texts = mutableMapOf<String, String>()
        ZipInputStream(open(uri).buffered()).use { zip ->
            while (true) {
                val e = zip.nextEntry ?: break
                if (e.isDirectory) continue
                names += e.name
                require(names.size < 20000) { "Archive has too many entries." }
                val lower = e.name.lowercase()
                if (lower == "meta-inf/container.xml" ||
                    lower.endsWith(".opf")
                ) {
                    texts[e.name] = readCapped(zip, 2 shl 20).toString(Charsets.UTF_8)
                }
            }
        }
        return mapOf("names" to names, "texts" to texts)
    }

    // ---- CBR comics: a RAR archive of page images (or, often, a ZIP with the wrong name) ----

    private val comicPage = Regex(".*\\.(jpe?g|png|gif|webp|bmp)$", RegexOption.IGNORE_CASE)

    private fun comicKind(file: File): String {
        val head = ByteArray(8)
        val n = file.inputStream().use { it.read(head) }
        return when {
            n >= 2 && head[0] == 'P'.code.toByte() && head[1] == 'K'.code.toByte() -> "zip"
            n >= 8 && String(head, 0, 4, Charsets.ISO_8859_1) == "Rar!" && head[6].toInt() == 1 -> "rar5"
            n >= 7 && String(head, 0, 4, Charsets.ISO_8859_1) == "Rar!" -> "rar4"
            else -> "unknown"
        }
    }

    // Gives [block] the comic as a file (the RAR reader needs one) and what it is by its first
    // bytes. The original is read in place through its file descriptor when the system allows;
    // otherwise it is copied into Quill's cache first and the copy removed afterwards.
    private fun <T> withComic(
        uri: Uri,
        tag: String,
        block: (File, String) -> T,
    ): T {
        if (uri.scheme != "content") {
            val file = File(requireNotNull(uri.path))
            return block(file, comicKind(file))
        }
        contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
            val direct = File("/proc/self/fd/${descriptor.fd}")
            val kind =
                try {
                    comicKind(direct)
                } catch (e: Exception) {
                    null
                }
            if (kind != null) return block(direct, kind)
        }
        val dir = File(cacheDir, "cbr-work").apply { mkdirs() }
        val copy = File(dir, "$tag.bin")
        try {
            open(uri).use { input -> copy.outputStream().use { input.copyTo(it) } }
            return block(copy, comicKind(copy))
        } finally {
            copy.delete()
        }
    }

    private fun refuseComic(kind: String): Nothing =
        throw IllegalStateException(
            if (kind == "rar5") {
                "This comic uses RAR 5 compression, which Quill cannot open. Convert it to CBZ to read it."
            } else {
                "This file is not a comic archive Quill can read."
            },
        )

    private fun rarPages(archive: com.github.junrar.Archive): List<com.github.junrar.rarfile.FileHeader> {
        require(!archive.isEncrypted) { "This comic is password protected." }
        return archive.fileHeaders
            .filter { !it.isDirectory && !it.isEncrypted && comicPage.matches(it.fileName) }
            .sortedBy { it.fileName.replace('\\', '/').lowercase() }
    }

    // Writes the comic's pages as a CBZ (stored, not compressed again). Returns the page count.
    private fun cbrToCbz(
        uri: Uri,
        out: File,
    ): Int {
        require(out.canonicalPath.startsWith(cacheDir.canonicalPath + File.separator)) { "Bad output path." }
        // Asked for again while it was being made (the reader was reopened): it is ready now.
        if (out.isFile && out.length() > 0) return 0
        return withComic(uri, "convert") { copy, kind ->
            out.parentFile?.mkdirs()
            val temp = File(out.path + ".tmp")
            var pages = 0
            try {
                when (kind) {
                    "zip" -> {
                        copy.copyTo(temp, overwrite = true)
                        pages = java.util.zip.ZipFile(temp).use { zip -> zip.entries().asSequence().count { comicPage.matches(it.name) } }
                    }
                    "rar4" ->
                        com.github.junrar.Archive(copy).use { archive ->
                            java.util.zip.ZipOutputStream(temp.outputStream().buffered()).use { zip ->
                                zip.setLevel(java.util.zip.Deflater.NO_COMPRESSION)
                                for (header in rarPages(archive)) {
                                    zip.putNextEntry(java.util.zip.ZipEntry(header.fileName.replace('\\', '/')))
                                    archive.extractFile(header, zip)
                                    zip.closeEntry()
                                    pages++
                                }
                            }
                        }
                    else -> refuseComic(kind)
                }
                require(pages > 0) { "This comic has no pages Quill can show." }
                require(temp.renameTo(out)) { "The comic could not be prepared." }
                pages
            } finally {
                temp.delete()
            }
        }
    }

    // The first page of a CBR as a cover.
    private fun cbrImage(
        uri: Uri,
        maxWidth: Int,
        out: File,
    ): Boolean =
        withComic(uri, "cover") { copy, kind ->
            val bytes =
                when (kind) {
                    "zip" ->
                        java.util.zip.ZipFile(copy).use { zip ->
                            val first =
                                zip.entries().asSequence()
                                    .filter { !it.isDirectory && comicPage.matches(it.name) }
                                    .minByOrNull { it.name.lowercase() }
                            first?.let { e -> zip.getInputStream(e).use { readCapped(it, 40 shl 20) } }
                        }
                    "rar4" ->
                        com.github.junrar.Archive(copy).use { archive ->
                            rarPages(archive).firstOrNull()?.let { header ->
                                ByteArrayOutputStream().also { archive.extractFile(header, it) }.toByteArray()
                            }
                        }
                    else -> refuseComic(kind)
                }
            bytes != null && writeJpeg(decodeScaled(bytes, maxWidth), out)
        }

    private fun zipImage(
        uri: Uri,
        entry: String,
        maxWidth: Int,
        out: File,
    ): Boolean {
        ZipInputStream(open(uri).buffered()).use { zip ->
            while (true) {
                val e = zip.nextEntry ?: return false
                if (e.name == entry) return writeJpeg(decodeScaled(readCapped(zip, 40 shl 20), maxWidth), out)
            }
        }
    }

    private fun pdfImage(
        uri: Uri,
        maxWidth: Int,
        out: File,
    ): Boolean {
        val fd =
            if (uri.scheme == "content") {
                requireNotNull(contentResolver.openFileDescriptor(uri, "r")) { "Cannot open book." }
            } else {
                android.os.ParcelFileDescriptor.open(File(requireNotNull(uri.path)), android.os.ParcelFileDescriptor.MODE_READ_ONLY)
            }
        PdfRenderer(fd).use { pdf ->
            if (pdf.pageCount == 0) return false
            pdf.openPage(0).use { page ->
                val height = (maxWidth.toLong() * page.height / page.width).toInt().coerceIn(1, maxWidth * 3)
                val bitmap = Bitmap.createBitmap(maxWidth, height, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                return writeJpeg(bitmap, out)
            }
        }
    }

    private fun readCapped(
        input: InputStream,
        cap: Int,
    ): ByteArray {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(16384)
        while (true) {
            val n = input.read(chunk)
            if (n < 0) break
            buffer.write(chunk, 0, n)
            require(buffer.size() <= cap) { "Entry too large." }
        }
        return buffer.toByteArray()
    }

    private fun decodeScaled(
        bytes: ByteArray,
        maxWidth: Int,
    ): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxWidth) sample *= 2
        val decoded =
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        if (decoded.width <= maxWidth) return decoded
        val height = (decoded.height.toLong() * maxWidth / decoded.width).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(decoded, maxWidth, height, true)
    }

    private fun writeJpeg(
        bitmap: Bitmap?,
        out: File,
    ): Boolean {
        if (bitmap == null) return false
        out.parentFile?.mkdirs()
        val temp = File(out.path + ".tmp")
        FileOutputStream(temp).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        return temp.renameTo(out)
    }

    private val saveDocumentRequest = 4104
    private val openDocumentRequest = 4105
    private var pendingSave: MethodChannel.Result? = null
    private var pendingSaveSource: File? = null
    private var pendingOpen: MethodChannel.Result? = null

    // Only files in Quill's own cache or files folder can be saved out.
    private fun saveDocument(
        path: String,
        name: String,
        mime: String,
        result: MethodChannel.Result,
    ) {
        val source = File(path).canonicalFile
        val own = listOf(cacheDir, filesDir).any { source.path.startsWith(it.canonicalPath + File.separator) }
        if (!own || !source.isFile) {
            result.error("backup", "Nothing to save.", null)
            return
        }
        if (pendingSave != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }
        pendingSave = result
        pendingSaveSource = source
        val intent =
            Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(mime)
                .putExtra(Intent.EXTRA_TITLE, name)
        startActivityForResult(intent, saveDocumentRequest)
    }

    private fun openDocument(result: MethodChannel.Result) {
        if (pendingOpen != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }
        pendingOpen = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivityForResult(intent, openDocumentRequest)
    }

    private fun finishSave(uri: Uri?) {
        val result = pendingSave ?: return
        val source = pendingSaveSource
        pendingSave = null
        pendingSaveSource = null
        if (uri == null || source == null) {
            result.success(false)
            return
        }
        io.execute {
            try {
                requireNotNull(contentResolver.openOutputStream(uri, "wt")) { "Cannot write there." }.use { out ->
                    source.inputStream().use { it.copyTo(out) }
                }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("backup", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    // Copies the chosen file into Quill's cache (at most 256 MB) and returns that path.
    private fun finishOpen(uri: Uri?) {
        val result = pendingOpen ?: return
        pendingOpen = null
        if (uri == null) {
            result.success(null)
            return
        }
        io.execute {
            try {
                val dir = File(cacheDir, "restore").apply { mkdirs() }
                val copy = File(dir, "picked.bin")
                val cap = 256L shl 20
                requireNotNull(contentResolver.openInputStream(uri)) { "Cannot open that file." }.use { input ->
                    copy.outputStream().use { out ->
                        val chunk = ByteArray(65536)
                        var total = 0L
                        while (true) {
                            val n = input.read(chunk)
                            if (n < 0) break
                            total += n
                            require(total <= cap) { "That file is too large to be a Quill backup." }
                            out.write(chunk, 0, n)
                        }
                    }
                }
                runOnUiThread { result.success(copy.path) }
            } catch (e: Exception) {
                runOnUiThread { result.error("backup", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private val pickFileRequest = 4102
    private var pendingFile: MethodChannel.Result? = null

    private fun pickFile(result: MethodChannel.Result) {
        if (pendingFile != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }
        pendingFile = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivityForResult(intent, pickFileRequest)
    }

    // Reads a Moon Reader .mrstd backup (a ZIP of numbered .tag files named by _names.list).
    // Only mrbooks.db (books, statistics, notes) and positions10.xml are read; nothing else in
    // the backup is opened. The file is copied into Quill's cache, read, and the copies deleted.
    private fun readMoonBackup(uri: Uri): Map<String, Any?> {
        val work =
            File(cacheDir, "moon-import").apply {
                deleteRecursively()
                mkdirs()
            }
        try {
            val archive = File(work, "backup.zip")
            val digest = MessageDigest.getInstance("SHA-256")
            open(uri).use { input ->
                FileOutputStream(archive).use { out ->
                    val chunk = ByteArray(65536)
                    var total = 0L
                    while (true) {
                        val n = input.read(chunk)
                        if (n < 0) break
                        total += n
                        require(total <= 200L shl 20) { "This file is too large to be a Moon Reader backup." }
                        digest.update(chunk, 0, n)
                        out.write(chunk, 0, n)
                    }
                }
            }
            val hash = digest.digest().joinToString("") { "%02x".format(it) }
            ZipFile(archive).use { zip ->
                val namesEntry =
                    zip.entries().asSequence().firstOrNull { it.name.endsWith("_names.list") }
                        ?: error("This is not a Moon Reader backup (.mrstd).")
                val base = namesEntry.name.substringBeforeLast('/', "").let { if (it.isEmpty()) "" else "$it/" }
                val names =
                    zip
                        .getInputStream(namesEntry)
                        .use { readCapped(it, 1 shl 20) }
                        .toString(Charsets.UTF_8)
                        .lines()

                fun tag(suffix: String) =
                    names
                        .indexOfFirst { it.trim().endsWith(suffix) }
                        .takeIf { it >= 0 }
                        ?.let { zip.getEntry("$base${it + 1}.tag") }
                val dbEntry = tag("databases/mrbooks.db") ?: error("The backup has no Moon Reader library.")
                val db = File(work, "mrbooks.db")
                zip.getInputStream(dbEntry).use { input -> FileOutputStream(db).use { input.copyTo(it) } }
                require(db.length() <= 100L shl 20) { "The backup's library is too large." }
                val positions =
                    tag("shared_prefs/positions10.xml")?.let { e ->
                        zip.getInputStream(e).use { readCapped(it, 8 shl 20) }.toString(Charsets.UTF_8)
                    } ?: ""
                val sql = SQLiteDatabase.openDatabase(db.path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS)
                try {
                    fun rows(
                        table: String,
                        columns: List<String>,
                    ): List<Map<String, Any?>> {
                        val exists =
                            sql.rawQuery("select name from sqlite_master where type='table' and name=?", arrayOf(table)).use {
                                it.count >
                                    0
                            }
                        if (!exists) return emptyList()
                        val present =
                            sql.rawQuery("pragma table_info(\"$table\")", null).use { c ->
                                buildSet { while (c.moveToNext()) add(c.getString(1)) }
                            }
                        val wanted = columns.filter { it in present }
                        return sql.query(table, wanted.toTypedArray(), null, null, null, null, null).use { c ->
                            buildList {
                                while (c.moveToNext()) add(wanted.mapIndexed { i, name -> name to c.getString(i) }.toMap())
                            }
                        }
                    }
                    return mapOf(
                        "hash" to hash,
                        "books" to rows("books", listOf("filename", "book", "author", "description", "category", "addTime")),
                        "statistics" to rows("statistics", listOf("filename", "dates")),
                        "notes" to
                            rows(
                                "notes",
                                listOf(
                                    "filename",
                                    "lastChapter",
                                    "lastPosition",
                                    "highlightColor",
                                    "time",
                                    "original",
                                    "underline",
                                    "strikethrough",
                                ),
                            ),
                        "positions" to positions,
                    )
                } finally {
                    sql.close()
                }
            }
        } finally {
            work.deleteRecursively()
        }
    }

    // Android's folder picker. Access is kept across restarts; books are read in place.
    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A folder picker is already open.", null)
            return
        }
        pendingPick = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        startActivityForResult(intent, pickFolderRequest)
    }

    @Deprecated("Activity result API is not available to FlutterFragmentActivity channels here.")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickImageRequest) {
            val result = pendingImage ?: return
            pendingImage = null
            result.success(if (resultCode == Activity.RESULT_OK) data?.data?.toString() else null)
            return
        }
        if (requestCode == saveDocumentRequest) {
            finishSave(if (resultCode == Activity.RESULT_OK) data?.data else null)
            return
        }
        if (requestCode == openDocumentRequest) {
            finishOpen(if (resultCode == Activity.RESULT_OK) data?.data else null)
            return
        }
        if (requestCode == pickFileRequest) {
            val result = pendingFile ?: return
            pendingFile = null
            result.success(if (resultCode == Activity.RESULT_OK) data?.data?.toString() else null)
            return
        }
        if (requestCode != pickFolderRequest) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        result.success(uri.toString())
    }

    private fun hasAccess(uri: String) =
        uri.isNotEmpty() && contentResolver.persistedUriPermissions.any { it.uri.toString() == uri && it.isReadPermission }

    // Recursive listing of EPUB, PDF, CBR and CBZ files. Hidden entries are skipped.
    private fun scan(tree: Uri): List<Map<String, Any>> {
        require(hasAccess(tree.toString())) { "Folder access was lost. Select Books again to reconnect." }
        val found = mutableListOf<Map<String, Any>>()
        val columns =
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )

        fun walk(
            documentId: String,
            relative: String,
            depth: Int,
        ) {
            require(depth < 32 && found.size < 20000) { "Folder is too large or deeply nested." }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
            val cursor =
                contentResolver.query(children, columns, null, null, null)
                    ?: error("A subfolder could not be read. Previous library kept.")
            cursor.use {
                while (it.moveToNext()) {
                    val id = it.getString(0) ?: continue
                    val name = it.getString(1) ?: continue
                    if (name.startsWith('.')) continue
                    if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        walk(id, listOf(relative, name).filter { p -> p.isNotBlank() }.joinToString("/"), depth + 1)
                    } else if (name.substringAfterLast('.').lowercase() in setOf("epub", "pdf", "cbr", "cbz")) {
                        found +=
                            mapOf(
                                "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                                "name" to name,
                                "folder" to relative,
                                "size" to it.getLong(3),
                                "modified" to it.getLong(4),
                            )
                    }
                }
            }
        }
        walk(DocumentsContract.getTreeDocumentId(tree), "", 0)
        return found
    }
}
