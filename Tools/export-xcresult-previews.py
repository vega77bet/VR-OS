"""Export native XCTest PNG previews on Xcode 15 and newer.

xcodebuild can run on a cloned simulator. Do not assume the requested device
owns the data container. Prefer the generated files, then result attachments.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

result = Path(sys.argv[1])
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
root = Path.home() / 'Library/Developer/CoreSimulator/Devices'
for source in sorted(root.glob('*/data/Containers/Data/Application/*/Documents/VR-OS-Previews/VR-OS-V48-*.png')):
    shutil.copyfile(source, output / source.name)

if not list(output.glob('*.png')):
    def get(identifier=None):
        command = ['xcrun', 'xcresulttool', 'get', '--path', str(result), '--format', 'json']
        if identifier:
            command.extend(['--id', identifier])
        response = subprocess.run(command, capture_output=True, text=True)
        if response.returncode:
            # Xcode 16 exposes the same schema through the legacy interface.
            response = subprocess.run(command + ['--legacy'], check=True, capture_output=True, text=True)
        return json.loads(response.stdout)

    def value(node):
        return node.get('_value', '') if isinstance(node, dict) else ''

    queue = [get()]
    seen = set()
    exported = set()
    while queue:
        document = queue.pop(0)
        references = []
        def walk(node):
            if isinstance(node, list):
                for item in node:
                    walk(item)
            elif isinstance(node, dict):
                for key in ('testsRef', 'summaryRef'):
                    identifier = value(node.get(key, {}).get('id', {}))
                    if identifier and identifier not in seen:
                        seen.add(identifier)
                        references.append(identifier)
                name = value(node.get('name'))
                payload = value(node.get('payloadRef', {}).get('id', {}))
                if name.startswith('VR-OS-V48-') and payload and payload not in exported:
                    exported.add(payload)
                    filename = re.sub(r'[^A-Za-z0-9._-]', '_', name)
                    if not filename.lower().endswith('.png'):
                        filename += '.png'
                    command = ['xcrun', 'xcresulttool', 'export', '--type', 'file', '--path', str(result),
                               '--id', payload, '--output-path', str(output / filename)]
                    response = subprocess.run(command, capture_output=True, text=True)
                    if response.returncode:
                        subprocess.run(command[:3] + ['object'] + command[3:] + ['--legacy'], check=True)
                for item in node.values():
                    walk(item)
        walk(document)
        queue.extend(get(identifier) for identifier in references)

files = sorted(output.glob('*.png'))
if len(files) < 4:
    raise SystemExit(f'Expected at least four native previews; found {len(files)}')
for path in files:
    print(path)
