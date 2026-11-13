package dk.nota.flutterreadium.fragments

import android.animation.ValueAnimator
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import dk.nota.flutterreadium.PluginLog
import kotlin.math.abs

/** A covered, two-page preview. Only a completed turn may publish the destination locator. */
internal class PageFlip(
    private val root: () -> ViewGroup?,
    private val background: () -> Int,
    private val onBegin: () -> Unit = {},
    private val onEnd: (Boolean) -> Unit = {},
) {
    private var curl: PageCurlView? = null
    private var animator: ValueAnimator? = null
    private var restoreOrigin: (() -> Unit)? = null
    private var forward = true
    private var ready = false
    private var capturing = false
    private var started = false
    private var interactive = false
    private var amount = 0f
    private var released: Boolean? = null
    private var deadline: Runnable? = null
    private var pending = false
    private var generation = 0
    var restoring = false
        private set
    val active: Boolean get() = curl != null || pending

    fun turn(
        forward: Boolean,
        restore: () -> Unit,
        turn: () -> Boolean,
    ): Boolean {
        if (active && !ready) return false
        if (active) finish(commit = true, restore = false)
        return begin(forward, false, restore, turn)
    }

    fun drag(
        forward: Boolean,
        restore: () -> Unit,
        turn: () -> Boolean,
    ): Boolean {
        if (active) return false
        return begin(forward, true, restore, turn)
    }

    private fun begin(
        forward: Boolean,
        interactive: Boolean,
        restore: () -> Unit,
        turn: () -> Boolean,
    ): Boolean {
        val host = root() ?: return if (interactive) false else turn()
        if (host.width == 0 || host.height == 0) return false
        this.forward = forward
        this.interactive = interactive
        restoreOrigin = restore
        ready = false
        capturing = false
        started = false
        restoring = false
        amount = 0f
        released = if (interactive) null else true
        val id = ++generation
        pending = true
        // The live page is unchanged until the cover is attached, so an asynchronous copy is safe.
        capture(host, cover = null) { old ->
            if (id != generation || !pending) return@capture
            pending = false
            attach(host, old, turn)
        }
        return true
    }

    private fun attach(
        host: ViewGroup,
        old: Bitmap,
        turn: () -> Boolean,
    ) {
        val view =
            PageCurlView(host.context, background()).apply {
                front = old
                if (!forward) under = old
                progress = if (forward) 0f else 1f
            }
        // Cover first. Changing the live page before attaching this view exposes new text early.
        host.addView(view, FrameLayout.LayoutParams(host.width, host.height))
        curl = view
        onBegin()
        armDeadline(host)
        host.postOnAnimation {
            if (curl === view) {
                started = true
                if (!turn()) finish(commit = false, restore = false)
            }
        }
    }

    /**
     * For on-device tests: what the curl is drawing. "Ink" is the share of sampled pixels clearly
     * darker than the page colour, so a blank capture (paper only) reads as ~0.
     */
    fun debugState(): Map<String, Any> {
        val view = curl ?: return mapOf("active" to false)
        val front = view.front
        val under = view.under
        return mapOf(
            "active" to true,
            "ready" to ready,
            "frontInk" to inkOf(front),
            "underInk" to inkOf(under),
            "pagesDiffer" to (front != null && under != null && differ(front, under)),
        )
    }

    private fun inkOf(bitmap: Bitmap?): Double {
        if (bitmap == null) return 0.0
        val paper = luminance(background())
        var ink = 0
        var total = 0
        sample(bitmap) { x, y ->
            total++
            if (paper - luminance(bitmap.getPixel(x, y)) > 60) ink++
        }
        return if (total == 0) 0.0 else ink.toDouble() / total
    }

    private fun differ(
        a: Bitmap,
        b: Bitmap,
    ): Boolean {
        if (a.width != b.width || a.height != b.height) return true
        var changed = 0
        sample(a) { x, y -> if (abs(luminance(a.getPixel(x, y)) - luminance(b.getPixel(x, y))) > 60) changed++ }
        return changed > 20
    }

    private inline fun sample(
        bitmap: Bitmap,
        each: (Int, Int) -> Unit,
    ) {
        val step = 6
        for (y in 0 until bitmap.height step step) for (x in 0 until bitmap.width step step) each(x, y)
    }

    private fun luminance(c: Int) = (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000

    /** Called by the navigator's actual page callback, never by a fixed render delay. */
    fun pageReady(isOrigin: Boolean) {
        val view = curl ?: return
        val host = view.parent as? ViewGroup ?: return
        if (!started) return
        if (restoring) {
            if (isOrigin) finish(commit = false, restore = false)
            return
        }
        if (isOrigin || ready || capturing) return
        capturing = true
        host.postOnAnimation {
            host.postOnAnimation {
                if (curl !== view || restoring) return@postOnAnimation
                capture(host, cover = view) { destination ->
                    if (curl !== view || restoring) return@capture
                    if (forward) view.under = destination else view.front = destination
                    ready = true
                    deadline?.let { host.removeCallbacks(it) }
                    drawProgress()
                    released?.let { settle(it) }
                }
            }
        }
    }

    fun update(progress: Float) {
        if (!interactive || restoring) return
        amount = progress.coerceIn(0f, 1f)
        if (ready) drawProgress()
    }

    fun release(commit: Boolean) {
        if (!interactive || restoring) return
        released = commit
        if (ready) settle(commit)
    }

    private fun drawProgress() {
        curl?.progress = if (forward) amount else 1f - amount
    }

    private fun settle(commit: Boolean) {
        val view = curl ?: return
        animator?.removeAllListeners()
        animator?.cancel()
        val end = if (commit) 1f else 0f
        animator =
            ValueAnimator.ofFloat(amount, end).apply {
                duration = (260 * abs(end - amount)).toLong().coerceAtLeast(70)
                interpolator = PathInterpolator(0.25f, 0f, 0.2f, 1f)
                addUpdateListener {
                    amount = it.animatedValue as Float
                    drawProgress()
                }
                addListener(
                    object : android.animation.AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: android.animation.Animator) {
                            if (curl !== view) return
                            if (commit) {
                                finish(commit = true, restore = false)
                            } else {
                                restoring = true
                                (view.parent as? ViewGroup)?.let { armDeadline(it) }
                                restoreOrigin?.invoke()
                            }
                        }
                    },
                )
                start()
            }
    }

    private fun armDeadline(host: ViewGroup) {
        deadline?.let { host.removeCallbacks(it) }
        deadline = Runnable { finish() }.also { host.postDelayed(it, 4000) }
    }

    /** Roll back on interruption. Explicit jumps can discard the preview without restoring it. */
    fun finish(
        commit: Boolean = false,
        restore: Boolean = true,
    ) {
        if (pending) {
            // Still copying the origin: nothing is covered or moved yet, so just drop the turn.
            pending = false
            generation++
            restoreOrigin = null
            return
        }
        val view = curl ?: return
        val host = view.parent as? ViewGroup
        deadline?.let { host?.removeCallbacks(it) }
        deadline = null
        animator?.removeAllListeners()
        animator?.cancel()
        animator = null
        if (!commit && restore) restoreOrigin?.invoke()
        curl = null
        restoreOrigin = null
        restoring = false
        host?.removeView(view)
        view.front = null
        view.under = null
        onEnd(commit)
    }

    /**
     * The screen as the reader sees it, without the curl. The reader is a texture-layer platform
     * view composited into Flutter's SurfaceView, which View.draw on a software canvas cannot see
     * (that produced blank sheets with the live page showing through). PixelCopy reads that
     * surface; the curl lives in the window surface, so it never needs hiding. Hosts without a
     * SurfaceView (or a failed copy) fall back to drawing the views, with [cover] hidden.
     */
    private fun capture(
        host: ViewGroup,
        cover: View?,
        done: (Bitmap) -> Unit,
    ) {
        val surface = findSurface(host)
        if (surface == null || surface.width == 0 || surface.height == 0) {
            done(snapshot(host, cover))
            return
        }
        try {
            val shot = Bitmap.createBitmap(surface.width, surface.height, Bitmap.Config.ARGB_8888)
            PixelCopy.request(surface, shot, { result ->
                done(if (result == PixelCopy.SUCCESS) place(host, surface, shot) else snapshot(host, cover))
            }, Handler(Looper.getMainLooper()))
        } catch (e: Throwable) {
            PluginLog.w("PageFlip", "::capture could not copy the surface")
            done(snapshot(host, cover))
        }
    }

    private fun findSurface(view: View): SurfaceView? {
        if (view is SurfaceView && view.isShown) return view
        if (view !is ViewGroup) return null
        for (i in 0 until view.childCount) findSurface(view.getChildAt(i))?.let { return it }
        return null
    }

    /** The surface copy positioned on a host-sized page. */
    private fun place(
        host: View,
        surface: View,
        shot: Bitmap,
    ): Bitmap {
        if (surface.width == host.width && surface.height == host.height) return shot
        val at = IntArray(2).also { surface.getLocationInWindow(it) }
        val origin = IntArray(2).also { host.getLocationInWindow(it) }
        return Bitmap.createBitmap(host.width, host.height, Bitmap.Config.ARGB_8888).also {
            val canvas = Canvas(it)
            canvas.drawColor(background())
            canvas.drawBitmap(shot, (at[0] - origin[0]).toFloat(), (at[1] - origin[1]).toFloat(), null)
        }
    }

    private fun snapshot(
        page: View,
        cover: View?,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(background())
        cover?.visibility = View.INVISIBLE
        try {
            page.draw(canvas)
        } catch (e: Throwable) {
            PluginLog.w("PageFlip", "::snapshot could not draw the page")
        } finally {
            cover?.visibility = View.VISIBLE
        }
        return bitmap
    }

    companion object {
        fun colorOr(
            css: String?,
            fallback: Int = Color.WHITE,
        ): Int = css?.let { runCatching { Color.parseColor(it) }.getOrNull() } ?: fallback
    }
}
