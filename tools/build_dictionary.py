#!/usr/bin/env python3
"""Build the bundled English index from the official WordNet 3.0 archive (no network)."""
import argparse, pathlib, sqlite3, tarfile

def build(archive, output, license_output):
    output=pathlib.Path(output)
    temporary=output.with_suffix('.tmp')
    temporary.unlink(missing_ok=True)
    with tarfile.open(archive) as src, sqlite3.connect(temporary) as db:
        db.executescript('CREATE TABLE definitions(word TEXT NOT NULL, pos TEXT NOT NULL, definition TEXT NOT NULL); CREATE TABLE exceptions(form TEXT NOT NULL, base TEXT NOT NULL);')
        for part in ('noun','verb','adj','adv'):
            rows=[]
            for line in src.extractfile(f'WordNet-3.0/dict/data.{part}'):
                text=line.decode('utf-8').rstrip()
                if not text or not text[0].isdigit(): continue
                data,gloss=text.split('|',1); fields=data.split(); count=int(fields[3],16)
                for i in range(count):rows.append((fields[4+i*2].lower(),part,gloss.strip()))
            db.executemany('INSERT INTO definitions VALUES (?,?,?)',rows)
            rows=[]
            for line in src.extractfile(f'WordNet-3.0/dict/{part}.exc'):
                fields=line.decode().split()
                rows.extend((fields[0],base) for base in fields[1:])
            db.executemany('INSERT INTO exceptions VALUES (?,?)',rows)
        db.executescript('CREATE INDEX definitions_word ON definitions(word); CREATE INDEX exceptions_form ON exceptions(form); PRAGMA user_version=1;')
        db.commit()
        assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        print('Definitions:',db.execute('SELECT count(*) FROM definitions').fetchone()[0])
        pathlib.Path(license_output).write_bytes(src.extractfile('WordNet-3.0/LICENSE').read())
    temporary.replace(output)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('archive');p.add_argument('output');p.add_argument('license_output');a=p.parse_args();build(a.archive,a.output,a.license_output)
