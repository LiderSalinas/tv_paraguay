"""Restore the exact logo and Android icons from their versioned payload."""

import base64
import hashlib
import json
from pathlib import Path


def prepare():
    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root / 'branding/tv_paraguay_assets.json').read_text(encoding='utf-8'))
    files = []
    for entry in manifest['files']:
        relative = Path(entry['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Invalid branding path')
        data = base64.b64decode(entry['base64'], validate=True)
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError(f'Invalid branding bytes: {relative}')
        files.append((root / relative, data))
    for target, data in files:
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != data:
            temporary = target.with_name(target.name + '.tmp')
            temporary.write_bytes(data)
            temporary.replace(target)
    print(f'Logo original e iconos preparados: {len(files)} archivos.')


if __name__ == '__main__':
    prepare()
