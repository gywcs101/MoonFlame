"""Check that the local release archive contains required redistribution materials."""
from pathlib import Path
import json
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
archive = ROOT / '_build/publish/gywcs101-moonflame-0.2.0.zip'
with zipfile.ZipFile(archive) as package:
    names = package.namelist()
    def member(suffix):
        matches = [name for name in names if name.replace('\\', '/').endswith(suffix)]
        assert len(matches) == 1, f'Missing or ambiguous archive member: {suffix}'
        return matches[0]
    manifest = json.loads(package.read(member('testdata/SOURCES.json')))
    assert hashlib.sha256(package.read(member('LICENSES/Apache-2.0.txt'))).hexdigest() == manifest['upstream']['license_sha256']
    for name, expected in manifest['files'].items():
        assert hashlib.sha256(package.read(member(name))).hexdigest() == expected, name
    for name in ['LICENSE', 'README.md', 'THIRD_PARTY_NOTICES.md', 'MIGRATION.md', 'REMEDIATION.md']:
        member(name)
    assert not any('/node_modules/' in name.replace('\\', '/') for name in names)
    assert not any('_toolchain/' in name.replace('\\', '/') for name in names)
print(f'Release archive and license/fixture contents verified: {archive.name}')
