"""Exercise real process status, output streams and file preservation."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=['native', 'js', 'wasm'], default='native')
    args = parser.parse_args()
    subprocess.run(['moon', 'build', '--target', args.target, '--deny-warn'], cwd=ROOT, check=True)
    # Moon has changed the default build profile directory across releases
    # (for example, debug versus release). Discover the actual artifact
    # instead of assuming one private _build path.
    build_root = ROOT / '_build' / args.target
    if args.target == 'native':
        names = {'main.exe', 'main'}
        command = [str(next(p for p in build_root.rglob('*') if p.is_file() and p.name in names and 'cmd' in p.parts and 'main' in p.parts))]
    elif args.target == 'js':
        path = next(p for p in build_root.rglob('main.js') if p.is_file() and 'cmd' in p.parts and 'main' in p.parts)
        command = ['node', str(path)]
    else:
        path = next(p for p in build_root.rglob('main.wasm') if p.is_file() and 'cmd' in p.parts and 'main' in p.parts)
        command = ['moonrun', str(path), '--']

    def run(*argv, status=0):
        result = subprocess.run([*command, *map(str, argv)], cwd=ROOT, encoding='utf-8', capture_output=True, timeout=90)
        assert result.returncode == status, (argv, result.returncode, result.stdout[:500], result.stderr[:500])
        return result

    assert '0.2.0' in run('--version').stdout
    assert 'Usage:' in run('--help').stdout
    run(status=2)
    run('nonexistent-file.folded', status=1)
    for option, value in [('width', 'NaN'), ('width', 'Infinity'), ('width', '20'), ('max-depth', '-1'), ('max-depth', 'abc'), ('unit', 'invalid')]:
        run('testdata/demo.folded', '--' + option, value, status=2)
    with tempfile.TemporaryDirectory(prefix='moonflame-cli-') as tmp:
        tmp = Path(tmp)
        bad, good, out = tmp / 'bad.folded', tmp / 'good.folded', tmp / 'out.svg'
        good.write_text('r;a 60\nr;b 40\n', encoding='utf-8')
        for invalid in ['r;a 100\nr;b -50', 'r;a 1\nbroken', 'r 0', 'r 1e308\nr 1e308']:
            bad.write_text(invalid, encoding='utf-8')
            out.write_text('previous output', encoding='utf-8')
            result = run(bad, '-o', out, status=1)
            assert not result.stdout
            assert result.stderr
            assert out.read_text() == 'previous output'
        bad.write_text('r;a 100\nr;b -50', encoding='utf-8')
        for subcommand in ['hotspots', 'callers', 'callees', 'filter']:
            argv = [subcommand, 'a', bad] if subcommand == 'filter' else [subcommand, bad]
            if subcommand in ['callers', 'callees']:
                argv.append('a')
            run(*argv, status=1)
        run('diff', good, bad, status=1)
        run('delta', bad, good, status=1)
        result = run(good)
        ET.fromstring(result.stdout)
        assert result.stdout.lstrip().startswith('<svg')
        run(good, '-o', tmp / 'missing-directory' / 'out.svg', status=1)
        run('filter', 'not-found', good, '-o', out)
        assert out.read_bytes() == b''
        assert run('filter', 'not-found', good).stdout == ''
        assert '没有直接被调用者' in run('callees', good, 'a').stdout
        before = tmp / 'before.folded'
        after = tmp / 'after.folded'
        before.write_text('r;gone 50\nr;keep 30\nr 20', encoding='utf-8')
        after.write_text('r;keep 30\nr 20', encoding='utf-8')
        xml = ET.fromstring(run('diff', before, after, '--unit', 'count').stdout)
        ns = {'s': 'http://www.w3.org/2000/svg'}
        own = xml.find('.//s:g[@data-name="(self)"]', ns)
        assert own.find('s:rect', ns).attrib['fill'] == 'rgb(255,255,255)'
        assert '-50.0%' in run('delta', before, after, '--unit', 'count').stdout
        for sub in ['callers', 'callees']:
            report = run(sub, 'testdata/demo.folded', 'walk_tree').stdout
            assert '369.1%' not in report
        # Full real fixtures, not just string excerpts used by unit tests.
        for profile in ['testdata/demo.folded', 'testdata/stress-recursive.folded']:
            xml = ET.fromstring(run(profile).stdout)
            for rect in xml.findall('.//s:rect', ns):
                assert float(rect.attrib['width']) >= 0
        ET.fromstring(run('testdata/stress-recursive.folded', '--max-depth', '0').stdout)
    print(f'CLI acceptance scenarios passed [{args.target}].')


if __name__ == '__main__':
    main()
