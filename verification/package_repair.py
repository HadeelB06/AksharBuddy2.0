from pathlib import Path
import json,hashlib,zipfile

root=Path(__file__).resolve().parents[1]
destination=root.parent/'AksharBuddy-LAN-repair.zip'
excluded={'.git','.dart_tool','.gradle','.venv','build','__pycache__','.idea','node_modules','local-logs','failures'}
files=[]
for path in root.rglob('*'):
    relative=path.relative_to(root)
    if not path.is_file() or any(part in excluded for part in relative.parts):continue
    if path.name in {'.env','firebase_key.json','package-manifest.json','package-summary.json'}:continue
    if path.name.startswith('implement_'):continue
    if path.name=='12-progress.png':continue
    files.append(path)
manifest=[]
for path in files:
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    manifest.append(dict(path=path.relative_to(root).as_posix(),bytes=path.stat().st_size,sha256=digest.hexdigest()))
manifest_path=root/'verification/package-manifest.json'
manifest_path.write_text(json.dumps(manifest,indent=2),encoding='utf-8')
files.append(manifest_path)
with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=1,allowZip64=True) as archive:
    for path in files:archive.write(path,root.name+'/'+path.relative_to(root).as_posix())
print('Archive written; checking every entry CRC.',flush=True)
with zipfile.ZipFile(destination) as archive:
    bad=archive.testzip()
    if bad:raise RuntimeError('Archive CRC failed: '+bad)
summary=dict(archive=str(destination),bytes=destination.stat().st_size,file_count=len(files),crc_verified=True)
(root/'verification/package-summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary),flush=True)
