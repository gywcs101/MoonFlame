"""Compile the README API example in a separate module before registry publication."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
readme = (ROOT / 'README.md').read_text(encoding='utf-8')
source = re.search(r'```moonbit\n(.*?)```', readme, re.S).group(1)
with tempfile.TemporaryDirectory(prefix='moonflame-consumer-') as directory:
    workspace = Path(directory)
    consumer = workspace / 'consumer'
    local_module = workspace / 'moonflame'
    consumer.mkdir()
    # Modern Moon resolves local modules through moon.work. Copy the module
    # into the temporary workspace so this test remains independent of the
    # checkout path and works with current and future MoonBit toolchains.
    shutil.copytree(
        ROOT,
        local_module,
        ignore=shutil.ignore_patterns('.git', '_build', '_toolchain', 'node_modules'),
    )
    (workspace / 'moon.work').write_text(
        'members = ["consumer", "moonflame"]\n', encoding='utf-8'
    )
    (consumer / 'moon.mod').write_text(
        'name = "moonflame-tests/consumer"\n'
        'version = "0.0.0"\n'
        'preferred_target = "native"\n'
        'import { "gywcs101/moonflame@0.2.0" }\n',
        encoding='utf-8',
    )
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
