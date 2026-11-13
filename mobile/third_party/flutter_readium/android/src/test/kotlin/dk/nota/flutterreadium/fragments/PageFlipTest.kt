package dk.nota.flutterreadium.fragments

import android.app.Activity
import android.graphics.Color
import android.os.Looper
import android.widget.FrameLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w400dp-h600dp-mdpi")
@LooperMode(LooperMode.Mode.PAUSED)
class PageFlipTest {
    private fun frame(ms: Long = 80) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))

    private fun preview(
        forward: Boolean,
        check: (PageFlip, FrameLayout, MutableList<Boolean>) -> Unit,
    ) {
        val controller = Robolectric.buildActivity(Activity::class.java).setup().visible()
        val host = FrameLayout(controller.get()).apply { setBackgroundColor(Color.RED) }
        controller.get().setContentView(host)
        frame()
        host.layout(0, 0, 400, 600)
        val settled = mutableListOf<Boolean>()
        lateinit var flip: PageFlip
        flip = PageFlip({ host }, { Color.WHITE }, onEnd = { settled.add(it) })
        assertTrue(
            flip.drag(forward, restore = {
                host.setBackgroundColor(Color.RED)
                flip.pageReady(isOrigin = true)
            }) {
                assertEquals("the old page covers the destination before navigation", 1, host.childCount)
                host.setBackgroundColor(Color.BLUE)
                true
            },
        )
        frame()
        flip.pageReady(isOrigin = false)
        frame()
        check(flip, host, settled)
        flip.finish()
        controller.pause().stop().destroy()
    }

    @Test
    fun heldForwardTurnRetainsBothPagesWithoutCommitting() =
        preview(true) { flip, host, settled ->
            flip.update(.5f)
            frame(2000)
            val view = host.getChildAt(0) as PageCurlView
            assertEquals(.5f, view.progress, .001f)
            assertEquals(Color.RED, view.front!!.getPixel(10, 10))
            assertEquals(Color.BLUE, view.under!!.getPixel(10, 10))
            assertTrue(flip.active)
            assertTrue(settled.isEmpty())
        }

    @Test
    fun releaseCommitsOnceAndDropsTheOverlay() =
        preview(true) { flip, host, settled ->
            flip.update(.6f)
            flip.release(true)
            frame(500)
            assertEquals(listOf(true), settled)
            assertFalse(flip.active)
            assertEquals(0, host.childCount)
        }

    @Test
    fun reversedTurnRestoresOriginWithoutCommittingDestination() =
        preview(true) { flip, host, settled ->
            flip.update(.7f)
            flip.update(.1f)
            flip.release(false)
            frame(500)
            assertEquals(listOf(false), settled)
            assertFalse(flip.active)
            assertEquals(0, host.childCount)
        }

    @Test
    fun backwardPreviewUsesDestinationAsTurningSheetAndOriginalUnderneath() =
        preview(false) { flip, host, settled ->
            flip.update(.4f)
            frame(1000)
            val view = host.getChildAt(0) as PageCurlView
            assertEquals(.6f, view.progress, .001f)
            assertEquals(Color.BLUE, view.front!!.getPixel(10, 10))
            assertEquals(Color.RED, view.under!!.getPixel(10, 10))
            assertTrue(settled.isEmpty())
        }
}
