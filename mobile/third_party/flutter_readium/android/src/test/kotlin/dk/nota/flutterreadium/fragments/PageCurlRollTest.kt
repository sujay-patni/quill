package dk.nota.flutterreadium.fragments

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class PageCurlRollTest {
    private val w = 400f
    private val h = 600f

    private fun at(
        roll: PageCurlView.Roll,
        x: Float,
        y: Float,
        side: PageCurlView.Roll.Side,
    ) = FloatArray(2).also { roll.project(x, y, side, it) }

    @Test
    fun theRolledCornerLandsWhereTheTurnHasPulledIt() {
        for (p in listOf(.05f, .3f, .5f, .8f)) {
            val roll = PageCurlView.Roll.at(p, w, h, maxRadius = 44f)
            val corner = at(roll, w, h, PageCurlView.Roll.Side.BACK)
            assertEquals("x at $p", w - p * 2 * w, corner[0], .5f)
            assertEquals("y at $p", h - h * .16f * sin(PI * p).toFloat(), corner[1], .5f)
        }
    }

    @Test
    fun theFarSideStaysFlatAndTheTwoSidesMeetAtTheCrest() {
        val roll = PageCurlView.Roll.at(.4f, w, h, maxRadius = 44f)
        val flat = at(roll, 0f, 0f, PageCurlView.Roll.Side.FRONT)
        assertEquals(0f, flat[0], 1e-3f)
        assertEquals(0f, flat[1], 1e-3f)
        // Points a quarter turn past the axis are the crest on both sides of the sheet.
        val q = (PI * roll.r / 2).toFloat()
        val x = roll.ax + roll.nx * q
        val y = roll.ay + roll.ny * q
        val front = at(roll, x, y, PageCurlView.Roll.Side.FRONT)
        val back = at(roll, x, y, PageCurlView.Roll.Side.BACK)
        assertEquals(front[0], back[0], 1e-2f)
        assertEquals(front[1], back[1], 1e-2f)
        assertEquals(roll.ax + roll.nx * roll.r, front[0], 1e-2f)
    }
}
