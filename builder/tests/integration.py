"""Real APKTool/D8/apksigner smoke test, run inside the built image by CI."""
import json
import sys
import tempfile
import zipfile
from pathlib import Path
sys.path.insert(0, '/app')
import server as s

fixtures=Path('/fixtures')
base=fixtures/'input.apk'
split=fixtures/'config.apk'
with tempfile.TemporaryDirectory() as d:
    work=Path(d)
    output=work/'integrated.apk'
    s.integrate(base,output,work)
    with zipfile.ZipFile(base) as before, zipfile.ZipFile(output) as after:
        for name in before.namelist():
            if name.endswith('.dex'):
                assert before.read(name)==after.read(name), 'Host DEX changed'
        assert 'assets/xsgps_map.html' in after.namelist()
        assert any(b'Lcom/xsgps/embed/XsGpsInitProvider;' in after.read(n) for n in after.namelist() if n.endswith('.dex'))
    assert 'XsGpsInitProvider' in s.run(s.TOOLS/'aapt','dump','xmltree',output,'AndroidManifest.xml')
    with tempfile.TemporaryDirectory() as bundle_dir:
        bundle=Path(bundle_dir)
        source=bundle/'input.xapk'
        manifest={'split_apks':[{'file':'base.apk','file_size':base.stat().st_size}, {'file':'config.apk','file_size':split.stat().st_size}]}
        with zipfile.ZipFile(source,'w') as z:
            z.write(base,'base.apk');z.write(split,'config.apk')
            z.writestr('manifest.json',json.dumps(manifest))
            z.writestr('Android/obb/com.xsgps.android/main.obb',b'preserve-this-data')
        result=bundle/'output.xapk'
        s.process_xapk(source,result,bundle)
        certs=[]
        with zipfile.ZipFile(result) as z:
            assert z.read('Android/obb/com.xsgps.android/main.obb')==b'preserve-this-data'
            m=json.loads(z.read('manifest.json'))
            for entry in m['split_apks']:
                assert entry['file_size']==len(z.read(entry['file']))
                p=bundle/('check-'+entry['file']);p.write_bytes(z.read(entry['file']))
                verified=s.run(s.TOOLS/'apksigner','verify','--print-certs',p)
                certs.append(next(line for line in verified.splitlines() if 'certificate SHA-256 digest:' in line))
        assert certs[0]==certs[1], 'Split certificates differ'
print('PASS: real APK integration, unchanged host DEX, initializer, split XAPK, OBB preservation, signatures and certificate match')
