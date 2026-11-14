"""Exercise OpenSSH command construction without connecting to a server."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('remote', ROOT / 'scripts/remote.py')
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)


class RemoteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.hosts = root / 'known hosts'
        self.hosts.write_text('example.test ssh-ed25519 AAAA\n')
        self.key = root / 'identity'
        self.key.write_text('PRIVATE KEY MUST NOT BE READ')
        self.payload = {'host': 'example.test', 'user': 'ubuntu', 'port': 22,
                        'known_hosts_path': str(self.hosts), 'private_key_path': str(self.key),
                        'operation': 'install_dokku',
                        'args': {'version': '0.35.20', 'hostname': 'example.test', 'allow_upgrade': False}}

    def test_strict_hosts_key_path_and_no_private_key_read(self):
        original = Path.read_text
        def read(path, *args, **kwargs):
            if path == self.key.resolve():
                self.fail('Runner read private key contents')
            return original(path, *args, **kwargs)
        with patch.object(Path, 'read_text', read):
            command, script, timeout = remote.build_request(self.payload)
        self.assertIn('StrictHostKeyChecking=yes', command)
        self.assertIn('GlobalKnownHostsFile=/dev/null', command)
        self.assertIn('UserKnownHostsFile="' + str(self.hosts.resolve()) + '"', command)
        self.assertIn(str(self.key.resolve()), command)
        self.assertIn('IdentitiesOnly=yes', command)
        self.assertEqual(command[-3:-1], ['--', 'example.test'])
        self.assertIn('dokku', script)
        self.assertEqual(timeout, 1800)

    def test_remote_args_are_shell_quoted(self):
        self.payload['args']['hostname'] = "example.test; touch /tmp/bad 'quoted'"
        command, _, _ = remote.build_request(self.payload)
        self.assertEqual(shlex.split(command[-1]), ['sudo', '-n', 'bash', '-s', '--', '0.35.20', self.payload['args']['hostname'], 'false'])

    def test_agent_requires_socket(self):
        self.payload['private_key_path'] = None
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'SSH_AUTH_SOCK'):
                remote.build_request(self.payload)
        with patch.dict(os.environ, {'SSH_AUTH_SOCK': '/tmp/agent'}):
            command, _, _ = remote.build_request(self.payload)
        self.assertIn('IdentitiesOnly=no', command)

    def test_rejects_option_injection_and_missing_known_hosts(self):
        for field, value in [('host', '-oProxyCommand=evil'), ('user', '-root'), ('port', 0), ('known_hosts_path', '/missing/path')]:
            with self.subTest(field=field):
                payload = {**self.payload, field: value}
                with self.assertRaises(ValueError):
                    remote.build_request(payload)

    def test_main_returns_ssh_failure_and_streams_script(self):
        with patch.dict(os.environ, {'DOKKU_REMOTE_PAYLOAD': json.dumps(self.payload)}), patch.object(remote.subprocess, 'run') as run:
            run.return_value.returncode = 23
            self.assertEqual(remote.main(), 23)
            self.assertTrue(run.call_args.kwargs['input'].startswith('#!/usr/bin/env bash'))


if __name__ == '__main__':
    unittest.main()
