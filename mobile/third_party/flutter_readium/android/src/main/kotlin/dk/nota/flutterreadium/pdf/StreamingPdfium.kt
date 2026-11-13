/*
 * Quill patch (see mobile/third_party/PATCHES.md). Based on Readium kotlin-toolkit 3.4.0
 * PdfiumDocumentFactory, PdfiumDocumentFragment and PdfiumEngineProvider (BSD-3-Clause,
 * Copyright 2022 Readium Foundation).
 *
 * Readium opens a PDF straight from disk only for file:// resources; content:// books fall back
 * to reading the whole file into one ByteArray, which runs out of memory for large PDFs and can
 * never hold one over 2 GiB. Here PDFium opens content:// and file:// PDFs from a file descriptor.
 */
@file:OptIn(InternalReadiumApi::class, ExperimentalReadiumApi::class)

package dk.nota.flutterreadium.pdf

import android.content.Context
import android.graphics.PointF
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.lifecycleScope
import com.github.barteksc.pdfviewer.PDFView
import com.shockwave.pdfium.PdfiumCore
import java.io.File
import kotlin.math.roundToInt
import kotlin.reflect.KClass
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.readium.adapter.pdfium.document.PdfiumDocument
import org.readium.adapter.pdfium.document.PdfiumDocumentFactory
import org.readium.adapter.pdfium.navigator.PdfiumEngineProvider
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.adapter.pdfium.navigator.PdfiumPreferencesEditor
import org.readium.adapter.pdfium.navigator.PdfiumSettings
import org.readium.r2.navigator.OverflowableNavigator
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.pdf.PdfDocumentFragment
import org.readium.r2.navigator.pdf.PdfDocumentFragmentInput
import org.readium.r2.navigator.pdf.PdfEngineProvider
import org.readium.r2.navigator.preferences.Axis
import org.readium.r2.navigator.preferences.Fit
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.navigator.util.SingleFragmentFactory
import org.readium.r2.navigator.util.createFragmentFactory
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.SingleJob
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.data.ReadTry
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.pdf.PdfDocumentFactory
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.toDebugDescription

private const val TAG = "QuillPdf"

class StreamingPdfiumDocumentFactory(context: Context) : PdfDocumentFactory<PdfiumDocument> {
    private val context = context.applicationContext
    private val core by lazy { PdfiumCore(this.context) }
    private val fallback by lazy { PdfiumDocumentFactory(this.context) }

    override val documentType: KClass<PdfiumDocument> = PdfiumDocument::class

    override suspend fun open(resource: Resource, password: String?): ReadTry<PdfiumDocument> {
        val url = resource.sourceUrl?.toString()
        val opened = url?.let { openDescriptor(it, password) }
        if (opened != null) return Try.success(opened)
        Log.d(TAG, "byte fallback for ${url?.substringAfterLast('/')}")
        return fallback.open(resource, password)
    }

    // Null when this source cannot be opened by descriptor; the caller then uses Readium's path.
    private suspend fun openDescriptor(url: String, password: String?): PdfiumDocument? =
        withContext(Dispatchers.IO) {
            try {
                val descriptor =
                    when {
                        url.startsWith("content://") ->
                            context.contentResolver.openFileDescriptor(Uri.parse(url), "r")
                        url.startsWith("file://") ->
                            ParcelFileDescriptor.open(File(Uri.parse(url).path!!), ParcelFileDescriptor.MODE_READ_ONLY)
                        else -> null
                    } ?: return@withContext null
                // PDFium owns the descriptor from here and closes it with the document.
                val document = core.newDocument(descriptor, password)
                // Readium hashes the whole file for an identifier; Quill never uses it, and
                // hashing gigabytes would stall every open.
                PdfiumDocument(core, document, identifier = null, pageCount = core.getPageCount(document))
            } catch (e: Exception) {
                Log.w(TAG, "descriptor open failed, using byte fallback", e)
                null
            }
        }
}

