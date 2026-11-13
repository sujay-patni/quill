package dk.nota.flutterreadium

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.select.NodeTraversor
import org.jsoup.select.NodeVisitor
import org.readium.r2.shared.publication.Locator

/**
 * Element ids of an XHTML document in document order, with each element's subtree.
 *
 * ToC entries can target a container (e.g. a newspaper `<section>` or `<aside>`) that has no
 * Sync Narration cue and that the ContentService never yields; only its descendants do. This
 * maps such a target to the first descendant that does. See ADR 0001.
 */
class XhtmlIdTree(
    xhtml: ByteArray,
) {
    val ids = mutableListOf<String>()

    /** The descendants of `ids[i]` are `ids.subList(i + 1, subtreeEnd[i])`. */
    private val subtreeEnd = mutableListOf<Int>()

    init {
        // Quill patch: jsoup instead of XmlPullParser. Real EPUB XHTML uses undeclared HTML
        // entities (&nbsp;, &mdash;) and unclosed tags; a strict XML parser stopped at the first
        // one, losing every later id (wrong chapter titles). One linear pass either way.
        val open = ArrayDeque<Int?>()
        val document = Jsoup.parse(String(xhtml, Charsets.UTF_8))
        NodeTraversor.traverse(
            object : NodeVisitor {
                override fun head(
                    node: Node,
                    depth: Int,
                ) {
                    if (node !is Element) return
                    val id = node.id()
                    if (id.isEmpty()) {
                        open.addLast(null)
                    } else {
                        open.addLast(ids.size)
                        ids.add(id)
                        subtreeEnd.add(ids.size)
                    }
                }

                override fun tail(
                    node: Node,
                    depth: Int,
                ) {
                    if (node !is Element) return
                    open.removeLastOrNull()?.let { subtreeEnd[it] = ids.size }
                }
            },
            document,
        )
    }

    /** The first id inside element [id], excluding [id] itself, that is in [candidates]. */
    fun firstDescendant(
        id: String,
        candidates: Set<String>,
    ): String? {
        val start = ids.indexOf(id).takeIf { it >= 0 } ?: return null
        return ids.subList(start + 1, subtreeEnd[start]).firstOrNull { it in candidates }
    }

    /** A later enclosing ToC element ends continuation from an earlier heading. */
    fun boundaryOwner(
        textId: String,
        ownerId: String?,
        tocIds: List<String>,
    ): Int? {
        val current = ids.indexOf(textId).takeIf { it >= 0 } ?: return null
        val owner = ownerId?.let { ids.indexOf(it) } ?: -1
        if (ownerId != null && owner == -1) return null
        var result: Int? = null
        var latest = owner
        tocIds.forEachIndexed { index, id ->
            val start = ids.indexOf(id)
            if (start > owner && start <= current && current < subtreeEnd[start] && start >= latest) {
                latest = start
                result = index
            }
        }
        return result
    }

    /** A known cue-less element seeks forward; a missing id keeps the caller's fallback policy. */
    fun anchor(
        locator: Locator,
        textId: String,
        cueIds: Set<String>,
    ): Locator? {
        if (locator.locations.fragments.any { it.startsWith("t=") }) return locator
        val start = ids.indexOf(textId).takeIf { it >= 0 } ?: return locator
        val first = ids.subList(start, ids.size).firstOrNull { it in cueIds } ?: return null
        return locator.copy(
            locations =
                locator.locations.copy(
                    fragments = listOf(first),
                    otherLocations = locator.locations.otherLocations + ("cssSelector" to "#$first"),
                ),
        )
    }
}
