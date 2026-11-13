package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class XhtmlIdTreeTest {
    private fun tree(body: String) =
        XhtmlIdTree(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title></head>
            <body>$body</body></html>
            """.trimIndent().toByteArray(),
        )

    @Test
    fun idsAfterHtmlEntitiesAreStillFound() {
        // Real EPUB XHTML often uses HTML entities that are not declared in XML.
        val t =
            tree(
                """<h1 id="c1">One</h1><p>A&nbsp;b &mdash; c&rsquo;s &hellip;</p>
                <section id="s2"><h2 id="c2">Two</h2><p id="p2">Text &amp; more</p></section>""",
            )
        assertEquals(listOf("c1", "s2", "c2", "p2"), t.ids)
        assertEquals("c2", t.firstDescendant("s2", setOf("c2", "p2")))
    }

    @Test
    fun idsAfterMalformedMarkupAreStillFound() {
        val t = tree("""<p id="a">x<br>y</p><p id="b">z</p><img src="a.png"><p id="c">w</p>""")
        assertEquals(listOf("a", "b", "c"), t.ids)
    }
}
