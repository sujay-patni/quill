package dk.nota.flutterreadium.fragments

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.widget.FrameLayout
import kotlin.math.abs

/** Horizontal page preview follows the pointer; vertical gestures and long presses remain native. */
class SwipeTurnLayout
    @JvmOverloads
    constructor(
        context: Context,
        attrs: AttributeSet? = null,
    ) : FrameLayout(context, attrs) {
        var enabled: () -> Boolean = { false }
        var interactive: () -> Boolean = { false }
        var onSwipe: ((Boolean) -> Unit)? = null
        var onBegin: ((Boolean) -> Boolean)? = null
        var onProgress: ((Float) -> Unit)? = null
        var onRelease: ((Boolean) -> Unit)? = null
        private val config = ViewConfiguration.get(context)
        private var downX = 0f
        private var downY = 0f
        private var downTime = 0L
        private var swiping = false
        private var preview = false
        private var forward = true
        private var tracker: VelocityTracker? = null

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
            if (!enabled()) return false
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    tracker?.recycle()
                    tracker = VelocityTracker.obtain().also { it.addMovement(ev) }
                    downX = ev.x
                    downY = ev.y
                    downTime = ev.eventTime
                    swiping = false
                    preview = false
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.x - downX
                    if (!swiping &&
                        ev.pointerCount == 1 &&
                        ev.eventTime - downTime < ViewConfiguration.getLongPressTimeout() &&
                        abs(dx) > config.scaledTouchSlop &&
                        abs(dx) > abs(ev.y - downY) * 1.5f
                    ) {
                        forward = dx < 0
                        swiping = true
                        preview = interactive() && onBegin?.invoke(forward) == true
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    tracker?.recycle()
                    tracker = null
                    swiping = false
                }
            }
            return swiping
        }

        override fun onTouchEvent(ev: MotionEvent): Boolean {
            if (!swiping) return super.onTouchEvent(ev)
            tracker?.addMovement(ev)
            val dx = ev.x - downX
            val direction = if (forward) -1f else 1f
            val progress = (dx * direction / width.coerceAtLeast(1)).coerceIn(0f, 1f)
            when (ev.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    if (preview) onProgress?.invoke(progress)
                }

                MotionEvent.ACTION_UP -> {
                    tracker?.computeCurrentVelocity(1000)
                    val velocity = (tracker?.xVelocity ?: 0f) * direction
                    if (preview) {
                        onProgress?.invoke(progress)
                        onRelease?.invoke(
                            velocity > config.scaledMinimumFlingVelocity * 4 ||
                                (progress > .35f && velocity > -config.scaledMinimumFlingVelocity * 4),
                        )
                    } else if (!interactive() && (abs(dx) > width * .12f || velocity > config.scaledMinimumFlingVelocity * 4)) {
                        onSwipe?.invoke(forward)
                    }
                    swiping = false
                    tracker?.recycle()
                    tracker = null
                }

                MotionEvent.ACTION_CANCEL -> {
                    if (preview) onRelease?.invoke(false)
                    swiping = false
                    tracker?.recycle()
                    tracker = null
                }
            }
            return true
        }
    }
