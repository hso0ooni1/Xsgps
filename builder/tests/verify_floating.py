"""Black-box emulator test of the APK produced by the production merge engine."""
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ARTIFACTS = pathlib.Path('floating-evidence')
ARTIFACTS.mkdir(exist_ok=True)

def adb(*args):
    return subprocess.check_output(['adb', *map(str, args)], text=True)

def dump(name):
    adb('shell', 'uiautomator', 'dump', '/sdcard/window.xml')
    text = adb('shell', 'cat', '/sdcard/window.xml')
    (ARTIFACTS / (name + '.xml')).write_text(text)
    return ET.fromstring(text)

def screenshot(name):
    (ARTIFACTS / (name + '.png')).write_bytes(subprocess.check_output(['adb', 'exec-out', 'screencap', '-p']))

def bubble(root):
    found = [n for n in root.iter('node') if n.get('content-desc') == 'فتح لوحة XsGPS']
    assert len(found) == 1, f'Expected exactly one floating button, found {len(found)}'
    return found[0]

def center(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
    assert x2 > x1 and y2 > y1
    return (x1 + x2) // 2, (y1 + y2) // 2

try:
    adb('install', '-r', 'fixtures/output.apk')
    adb('logcat', '-c')
    adb('shell', 'am', 'start', '-W', '-n', 'com.xsgps.android/.MainActivity')
    time.sleep(3)
    ui = dump('01-floating')
    button = bubble(ui)
    assert button.get('package') == 'com.xsgps.android'
    assert any(n.get('text') == 'XS GPS integration host' for n in ui.iter('node'))
    screenshot('01-floating')
    x, y = center(button)
    adb('shell', 'input', 'tap', x, y)
    time.sleep(2)
    panel = dump('02-panel')
    assert any('XsGPS  •  ANDROID' in n.get('text', '') for n in panel.iter('node')), 'Panel did not open'
    assert all(n.get('package') == 'com.xsgps.android' for n in panel.iter('node') if 'XsGPS' in n.get('text', ''))
    screenshot('02-panel')
    adb('shell', 'input', 'keyevent', 'BACK')
    time.sleep(1)
    x, y = center(bubble(dump('03-back')))
    adb('shell', 'input', 'swipe', x, y, max(80, x - 160), y + 120, 500)
    time.sleep(1)
    moved = center(bubble(dump('04-dragged')))
    assert abs(moved[0] - x) + abs(moved[1] - y) > 50, 'Button did not move'
    screenshot('04-dragged')
    adb('shell', 'input', 'keyevent', 'HOME')
    adb('shell', 'am', 'start', '-W', '-n', 'com.xsgps.android/.MainActivity')
    time.sleep(1)
    bubble(dump('05-resumed'))
    print('PASS: merged initializer, in-app floating button, panel, drag and activity resume')
finally:
    (ARTIFACTS / 'logcat.txt').write_text(adb('logcat', '-d', '-t', '1000'))