// Readium's PdfiumDocumentFragment with StreamingPdfiumDocumentFactory; its constructor is internal.
class StreamingPdfiumDocumentFragment internal constructor(
    private val publication: Publication,
    private val href: Url,
    private val initialPageIndex: Int,
    initialSettings: PdfiumSettings,
    private val listener: Listener?,
) : PdfDocumentFragment<PdfiumSettings>() {
    // Used by the FragmentManager on restore (readium/kotlin-toolkit#395).
    constructor() : this(
        publication =
            Publication(
                manifest = Manifest(metadata = Metadata(identifier = "readium:dummy", localizedTitle = LocalizedString(""))),
            ),
        href = Url("publication.pdf")!!,
        initialPageIndex = 0,
        initialSettings =
            PdfiumSettings(
                fit = Fit.WIDTH,
                pageSpacing = 0.0,
                readingProgression = ReadingProgression.LTR,
                scroll = true,
                scrollAxis = Axis.VERTICAL,
            ),
        listener = null,
    )

    internal interface Listener {
        fun onResourceLoadFailed(
            href: Url,
            error: ReadError,
        )

        fun onTap(point: PointF): Boolean
    }

    private lateinit var pdfView: PDFView
    private lateinit var resetJob: SingleJob
    private var pageCount = 0
    private var settings: PdfiumSettings = initialSettings
    private val currentPageIndex = MutableStateFlow(initialPageIndex)

    override val pageIndex: StateFlow<Int> = currentPageIndex.asStateFlow()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View = PDFView(inflater.context, null).also { pdfView = it }

    override fun onViewCreated(
        view: View,
        savedInstanceState: Bundle?,
    ) {
        super.onViewCreated(view, savedInstanceState)
        resetJob = SingleJob(viewLifecycleOwner.lifecycleScope)
        reset(pageIndex = initialPageIndex)
    }

    private fun reset(pageIndex: Int = currentPageIndex.value) {
        if (view == null) return
        val context = context?.applicationContext ?: return

        resetJob.launch {
            val resource = requireNotNull(publication.get(href))
            // PDFium crashes when reusing the same PdfDocument, so it is opened afresh each time.
            val document =
                StreamingPdfiumDocumentFactory(context)
                    .open(resource, null)
                    .getOrElse { error ->
                        Log.e(TAG, error.toDebugDescription())
                        listener?.onResourceLoadFailed(href, error)
                        return@launch
                    }

            pageCount = document.pageCount
            val page = toView(pageIndex)

            pdfView.recycle()
            pdfView
                .fromSource { _, _, _ -> document.document }
                .apply {
                    // AndroidPdfViewer has no right-to-left mode; give the pages in reverse.
                    if (isReversed) pages(*((pageCount - 1) downTo 0).toList().toIntArray())
                }.swipeHorizontal(isHorizontal)
                .spacing(settings.pageSpacing.roundToInt())
                .pageSnap(!settings.scroll)
                .pageFling(!settings.scroll)
                .defaultPage(page)
                .onRender {
                    if (settings.fit == Fit.WIDTH) {
                        pdfView.fitToWidth(page)
                        // fitToWidth often breaks defaultPage, so jump to the page again.
                        pdfView.jumpTo(page, false)
                    }
                }.onPageChange { index, _ -> currentPageIndex.value = fromView(index) }
                .onTap { event -> listener?.onTap(PointF(event.x, event.y)) ?: false }
                .load()
        }
    }

    override fun goToPageIndex(
        index: Int,
        animated: Boolean,
    ): Boolean {
        if (index !in 0 until pageCount) return false
        pdfView.jumpTo(toView(index), animated)
        return true
    }

    private val isHorizontal: Boolean get() = !settings.scroll || settings.scrollAxis == Axis.HORIZONTAL

    private val isReversed: Boolean get() = isHorizontal && settings.readingProgression == ReadingProgression.RTL

    private fun toView(pageIndex: Int): Int = if (isReversed) (pageCount - 1) - pageIndex else pageIndex

    private fun fromView(viewPageIndex: Int): Int = if (isReversed) (pageCount - 1) - viewPageIndex else viewPageIndex

    override fun applySettings(settings: PdfiumSettings) {
        if (this.settings == settings) return
        this.settings = settings
        reset()
    }
}

// Readium's PdfiumEngineProvider, creating StreamingPdfiumDocumentFragment.
class StreamingPdfiumEngineProvider(
    private val delegate: PdfiumEngineProvider = PdfiumEngineProvider(),
) : PdfEngineProvider<PdfiumSettings, PdfiumPreferences, PdfiumPreferencesEditor> {
    override fun createDocumentFragmentFactory(
        input: PdfDocumentFragmentInput<PdfiumSettings>,
    ): SingleFragmentFactory<StreamingPdfiumDocumentFragment> =
        createFragmentFactory {
            StreamingPdfiumDocumentFragment(
                publication = input.publication,
                href = input.href,
                initialPageIndex = input.pageIndex,
                initialSettings = input.settings,
                listener =
                    object : StreamingPdfiumDocumentFragment.Listener {
                        override fun onResourceLoadFailed(
                            href: Url,
                            error: ReadError,
                        ) {
                            input.navigatorListener?.onResourceLoadFailed(href, error)
                        }

                        override fun onTap(point: PointF): Boolean = input.inputListener?.onTap(TapEvent(point)) ?: false
                    },
            )
        }

    override fun computeSettings(
        metadata: Metadata,
        preferences: PdfiumPreferences,
    ): PdfiumSettings = delegate.computeSettings(metadata, preferences)

    override fun computeOverflow(settings: PdfiumSettings): OverflowableNavigator.Overflow = delegate.computeOverflow(settings)

    override fun createPreferenceEditor(
        publication: Publication,
        initialPreferences: PdfiumPreferences,
    ): PdfiumPreferencesEditor = delegate.createPreferenceEditor(publication, initialPreferences)

    override fun createEmptyPreferences(): PdfiumPreferences = delegate.createEmptyPreferences()
}
