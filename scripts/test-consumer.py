"""Compile the README API example in a separate module before registry publication."""
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
readme = (ROOT / 'README.md').read_text(encoding='utf-8')
source = re.search(r'```moonbit\n(.*?)```', readme, re.S).group(1)
with tempfile.TemporaryDirectory(prefix='moonflame-consumer-') as directory:
    consumer = Path(directory)
    # This toolchain's modern manifest delegates local overrides to workspaces.
    # Its compatibility manifest supports a local dependency directly; use it
    # only inside this temporary prepublication consumer, never in the library.
    manifest = {'name': 'moonflame-tests/consumer', 'version': '0.0.0',
                'deps': {'gywcs101/moonflame': {'path': str(ROOT)}},
                'preferred-target': 'native'}
    (consumer / 'moon.mod.json').write_text(json.dumps(manifest), encoding='utf-8')
    (consumer / 'moon.pkg').write_text('import { "gywcs101/moonflame", }\n', encoding='utf-8')
    (consumer / 'consumer.mbt').write_text(source, encoding='utf-8')
    (consumer / 'consumer_test.mbt').write_text('''///|
test "README public API pipeline" {
  let svg = @consumer.folded_to_svg("root;a 60\\nroot;b 40")
  assert_true(svg.contains("<g id=\\"frames\\">"))
  let invalid = try { ignore(@consumer.folded_to_svg("r -1")); false } catch { _ => true }
  assert_true(invalid)
}
''', encoding='utf-8')
    subprocess.run(['moon', 'test', '--deny-warn'], cwd=consumer, check=True)
print('README compiled and executed in an independent consumer module.')
