// Quill patch: mark blocks the book aligns to the start (left) so quillMoonMode.css can justify
// them while "book design" is off, as Moon Reader does, without touching centred/right lines.
// The book's own alignment is read once, before any Quill rule depends on it.
(function () {
  function mark() {
    var body = document.body;
    if (!body) return;
    var blocks = body.querySelectorAll('p, div, li, blockquote, dd, dt');
    for (var i = 0; i < blocks.length; i++) {
      var el = blocks[i];
      var align = getComputedStyle(el).textAlign;
      if (align === 'left' || align === 'start' || align === '-webkit-auto' || align === 'justify') {
        el.classList.add('quill-justify');
      }
    }
    document.documentElement.classList.add('quill-aligned');
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mark);
  } else {
    mark();
  }
})();
