"""Exercise OpenSSH command construction without connecting to a server."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shlex
import shutil
import subprocess
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

    def test_ubuntu_guard_is_streamed_with_both_installers_only(self):
        helper = (ROOT / 'files/ubuntu.sh').read_text().strip()
        cases = [
            ('install_docker', {'docker_version': 'auto', 'containerd_version': 'auto'}, 'files/install-docker.sh'),
            ('install_dokku', {'version': 'latest', 'hostname': 'example.test', 'allow_upgrade': False}, 'files/install.sh'),
        ]
        for operation, args, script_path in cases:
            with self.subTest(operation=operation):
                _, script, _ = remote.build_request({**self.payload, 'operation': operation, 'args': args})
                self.assertIn(helper, script)
                self.assertIn((ROOT / script_path).read_text().strip(), script)
                self.assertLess(script.index(helper), script.index('require_supported_ubuntu\n'))
        other_cases = [
            ('plugins', {'plugins': []}),
            ('configure_docker', {'config': '{}', 'allow_storage_migration': False}),
            ('ssh_key', {'management_id': 'scope', 'public_key_path': None}),
            ('ssh_key_revoke', {'management_id': 'scope'}),
        ]
        for operation, args in other_cases:
            with self.subTest(operation=operation):
                _, script, _ = remote.build_request({**self.payload, 'operation': operation, 'args': args})
                self.assertNotIn(helper, script)

    def test_main_returns_ssh_failure_and_streams_script(self):
        with patch.dict(os.environ, {'DOKKU_REMOTE_PAYLOAD': json.dumps(self.payload)}), patch.object(remote.subprocess, 'run') as run:
            run.return_value.returncode = 23
            self.assertEqual(remote.main(), 23)
            self.assertTrue(run.call_args.kwargs['input'].startswith('#!/usr/bin/env bash'))

    def test_inline_public_key_operation_args(self):
        inline = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHgoFK/JHSzDJsP4QBi6Pwe9LifvRH1vDQWcvPa4IpXo'
        result = remote.operation_args('ssh_key', {
            'management_id': 'scope',
            'name': 'admin',
            'public_key': inline,
            'public_key_path': None,
        })
        self.assertEqual(result, ['scope', 'admin', base64.b64encode(inline.encode()).decode('ascii')])

        self.assertEqual(
            remote.operation_args('ssh_key', {'management_id': 'scope', 'name': 'admin', 'public_key': None, 'public_key_path': None}),
            ['scope', '', ''],
        )
        with self.assertRaisesRegex(ValueError, 'not both'):
            remote.operation_args('ssh_key', {'management_id': 'scope', 'name': 'admin', 'public_key': inline, 'public_key_path': str(self.hosts)})
        for bad in ('   ', 'ssh-ed25519 AAAA\nssh-ed25519 BBBB', 'ssh-ed25519 AAAA\r'):
            with self.assertRaisesRegex(ValueError, 'public_key'):
                remote.operation_args('ssh_key', {'management_id': 'scope', 'name': 'admin', 'public_key': bad, 'public_key_path': None})

    def test_ssh_config_pins_identity_file_and_identity_agent(self):
        home = Path(self.temp.name) / 'home'
        ssh_dir = home / '.ssh'
        onepassword_dir = ssh_dir / '1Password'
        onepassword_dir.mkdir(parents=True)
        pub_key = onepassword_dir / 'SHA256_test.pub'
        pub_key.write_text('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHgoFK/JHSzDJsP4QBi6Pwe9LifvRH1vDQWcvPa4IpXo\n')
        (ssh_dir / 'config').write_text(
            'Match Host example.test User ubuntu\n'
            '  IdentitiesOnly yes\n'
            '  IdentityFile ~/.ssh/1Password/SHA256_test.pub\n'
            'Host *\n'
            '  IdentityAgent "~/Library/Group Containers/test/agent.sock"\n'
        )
        payload = {**self.payload, 'private_key_path': None}
        if shutil.which('ssh'):
            with patch.dict(os.environ, {'HOME': str(home)}, clear=True):
                command, _, _ = remote.build_request(payload)
            expected_agent = Path(pwd.getpwuid(os.getuid()).pw_dir) / 'Library/Group Containers/test/agent.sock'
        else:
            stdout = (
                'identitiesonly yes\n'
                'identityagent ~/Library/Group Containers/test/agent.sock\n'
                'identityfile ~/.ssh/1Password/SHA256_test.pub\n'
            )
            with patch.dict(os.environ, {'HOME': str(home)}, clear=True), \
                    patch.object(remote.subprocess, 'run') as run:
                run.return_value = subprocess.CompletedProcess(['ssh'], 0, stdout=stdout, stderr='')
                command, _, _ = remote.build_request(payload)
            expected_agent = home / 'Library/Group Containers/test/agent.sock'

        self.assertIn(f'IdentityAgent="{expected_agent}"', command)
        self.assertIn('IdentitiesOnly=yes', command)
        self.assertNotIn('IdentityFile=none', command)
        self.assertEqual(command[command.index('-i') + 1], str(pub_key))

    def test_ssh_config_default_identities_cleared_for_unconfigured_host(self):
        home = Path(self.temp.name) / 'home'
        ssh_dir = home / '.ssh'
        ssh_dir.mkdir(parents=True)
        (ssh_dir / 'config').write_text('Host other.example\n  IdentitiesOnly yes\n')
        payload = {**self.payload, 'private_key_path': None}
        if shutil.which('ssh'):
            with patch.dict(os.environ, {'HOME': str(home), 'SSH_AUTH_SOCK': '/tmp/agent'}, clear=True):
                command, _, _ = remote.build_request(payload)
        else:
            stdout = (
                'identitiesonly no\n'
                'identityfile ~/.ssh/id_rsa\n'
                'identityfile ~/.ssh/id_ed25519\n'
                'identityfile ~/.ssh/id_mldsa44_ed25519\n'
            )
            with patch.dict(os.environ, {'HOME': str(home), 'SSH_AUTH_SOCK': '/tmp/agent'}, clear=True), \
                    patch.object(remote.subprocess, 'run') as run:
                run.return_value = subprocess.CompletedProcess(['ssh'], 0, stdout=stdout, stderr='')
                command, _, _ = remote.build_request(payload)

        self.assertIn('IdentityFile=none', command)
        self.assertIn('IdentitiesOnly=no', command)
        self.assertNotIn('-i', command)

    def test_ssh_config_expands_tokens_and_pub_fallback_and_agent_variants(self):
        home = Path(self.temp.name) / 'home'
        ssh_dir = home / '.ssh'
        ssh_dir.mkdir(parents=True)
        (ssh_dir / 'config').write_text('# stub\n')
        token_pub = ssh_dir / 'example.test_ubuntu_2222.pub'
        token_pub.write_text('ssh-ed25519 AAAA\n')
        disk_key = ssh_dir / 'disk_key'
        disk_key.write_text('PRIVATE')
        payload = {**self.payload, 'private_key_path': None, 'port': 2222}

        stdout = (
            'identitiesonly yes\n'
            'identityagent $CUSTOM_SOCK\n'
            'identityfile %d/.ssh/%h_%r_%p\n'
            'identityfile ~/.ssh/missing\n'
        )
        with patch.dict(os.environ, {'HOME': str(home), 'CUSTOM_SOCK': '/tmp/custom.sock'}, clear=True), \
                patch.object(remote.subprocess, 'run') as run:
            run.return_value = subprocess.CompletedProcess(['ssh'], 0, stdout=stdout, stderr='')
            command, _, _ = remote.build_request(payload)
        self.assertIn('IdentityAgent="/tmp/custom.sock"', command)
        self.assertIn('IdentitiesOnly=yes', command)
        self.assertEqual(command[command.index('-i') + 1], str(token_pub))
        self.assertNotIn(str(ssh_dir / 'missing'), command)

        # IdentityAgent none is allowed when a non-.pub disk private key is configured.
        stdout_disk = (
            'identitiesonly yes\n'
            'identityagent none\n'
            'identityfile ~/.ssh/disk_key\n'
        )
        with patch.dict(os.environ, {'HOME': str(home)}, clear=True), \
                patch.object(remote.subprocess, 'run') as run:
            run.return_value = subprocess.CompletedProcess(['ssh'], 0, stdout=stdout_disk, stderr='')
            command, _, _ = remote.build_request(payload)
        self.assertIn('IdentityAgent=none', command)
        self.assertEqual(command[command.index('-i') + 1], str(disk_key))

        # IdentityAgent none with only a .pub file has no signing capability.
        stdout_pub_only = (
            'identitiesonly yes\n'
            'identityagent none\n'
            'identityfile %d/.ssh/%h_%r_%p.pub\n'
        )
        with patch.dict(os.environ, {'HOME': str(home), 'SSH_AUTH_SOCK': '/tmp/agent'}, clear=True), \
                patch.object(remote.subprocess, 'run') as run:
            run.return_value = subprocess.CompletedProcess(['ssh'], 0, stdout=stdout_pub_only, stderr='')
            with self.assertRaisesRegex(ValueError, 'SSH_AUTH_SOCK'):
                remote.build_request(payload)

    def test_ssh_config_failure_falls_back_and_explicit_key_skips_config(self):
        home = Path(self.temp.name) / 'home'
        ssh_dir = home / '.ssh'
        ssh_dir.mkdir(parents=True)
        (ssh_dir / 'config').write_text('Host *\n  IdentitiesOnly yes\n')

        with patch.dict(os.environ, {'HOME': str(home), 'SSH_AUTH_SOCK': '/tmp/agent'}, clear=True), \
                patch.object(remote.subprocess, 'run', side_effect=OSError('missing ssh')):
            command, _, _ = remote.build_request({**self.payload, 'private_key_path': None})
        self.assertIn('IdentityFile=none', command)
        self.assertIn('IdentitiesOnly=no', command)

        with patch.dict(os.environ, {'HOME': str(home)}, clear=True), \
                patch.object(remote.subprocess, 'run') as run:
            command, _, _ = remote.build_request(self.payload)
        run.assert_not_called()
        self.assertIn('IdentitiesOnly=yes', command)
        self.assertIn(str(self.key.resolve()), command)


if __name__ == '__main__':
    unittest.main()
