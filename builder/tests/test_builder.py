import io
import json
import os
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
import pytest
from fastapi.testclient import TestClient
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server as s


def pack(path, entries):
    with zipfile.ZipFile(path, 'w') as z:
        for name, value in entries.items():
            z.writestr(name, value)
    return path


@pytest.fixture(autouse=True)
def isolate(tmp_path, monkeypatch):
    monkeypatch.setattr(s, 'WORK', tmp_path)
    monkeypatch.setattr(s, 'KEY', 'private-test-key')
    s.jobs.clear()


@pytest.mark.parametrize('name', ['../escape', '/absolute', 'C:/drive', './base.apk', 'a/../b'])
def test_archive_paths(tmp_path, name):
    p = pack(tmp_path/'bad.xapk', {name: b'x'})
    with pytest.raises(ValueError):
        s.safe_unpack(p, tmp_path/'out')


def test_duplicate_entries(tmp_path):
    p = tmp_path/'bad.xapk'
    with zipfile.ZipFile(p, 'w') as z:
        z.writestr('base.apk', b'a')
        z.writestr('base.apk', b'b')
    with pytest.raises(ValueError):
        s.safe_unpack(p, tmp_path/'out')


def test_manifest_release_and_existing_app(tmp_path):
    original = '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.example.app"><application android:name=".HostApplication" android:debuggable="false"/><uses-sdk android:minSdkVersion="21"/></manifest>'
    (tmp_path/'AndroidManifest.xml').write_text(original)
    (tmp_path/'apktool.yml').write_text("sdkInfo:\n  minSdkVersion: '21'\n  targetSdkVersion: '34'\n")
    s.configure_manifest(tmp_path)
    xml=ET.parse(tmp_path/'AndroidManifest.xml').getroot()
    a='{'+s.ANDROID+'}'
    app=xml.find('application')
    assert app.get(a+'name') == '.HostApplication'
    assert app.get(a+'debuggable') == 'false'
    assert app.find('provider').get(a+'exported') == 'false'
    assert app.find('service').get(a+'foregroundServiceType') == 'location'
    assert xml.find('uses-sdk').get(a+'minSdkVersion') == '26'
    assert 'minSdkVersion: 26' in (tmp_path/'apktool.yml').read_text()
    with pytest.raises(ValueError, match='مسبقًا'):
        s.configure_manifest(tmp_path)


def test_xapk_preserves_splits_obb_and_updates_manifest(tmp_path, monkeypatch):
    manifest={'split_apks':[{'file':'base.apk','file_size':3,'sha256':'old'}, {'file':'splits/config.apk','md5':'old'}]}
    source=pack(tmp_path/'in.xapk', {'base.apk':b'base', 'splits/config.apk':b'split', 'Android/obb/org.example/main.obb':b'OBB-content', 'manifest.json':json.dumps(manifest)})
    monkeypatch.setattr(s, 'inspect_archive', lambda *args: None)
    monkeypatch.setattr(s, 'apk_info', lambda path: ('org.example', 'config' if ('config' in path.name or path.name=='1.apk') else None, '1'))
    calls=[]
    def replace(src,dst,work):
        calls.append(src.name)
        dst.write_bytes(src.read_bytes()+b'-signed')
    monkeypatch.setattr(s, 'sign', replace)
    monkeypatch.setattr(s, 'integrate', replace)
    output=tmp_path/'out.xapk'
    s.process_xapk(source,output,tmp_path)
    with zipfile.ZipFile(output) as z:
        assert z.read('base.apk')==b'base-signed'
        assert z.read('splits/config.apk')==b'split-signed'
        assert z.read('Android/obb/org.example/main.obb')==b'OBB-content'
        m=json.loads(z.read('manifest.json'))
        assert m['split_apks'][0]['file_size']==len(b'base-signed')
        assert m['split_apks'][0]['sha256']!='old'
        assert len(m['split_apks'][1]['md5'])==32
    assert sorted(calls)==['base.apk','config.apk']


def test_mixed_versions_rejected(tmp_path, monkeypatch):
    p=pack(tmp_path/'in.xapk',{'base.apk':b'a','config.apk':b'b'})
    monkeypatch.setattr(s,'apk_info',lambda path: ('org.example',None,'1') if path.name=='base.apk' else ('org.other','config','2'))
    with pytest.raises(ValueError,match='الإصدار'):
        s.process_xapk(p,tmp_path/'out.xapk',tmp_path)


def test_signed_download_uses_scoped_ticket(tmp_path):
    out=tmp_path/'out.apk';out.write_bytes(b'APK')
    s.jobs['job']={'state':'done','created':s.time.time(),'directory':tmp_path,'output_name':'out.apk','download_ticket':'scoped-ticket'}
    with TestClient(s.app) as client:
        assert client.get('/api/download/job').status_code==401
        assert client.get('/api/download/job?ticket=wrong').status_code==401
        response=client.get('/api/download/job?ticket=scoped-ticket')
        assert response.status_code==200 and response.content==b'APK'
        assert client.get('/api/status/job').status_code==401


def test_health_alias_and_auth():
    with TestClient(s.app) as c:
        assert c.get('/health').json()==c.get('/api/health').json()
        assert c.get('/').status_code==200
        assert c.post('/api/build',files={'file':('test.apk',b'X'*2000)}).status_code==401
        assert c.post('/api/build',headers={'X-Builder-Key':'private-test-key'},files={'file':('test.zip',b'X'*2000)}).status_code==400


def test_failed_build_removes_input_and_partial_files(tmp_path,monkeypatch):
    work=tmp_path/'job';work.mkdir()
    uploaded=pack(work/'upload.apk',{'AndroidManifest.xml':b'bad'})
    def fail(*args):
        (work/'partial.apk').write_bytes(b'x')
        raise ValueError('controlled failure')
    monkeypatch.setattr(s,'integrate',fail)
    s.jobs['job']={'state':'queued','created':s.time.time(),'directory':work}
    s.process('job',uploaded,'apk')
    assert s.jobs['job']['state']=='failed'
    assert list(work.iterdir())==[]
