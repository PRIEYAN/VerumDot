"""Contract tests use injected collaborators; no network or package actions run."""
from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib/python'))
from hyprrice.errors import RiceError
from hyprrice.process import Command, CommandError
from hyprrice.privacy import Connection, ConnectionInspector, MacRandomiser, PrivacyService, ProfileStore
from hyprrice.tor import TorBrowser, TorIpChecker


class FakeCommand:
    def __init__(self, *replies):
        self.replies = list(replies)
        self.calls = []

    def run(self, *args, timeout=None):
        self.calls.append((args, timeout))
        if not self.replies:
            return ''
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


CONNECTION = Connection('wlan0', 'uuid-1', '802-11-wireless.cloned-mac-address', 'permanent', '00:11:22:33:44:55')


class MemoryProfiles:
    def __init__(self):
        self.profiles = {}
        self.locked = False

    def remember(self, connection):
        self.profiles.setdefault(connection.uuid, connection.as_profile())

    def recorded(self, uuid):
        return self.profiles.get(uuid)

    def forget(self, uuid):
        self.profiles.pop(uuid, None)

    @contextmanager
    def lock(self):
        self.locked = True
        try:
            yield
        finally:
            self.locked = False


class CommandTests(unittest.TestCase):
    def test_empty_environment_is_not_replaced_by_host_environment(self):
        with patch('hyprrice.process.subprocess.run', return_value=SimpleNamespace(returncode=0, stdout=' ok\n')) as run:
            self.assertEqual(Command(env={}).run('probe'), 'ok')
        self.assertEqual(run.call_args.kwargs['env'], {'LC_ALL': 'C'})

    def test_detach_uses_injected_environment_and_no_stdin(self):
        with patch('hyprrice.process.subprocess.Popen') as launch:
            Command(env={'DISPLAY': ':test'}).detach('browser')
        self.assertEqual(launch.call_args.kwargs['env'], {'DISPLAY': ':test', 'LC_ALL': 'C'})
        self.assertEqual(launch.call_args.kwargs['stdin'], subprocess.DEVNULL)
        self.assertTrue(launch.call_args.kwargs['start_new_session'])

    def test_process_failures_share_the_command_error_contract(self):
        for failure in (FileNotFoundError(), PermissionError(), subprocess.TimeoutExpired('probe', 1)):
            with self.subTest(failure=failure), patch('hyprrice.process.subprocess.run', side_effect=failure):
                with self.assertRaises(CommandError):
                    Command(env={}).run('probe')
        with patch('hyprrice.process.subprocess.Popen', side_effect=PermissionError()):
            with self.assertRaises(CommandError):
                Command(env={}).detach('probe')


class InspectorTests(unittest.TestCase):
    def test_default_route_and_mac_use_injected_sources(self):
        command = FakeCommand('[{"dev":"eth0"}]', 'wlan0:wifi:connected\neth0:ethernet:connected', 'uuid-1', 'permanent')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'eth0').mkdir()
            (root/'eth0/address').write_text('00:11:22:33:44:55\n')
            result = ConnectionInspector(command, root).active()
        self.assertEqual(result.device, 'eth0')
        self.assertEqual(result.prop, ConnectionInspector.ETHERNET_PROP)
        self.assertEqual(result.mac, CONNECTION.mac)

    def test_missing_device_is_a_domain_error(self):
        command = FakeCommand('[]', 'wlan0:wifi:connected', 'uuid-1', 'permanent')
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(RiceError, 'MAC address'):
            ConnectionInspector(command, Path(directory)).active()

    def test_invalid_route_and_device_responses_are_domain_errors(self):
        for route, devices in [('invalid', ''), ('{}', ''), ('[null]', ''), ('[]', 'bad-record')]:
            with self.subTest(route=route, devices=devices), self.assertRaises(RiceError):
                ConnectionInspector(FakeCommand(route, devices)).active()


class MacTests(unittest.TestCase):
    def test_enable_records_original_and_verifies_change(self):
        store = MemoryProfiles()
        current = Connection('wlan0', 'uuid-1', CONNECTION.prop, 'random', '22:33:44:55:66:77')
        inspector = Mock(active=Mock(side_effect=[CONNECTION, current]))
        command = FakeCommand()
        MacRandomiser(command, inspector, store).apply(True)
        self.assertEqual(store.recorded('uuid-1')['setting'], 'permanent')
        self.assertEqual(command.calls[0][0][-1], 'random')

    def test_failed_verification_rolls_back_and_retains_original(self):
        store = MemoryProfiles()
        inspector = Mock(active=Mock(side_effect=[CONNECTION, RiceError('Device vanished')]))
        command = FakeCommand()
        with self.assertRaisesRegex(RiceError, 'previous connection setting was restored'):
            MacRandomiser(command, inspector, store).apply(True)
        self.assertEqual([call[0][-1] for call in command.calls if 'modify' in call[0]], ['random', 'permanent'])
        self.assertIsNotNone(store.recorded('uuid-1'))

    def test_disable_forgets_only_after_success(self):
        store = MemoryProfiles(); store.remember(CONNECTION)
        current = Connection('wlan0', 'uuid-1', CONNECTION.prop, 'random', '22:33:44:55:66:77')
        inspector = Mock(active=Mock(side_effect=[current, CONNECTION]))
        MacRandomiser(FakeCommand(), inspector, store).apply(False)
        self.assertIsNone(store.recorded('uuid-1'))

    def test_rollback_failure_preserves_restore_record(self):
        store = MemoryProfiles()
        command = FakeCommand(RiceError('modify failed'), RiceError('rollback failed'))
        with self.assertRaisesRegex(RiceError, 'original setting is saved'):
            MacRandomiser(command, Mock(active=Mock(return_value=CONNECTION)), store).apply(True)
        self.assertIsNotNone(store.recorded('uuid-1'))


