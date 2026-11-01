#!/usr/bin/env python3
"""Real two-output splash smoke test. Run in an isolated environment.

Requires sway, quickshell, grim and Mesa software OpenGL. SWAY_BIN may point to
an extracted Sway binary. No GPU, physical display, or real desktop services
are needed. Hyprland readiness replies are controlled test fixtures.
"""
from pathlib import Path
import io
import json
import os
import shutil
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]


def wait_for(predicate, timeout=6):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        value=predicate()
        if value:return value
        time.sleep(.02)
    raise AssertionError('Timed out waiting for test session')


def screenshot(env, output):
    result=subprocess.run(['grim','-t','ppm','-o',output,'-'],env=env,capture_output=True,check=True,timeout=3)
    stream=io.BytesIO(result.stdout)
    assert stream.readline().strip()==b'P6'
    width,height=map(int,stream.readline().split())
    assert stream.readline().strip()==b'255'
    return width,height,stream.read(),result.stdout


def main():
    sway_bin=os.environ.get('SWAY_BIN') or shutil.which('sway')
    assert sway_bin,'Install sway or set SWAY_BIN for this optional test'
    swaymsg=str(Path(sway_bin).with_name('swaymsg'))
    artifacts=Path(os.environ.get('SPLASH_TEST_ARTIFACTS','/tmp/verumdot-splash-wayland'))
    artifacts.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='splash-wayland-') as tmp:
        base=Path(tmp); runtime=base/'run';runtime.mkdir(mode=0o700)
        env=dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HOME=str(base/'home'),
                 WLR_BACKENDS='headless',WLR_RENDERER='pixman',WLR_HEADLESS_OUTPUTS='2',
                 WLR_LIBINPUT_NO_DEVICES='1',LIBGL_ALWAYS_SOFTWARE='1',QSG_RHI_BACKEND='opengl',
                 QT_QPA_PLATFORM='wayland',QT_NO_XDG_DESKTOP_PORTAL='1',NO_COLOR='1')
        for key in ('WAYLAND_DISPLAY','DISPLAY','HYPRLAND_INSTANCE_SIGNATURE','SWAYSOCK',
                    'DBUS_SESSION_BUS_ADDRESS','QT_QUICK_BACKEND','QT_QPA_PLATFORMTHEME','QT_STYLE_OVERRIDE'):
            env.pop(key,None)
        config=base/'sway.conf';config.write_text('output * resolution 800x600\nseat seat0 fallback true\n')
        children=[]
        logs=[]
        def spawn(args, logfile, child_env=env):
            log=open(artifacts/logfile,'w');logs.append(log)
            process=subprocess.Popen(args,env=child_env,stdout=log,stderr=log)
            children.append(process);return process
        try:
            sway=spawn([sway_bin,'-c',str(config)],'sway.log')
            ipc=wait_for(lambda:next(runtime.glob('sway-ipc.*.sock'),None))
            env['SWAYSOCK']=str(ipc)
            outputs=subprocess.run([swaymsg,'-t','get_outputs','-r'],env=env,capture_output=True,text=True,timeout=10)
            names=[o['name'] for o in json.loads(outputs.stdout) if o['active']]
            assert len(names)==2,names
            env['WAYLAND_DISPLAY']=wait_for(lambda:next((p.name for p in runtime.glob('wayland-*') if p.is_socket()),None))
            backdrop=base/'backdrop';backdrop.mkdir()
            (backdrop/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
  Variants { model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      color: "#208050"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "splash-test-background"
    }
  }
}
''')
            spawn(['qs','-p',str(backdrop)],'backdrop.log')
            wait_for(lambda:'Configuration Loaded' in (artifacts/'backdrop.log').read_text())
            green=bytes([32,128,80])
            for name in names:wait_for(lambda:screenshot(env,name)[2][:3]==green)
            rice=base/'rice'
            for folder in ('lib','scripts','apps/quickshell/splash','assets'):
                shutil.copytree(ROOT/folder,rice/folder,symlinks=True)
            fakebin=base/'bin';fakebin.mkdir()
            hyprctl=fakebin/'hyprctl'
            hyprctl.write_text('#!/usr/bin/python3\nimport os\nprint(os.environ["TEST_LAYERS"])\n');hyprctl.chmod(0o755)
            original_video=(rice/'assets/splash.mp4').read_bytes()
            timings={}
            for scenario in ('deadline','ready','invalid-media'):
                child_env=dict(env,PATH=str(fakebin)+':'+env.get('PATH','/usr/bin'),
                               HYPRLAND_INSTANCE_SIGNATURE='fixture',XDG_CACHE_HOME=str(base/scenario),TEST_LAYERS='{}')
                if scenario=='ready':
                    child_env['TEST_LAYERS']=json.dumps({name:{'levels':{'0':[
                        {'namespace':ns,'w':800,'h':600,'alpha':1} for ns in ('hyprpaper','waybar')]}} for name in names})
                (rice/'assets/splash.mp4').write_bytes(b'not a video' if scenario=='invalid-media' else original_video)
                cache=base/scenario/'hypr/splash.log'
                started=time.monotonic()
                launcher=spawn(['bash',str(rice/'scripts/splash.sh')],scenario+'-launcher.log',child_env)
                observed_black=set(); video_seen=False; fade_seen=False; hidden_at=None
                while time.monotonic()-started<5 and launcher.poll() is None:
                    for name in names:
                        w,h,pixels,ppm=screenshot(child_env,name)
                        corner=pixels[:3]
                        if max(corner)<8:
                            observed_black.add(name)
                            # A nonblack central region on black is the decoded video.
                            row=pixels[(h//2*w+w//3)*3:(h//2*w+2*w//3)*3]
                            if any(value>20 for value in row):
                                video_seen=True
                                (artifacts/(scenario+'-'+name+'.ppm')).write_bytes(ppm)
                        if 8<corner[1]<120:fade_seen=True
                    if cache.exists() and 'splash: hidden' in cache.read_text() and hidden_at is None:
                        hidden_at=time.monotonic()-started
                    time.sleep(.015)
                launcher.wait(timeout=6)
                text=cache.read_text();(artifacts/(scenario+'.log')).write_text(text)
                assert 'Configuration Loaded' in text,text
                assert 'splash: hidden' in text,text
                assert 'ERROR: Failed to load' not in text,text
                if scenario=='invalid-media':
                    assert 'cannot play video' in text,text
                else:
                    assert observed_black==set(names),(scenario,observed_black)
                    assert video_seen,(scenario,'no decoded video observed')
                    assert ('desktop ready' if scenario=='ready' else 'dismiss deadline') in text,text
                for name in names:
                    assert screenshot(child_env,name)[2][:3]==green,(scenario,'overlay still mapped',name)
                assert launcher.returncode==0
                timings[scenario]={'hidden_seconds':hidden_at,'total_seconds':time.monotonic()-started,'fade_observed':fade_seen}
                print('PASS',scenario,timings[scenario],flush=True)
            assert timings['ready']['hidden_seconds']<timings['deadline']['hidden_seconds'],timings
            (artifacts/'timings.json').write_text(json.dumps(timings,indent=2)+'\n')
        finally:
            for process in reversed(children):
                if process.poll() is None:
                    process.terminate()
                    try:process.wait(timeout=2)
                    except subprocess.TimeoutExpired:process.kill();process.wait()
            for log in logs:log.close()
    print('Real Wayland splash checks passed on both virtual outputs')


if __name__=='__main__':main()
