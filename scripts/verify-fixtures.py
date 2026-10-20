"""Offline fixture/license checks; optional verification with the pinned converter."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moon-pprof', type=Path)
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'testdata/SOURCES.json').read_text(encoding='utf-8'))
    for name, expected in manifest['files'].items():
        actual = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        assert actual == expected, f'Fixture changed without provenance update: {name}'
    actual_files = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'testdata').glob('*') if p.name != 'SOURCES.json'}
    assert actual_files == set(manifest['files']), 'Unclassified fixture in testdata/'
    license_data = (ROOT / 'LICENSES/Apache-2.0.txt').read_bytes()
    assert hashlib.sha256(license_data).hexdigest() == manifest['upstream']['license_sha256']
    baseline = []
    for line in (ROOT / 'testdata/demo.folded').read_text().splitlines():
        stack, value = line.rsplit(' ', 1)
        factor = 3 if 'bubble__sort' in stack else 0.8 if 'build__strings' in stack else 1
        baseline.append(f'{stack} {int(int(value) * factor)}')
    assert baseline == (ROOT / 'testdata/demo-baseline.folded').read_text().splitlines()
    if args.moon_pprof:
        converter = args.moon_pprof.resolve()
        with tempfile.TemporaryDirectory(prefix='moonflame-convert-') as tmp:
            for source, target in [('official-sample.pb.gz', 'stress-recursive.folded'), ('demo.pb.gz', 'demo.folded')]:
                out = Path(tmp) / target
                subprocess.run([str(converter), 'pprof2folded', str(ROOT / 'testdata' / source), str(out)], check=True)
                assert out.read_bytes() == (ROOT / 'testdata' / target).read_bytes(), target
    print('Fixture provenance, license copy and synthetic baseline verified.')


if __name__ == '__main__':
    main()
