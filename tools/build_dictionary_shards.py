#!/usr/bin/env python3
"""Turn the WordNet index built by build_dictionary.py (SQLite) into text shards for the Flutter app.

    python3 -I tools/build_dictionary_shards.py <wordnet.sqlite> <WORDNET-LICENSE.txt> mobile/assets/dictionary

Each shard holds "word<TAB>pos<TAB>definition" lines for the words whose hash falls in it, so a
lookup loads one small file. The hash must match lib/library/dictionary.dart.
"""
import pathlib, shutil, sqlite3, sys

SHARDS = 64

def shard(word):
    h = 0
    for unit in word.encode('utf-16-le')[::2]:  # low bytes; words are ASCII
        h = (h * 31 + unit) & 0x7FFFFFFF
    return h % SHARDS

def main(database, licence, out):
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(f'file:{database}?mode=ro', uri=True)
    buckets = [[] for _ in range(SHARDS)]
    for word, pos, definition in db.execute('SELECT word, pos, definition FROM definitions ORDER BY word, pos'):
        if '\t' in word or '\n' in definition:
            continue
        buckets[shard(word)].append(f'{word}\t{pos}\t{definition.strip()}')
    for i, lines in enumerate(buckets):
        (out / f'd{i:02d}.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    rows = sorted(set(db.execute('SELECT form, base FROM exceptions')))
    (out / 'exceptions.txt').write_text('\n'.join(f'{f}\t{b}' for f, b in rows) + '\n', encoding='utf-8')
    shutil.copyfile(licence, out / 'LICENSE.txt')
    print('words in shards:', sum(len(b) for b in buckets), 'largest shard lines:', max(len(b) for b in buckets))

if __name__ == '__main__':
    main(*sys.argv[1:4])