class StoreTests(unittest.TestCase):
    def test_default_directory_resolves_when_constructed(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'XDG_STATE_HOME': directory}):
            store = ProfileStore()
            store.remember(CONNECTION)
            path = Path(directory)/'hypr/privacy/profiles.json'
            self.assertTrue(path.exists())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(store.recorded('uuid-1'), CONNECTION.as_profile())

    def test_malformed_records_do_not_break_status_or_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            store = ProfileStore(Path(directory))
            for data in ('not-json', '[]', '{"uuid-1": 1}', '{"uuid-1": {"setting": "random"}}'):
                (Path(directory)/'profiles.json').write_text(data)
                self.assertIsNone(store.recorded('uuid-1'))


class TorTests(unittest.TestCase):
    def test_checker_keeps_direct_and_proxy_requests_separate(self):
        command = FakeCommand('{"IP":"direct","IsTor":false}', '{"IP":"exit","IsTor":true}')
        result = TorIpChecker(command, endpoint='https://test.invalid/ip', proxy='socks5h://test:9150').check()
        self.assertEqual(result, {'direct_ip': 'direct', 'tor_ip': 'exit', 'tor_verified': True})
        direct, proxied = [call[0] for call in command.calls]
        self.assertNotIn('--proxy', direct)
        self.assertIn('socks5h://test:9150', proxied)
        self.assertEqual(proxied[-1], 'https://test.invalid/ip')

    def test_invalid_replies_never_claim_tor_is_verified(self):
        for reply in ('[]', 'null', 'true', '{"IsTor":true}', '{"IP":"exit","IsTor":"true"}', 'bad-json'):
            with self.subTest(reply=reply):
                result = TorIpChecker(FakeCommand(reply, reply)).check()
                self.assertFalse(result['tor_verified'])

    def test_browser_uses_only_injected_launcher_and_command(self):
        launch = Mock(); command = FakeCommand()
        browser = TorBrowser(command, launch=launch, which=lambda _: '/test/browser')
        browser.launch(); browser.install()
        launch.assert_called_once_with('torbrowser-launcher')
        self.assertEqual(command.calls[0][1], 600)
        self.assertEqual(command.calls[0][0][:2], ('pkexec', '/usr/bin/pacman'))

    def test_unavailable_browser_does_not_launch(self):
        launch = Mock()
        browser = TorBrowser(FakeCommand(), launch=launch, which=lambda _: None)
        with self.assertRaises(RiceError):
            browser.launch()
        launch.assert_not_called()


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.store = MemoryProfiles()
        self.inspector = Mock(active=Mock(return_value=CONNECTION))
        self.randomiser = Mock()
        self.browser = Mock(available=Mock(return_value=True))
        self.checker = Mock(check=Mock(return_value={'tor_verified': False}))
        self.service = PrivacyService(inspector=self.inspector, store=self.store, randomiser=self.randomiser,
                                      ip_checker=self.checker, browser=self.browser)

    def test_status_and_browser_actions_use_injected_adapters(self):
        self.assertEqual(self.service.status()['device'], 'wlan0')
        self.service.launch_browser(); self.browser.launch.assert_called_once_with()
        self.service.install_browser(); self.browser.install.assert_called_once_with()
        self.assertEqual(self.service.check_ip(), {'tor_verified': False})
        self.checker.check.assert_called_once_with()

    def test_network_changes_hold_injected_store_lock(self):
        self.randomiser.apply.side_effect = lambda enable: self.assertTrue(self.store.locked)
        self.service.set_randomised(True)
        self.randomiser.apply.assert_called_once_with(True)
        self.assertFalse(self.store.locked)

    def test_failure_releases_lock_and_remains_visible(self):
        self.randomiser.apply.side_effect = RiceError('refused')
        with self.assertRaisesRegex(RiceError, 'refused'):
            self.service.set_randomised(True)
        self.assertFalse(self.store.locked)

    def test_status_can_report_expected_error_without_losing_browser_state(self):
        self.inspector.active.side_effect = RiceError('offline')
        result = self.service.status()
        self.assertEqual(result['error'], 'offline')
        self.assertTrue(result['browser_available'])


if __name__ == '__main__':
    unittest.main()
