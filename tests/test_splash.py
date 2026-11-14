"""Splash/startup contracts with private directories and fake system adapters."""
from pathlib import Path
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SplashTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.rice = self.root/'rice'
        for directory in ('lib', 'scripts'):
            shutil.copytree(ROOT/directory, self.rice/directory)
        (self.rice/'apps/quickshell/splash').mkdir(parents=True)
        shutil.copy2(ROOT/'apps/quickshell/splash/shell.qml', self.rice/'apps/quickshell/splash/shell.qml')
        (self.rice/'assets').mkdir()
        (self.rice/'assets/splash.mp4').write_bytes(b'fixture')
        self.bin = self.root/'bin'; self.bin.mkdir()
        # No real qs/hyprctl/waybar can be found through this PATH.
        for tool in ('bash', 'basename', 'dirname', 'readlink', 'mkdir', 'flock', 'timeout', 'env', 'jq', 'sleep', 'date', 'id', 'ls', 'head'):
            (self.bin/tool).symlink_to(shutil.which(tool))
        self.env = dict(os.environ, PATH=str(self.bin), XDG_CACHE_HOME=str(self.root/'cache'),
                        XDG_STATE_HOME=str(self.root/'state'), XDG_DATA_HOME=str(self.root/'data'),
                        XDG_RUNTIME_DIR=str(self.root/'run'), HYPRLAND_INSTANCE_SIGNATURE='test',
                        FAKE_RECORD=str(self.root/'calls'), HYPR_LOG_LEVEL='silent')
        self.mock('hyprctl', 'import os; print(os.environ.get("FAKE_LAYERS", "{}"))')
        self.mock('qs', 'import os; open(os.environ["FAKE_RECORD"],"a").write("launch\\n")')

    def mock(self, name, body):
        path=self.bin/name
        path.write_text('#!/usr/bin/python3\n'+body+'\n');path.chmod(0o755)

    def run_script(self, script, timeout=7):
        return subprocess.run(['/usr/bin/bash',str(self.rice/'scripts'/script)],env=self.env,
                              capture_output=True,text=True,timeout=timeout)

    def layers(self, *outputs):
        self.env['FAKE_LAYERS']=json.dumps({f'monitor-{i}': {'levels': {'0': layers}} for i,layers in enumerate(outputs)})

    def desktop(self):
        return [{'namespace':name,'w':800,'h':600,'alpha':1} for name in ('hyprpaper','waybar')]

    def test_ready_requires_both_mapped_layers_on_every_output(self):
        self.layers(self.desktop(), self.desktop())
        self.assertEqual(self.run_script('splash-ready.sh').returncode,0)
        self.layers(self.desktop(), self.desktop()[:1])
        self.assertNotEqual(self.run_script('splash-ready.sh').returncode,0)
        self.layers()
        self.assertNotEqual(self.run_script('splash-ready.sh').returncode,0)

    def test_invisible_or_empty_surface_is_not_ready(self):
        for field,value in [('alpha',0),('w',0),('h',0)]:
            layers=self.desktop();layers[1][field]=value;self.layers(layers)
            self.assertNotEqual(self.run_script('splash-ready.sh').returncode,0)

    def test_malformed_or_hung_ipc_is_bounded(self):
        self.env['FAKE_LAYERS']='invalid json'
        self.assertNotEqual(self.run_script('splash-ready.sh').returncode,0)
        self.mock('hyprctl','import time; time.sleep(10)')
        start=time.monotonic()
        self.assertNotEqual(self.run_script('splash-ready.sh').returncode,0)
        self.assertLess(time.monotonic()-start,1)

    def test_missing_session_is_not_ready(self):
        self.layers(self.desktop());self.env.pop('HYPRLAND_INSTANCE_SIGNATURE')
        self.assertNotEqual(self.run_script('splash-ready.sh').returncode,0)

    def test_missing_runtime_or_video_skips_without_blocking_login(self):
        (self.bin/'qs').unlink()
        self.assertEqual(self.run_script('splash.sh').returncode,0)
        self.mock('qs','raise RuntimeError("must not launch")')
        (self.rice/'assets/splash.mp4').unlink()
        self.assertEqual(self.run_script('splash.sh').returncode,0)
        self.assertFalse((self.root/'calls').exists())

    def test_launch_is_portal_independent_and_logs_failure(self):
        self.mock('qs','import os,sys; assert os.environ["QT_NO_XDG_DESKTOP_PORTAL"] == "1"; assert os.environ["QT_FFMPEG_DECODING_HW_DEVICE_TYPES"] == ","; print("bad media"); sys.exit(3)')
        self.assertEqual(self.run_script('splash.sh').returncode,0)
        log=(self.root/'cache/hypr/splash.log').read_text()
        self.assertIn('bad media',log);self.assertIn('status 3',log)

    def test_watchdog_kills_unresponsive_decoder_and_releases_lock(self):
        self.mock('qs','import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); open(os.environ["FAKE_RECORD"],"a").write("launch\\n"); time.sleep(30)')
        start=time.monotonic()
        self.assertEqual(self.run_script('splash.sh').returncode,0)
        self.assertLess(time.monotonic()-start,6)
        self.assertIn('deadline reached',(self.root/'cache/hypr/splash.log').read_text())
        self.mock('qs','import os; open(os.environ["FAKE_RECORD"],"a").write("launch\\n")')
        self.assertEqual(self.run_script('splash.sh').returncode,0)
        self.assertEqual((self.root/'calls').read_text().splitlines(),['launch','launch'])

    def test_duplicate_launch_is_ignored(self):
        self.mock('qs','import os,time; open(os.environ["FAKE_RECORD"],"a").write("launch\\n"); time.sleep(30)')
        first=subprocess.Popen(['/usr/bin/bash',str(self.rice/'scripts/splash.sh')],env=self.env)
        try:
            for _ in range(100):
                if (self.root/'calls').exists():break
                time.sleep(.01)
            self.assertTrue((self.root/'calls').exists())
            self.assertEqual(self.run_script('splash.sh').returncode,0)
            self.assertEqual((self.root/'calls').read_text(),'launch\n')
            first.wait(timeout=6)
        finally:
            if first.poll() is None:first.kill();first.wait()

    def compositor_socket(self):
        path=self.root/'run/hypr/test/.socket2.sock';path.parent.mkdir(parents=True,exist_ok=True)
        server=socket.socket(socket.AF_UNIX);server.bind(str(path));self.addCleanup(server.close)
        return server

    def test_waybar_stops_after_bounded_start_failures(self):
        self.compositor_socket()
        self.mock('waybar','import os,sys; open(os.environ["FAKE_RECORD"],"a").write("failed\\n"); sys.exit(1)')
        # Keep this retry-policy test fast; no real clock delay is needed.
        (self.bin/'sleep').unlink();self.mock('sleep','pass')
        self.assertEqual(self.run_script('waybar-start.sh').returncode,1)
        self.assertEqual(len((self.root/'calls').read_text().splitlines()),5)

    def test_waybar_observes_late_socket_and_stops_its_child(self):
        self.mock('waybar','import os,time; open(os.environ["FAKE_RECORD"],"w").write(str(os.getpid())); time.sleep(30)')
        supervisor=subprocess.Popen(['/usr/bin/bash',str(self.rice/'scripts/waybar-start.sh')],env=self.env)
        try:
            time.sleep(.15)
            self.assertFalse((self.root/'calls').exists())
            self.compositor_socket()
            for _ in range(100):
                if (self.root/'calls').exists():break
                time.sleep(.02)
            self.assertTrue((self.root/'calls').exists())
            child=int((self.root/'calls').read_text())
            supervisor.terminate();supervisor.wait(timeout=2)
            for _ in range(50):
                stat=Path(f'/proc/{child}/stat')
                try: state=stat.read_text().split()[2]
                except (FileNotFoundError,ProcessLookupError): break
                if state=='Z':break
                time.sleep(.02)
            else:self.fail('Waybar child outlived terminated supervisor')
        finally:
            if supervisor.poll() is None:supervisor.kill();supervisor.wait()


if __name__=='__main__':unittest.main()
