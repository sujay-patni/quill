package dk.nota.flutterreadium.fragments

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.view.View
import kotlin.math.PI
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Quill patch: a rolled page curl, like Apple Books' (and Moon Reader's "Real page turning").
 * [front] is the page being turned; [under] (optional) is drawn beneath it.
 *
 * At [progress] 0 the page lies flat; at 1 it has turned fully over the left edge. The bottom
 * right corner is pulled toward (-w, h), rising a little mid-turn. Instead of folding along a
 * crease, the page wraps around a cylinder whose axis lies across the page: behind the axis it
 * stays flat, over the cylinder it curves up (front side visible, darkening toward the crest),
 * and past half a turn it lies back over the page showing its plain back with the print faintly
 * through. The page bitmap is warped with [Canvas.drawBitmapMesh].
 */
@SuppressLint("ViewConstructor")
internal class PageCurlView(
    context: Context,
    private val paper: Int,
) : View(context) {
    var front: Bitmap? = null
        set(value) {
            field = value
            back = null
        }
    var under: Bitmap? = null
    var progress = 0f
        set(value) {
            field = value
            invalidate()
        }

    // The page's back: paper with the print showing faintly through (drawn mirrored by the roll).
    private var back: Bitmap? = null
    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val shadePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val frontMesh = FloatArray((COLS + 1) * (ROWS + 1) * 2)
    private val backMesh = FloatArray((COLS + 1) * (ROWS + 1) * 2)

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onDraw(canvas: Canvas) {
        val page = front ?: return
        val w = width.toFloat()
        val h = height.toFloat()
        under?.let { canvas.drawBitmap(it, 0f, 0f, bitmapPaint) }

        val p = progress.coerceIn(0f, 1f)
        if (p <= 0.001f) {
            canvas.drawBitmap(page, 0f, 0f, bitmapPaint)
            return
        }
        if (p >= 0.999f) return

        val roll = Roll.at(p, w, h, maxRadius = 0.11f * min(w, h))
        roll.mesh(w, h, COLS, ROWS, frontMesh, Roll.Side.FRONT)
        roll.mesh(w, h, COLS, ROWS, backMesh, Roll.Side.BACK)

        // 1. Shadow the rolled page casts on the page underneath, beyond the crest.
        val crestX = roll.ax + roll.nx * roll.r
        val crestY = roll.ay + roll.ny * roll.r
        val reach = roll.r * 0.7f + 12f * density
        canvas.save()
        canvas.clipPath(halfPlane(crestX, crestY, roll.nx, roll.ny, w, h))
        shadePaint.shader =
            LinearGradient(crestX, crestY, crestX + roll.nx * reach, crestY + roll.ny * reach, 0x55000000, 0, Shader.TileMode.CLAMP)
        canvas.drawPaint(shadePaint)
        canvas.restore()

        // 2. The page itself: flat part and the side rising over the roll.
        canvas.drawBitmapMesh(page, COLS, ROWS, frontMesh, 0, null, 0, bitmapPaint)

        // 3. Light on the roll: bright where it faces up (near the axis), dark toward the crest.
        canvas.save()
        canvas.clipPath(strip(roll, w, h))
        shadePaint.shader =
            LinearGradient(
                roll.ax,
                roll.ay,
                crestX,
                crestY,
                intArrayOf(0x00000000, 0x12FFFFFF, 0x30000000, 0x66000000),
                floatArrayOf(0f, 0.35f, 0.8f, 1f),
                Shader.TileMode.CLAMP,
            )
        canvas.drawPaint(shadePaint)
        canvas.restore()

        // 4. The back, over everything it covers, lit like the far side of the roll.
        canvas.drawBitmapMesh(backOf(page), COLS, ROWS, backMesh, 0, null, 0, bitmapPaint)
        canvas.save()
        canvas.clipPath(halfPlane(crestX, crestY, -roll.nx, -roll.ny, w, h))
        val inner = roll.r * 1.4f + 8f * density
        shadePaint.shader =
            LinearGradient(
                crestX,
                crestY,
                crestX - roll.nx * inner,
                crestY - roll.ny * inner,
                intArrayOf(0x40000000, 0x10FFFFFF, 0x00000000),
                floatArrayOf(0f, 0.5f, 1f),
                Shader.TileMode.CLAMP,
            )
        // Only where the back actually lies: clip to the back mesh's outline.
        canvas.clipPath(outline(backMesh))
        canvas.drawPaint(shadePaint)
        canvas.restore()
        shadePaint.shader = null
    }

    private fun backOf(page: Bitmap): Bitmap =
        back ?: Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888).also {
            val c = Canvas(it)
            c.drawColor(paper)
            c.drawBitmap(page, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG).apply { alpha = 34 })
            back = it
        }

    /** Screen half-plane from the line through (x, y) in direction (nx, ny), clipped to the view. */
    private fun halfPlane(
        x: Float,
        y: Float,
        nx: Float,
        ny: Float,
        w: Float,
        h: Float,
    ): Path {
        val far = 4 * (w + h)
        val tx = -ny
        val ty = nx
        return Path().apply {
            moveTo(x + tx * far, y + ty * far)
            lineTo(x - tx * far, y - ty * far)
            lineTo(x - tx * far + nx * far, y - ty * far + ny * far)
            lineTo(x + tx * far + nx * far, y + ty * far + ny * far)
            close()
        }
    }

    /** Between the roll's axis and its crest: where the page curves. */
    private fun strip(
        roll: Roll,
        w: Float,
        h: Float,
    ): Path {
        val far = 4 * (w + h)
        val tx = -roll.ny
        val ty = roll.nx
        val cx = roll.ax + roll.nx * roll.r
        val cy = roll.ay + roll.ny * roll.r
        return Path().apply {
            moveTo(roll.ax + tx * far, roll.ay + ty * far)
            lineTo(roll.ax - tx * far, roll.ay - ty * far)
            lineTo(cx - tx * far, cy - ty * far)
            lineTo(cx + tx * far, cy + ty * far)
            close()
        }
    }

    /** The outer boundary of a warped mesh (its edge vertices in order). */
    private fun outline(mesh: FloatArray): Path {
        val path = Path()

        fun to(
            col: Int,
            row: Int,
        ) {
            val i = (row * (COLS + 1) + col) * 2
            if (path.isEmpty) path.moveTo(mesh[i], mesh[i + 1]) else path.lineTo(mesh[i], mesh[i + 1])
        }
        for (c in 0..COLS) to(c, 0)
        for (r in 1..ROWS) to(COLS, r)
        for (c in COLS - 1 downTo 0) to(c, ROWS)
        for (r in ROWS - 1 downTo 1) to(0, r)
        path.close()
        return path
    }

    /**
     * A page rolled around a cylinder of radius [r] lying on the page along the line through
     * ([ax], [ay]) perpendicular to ([nx], [ny]); n points toward the pulled corner.
     */
    internal class Roll(
        val ax: Float,
        val ay: Float,
        val nx: Float,
        val ny: Float,
        val r: Float,
    ) {
        enum class Side { FRONT, BACK }

        /** Where page point (x, y) appears seen from above, for the given side of the sheet. */
        fun project(
            x: Float,
            y: Float,
            side: Side,
            out: FloatArray,
            offset: Int = 0,
        ) {
            val quarter = (PI * r / 2).toFloat()
            val raw = (x - ax) * nx + (y - ay) * ny
            // The front shows up to the crest, the back from the crest on; the rest of each side
            // collapses onto the crest so it draws nothing.
            val d = if (side == Side.FRONT) min(raw, quarter) else max(raw, quarter)
            val shown =
                when {
                    d <= 0f -> d
                    d < PI * r -> r * sin(d / r)
                    else -> -(d - (PI * r).toFloat())
                }
            out[offset] = x + nx * (shown - raw)
            out[offset + 1] = y + ny * (shown - raw)
        }

        fun mesh(
            w: Float,
            h: Float,
            cols: Int,
            rows: Int,
            out: FloatArray,
            side: Side,
        ) {
            var i = 0
            for (row in 0..rows) {
                val y = h * row / rows
                for (col in 0..cols) {
                    project(w * col / cols, y, side, out, i)
                    i += 2
                }
            }
        }

        companion object {
            /**
             * The roll for a turn [p] of a [w]x[h] page. The corner (w, h) travels to
             * (w - 2pw, h - 0.16h·sin(πp)); the axis is placed so the rolled-over corner lands there.
             */
            fun at(
                p: Float,
                w: Float,
                h: Float,
                maxRadius: Float,
            ): Roll {
                val tx = w - p * 2f * w
                val ty = h - h * 0.16f * sin(PI * p).toFloat()
                val len = hypot(w - tx, h - ty).coerceAtLeast(0.01f)
                val nx = (w - tx) / len
                val ny = (h - ty) / len
                val r = min(maxRadius, len / PI.toFloat())
                // A corner at distance a past the axis lands at -(a - πr): solve for it to reach t.
                val a = (len + PI.toFloat() * r) / 2f
                return Roll(w - nx * a, h - ny * a, nx, ny, r)
            }
        }
    }

    private companion object {
        const val COLS = 24
        const val ROWS = 36
    }
}
