"""Exercise deploy key ownership, validation, rotation and revocation in isolation."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class KeyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'bin').mkdir()
        (self.root / 'home').mkdir()
        for name, body in {
            'id': 'echo 0',
            'flock': 'exit 0',
            'ssh-keygen': 'if grep -q invalid "$2"; then exit 1; fi\nexit 0',
            'dokku': "[ \"${FAIL_ADD:-}\" != yes ] || exit 42\npython3 -c 'import os,sys; open(os.environ[\"AUTH\"],\"a\").write(\" NAME=\\\\\\\"\"+sys.argv[1]+\"\\\\\\\" key\\n\")' \"$2\"",
        }.items():
            path = self.root / 'bin' / name
            path.write_text('#!/bin/sh\n' + body + '\n')
            path.chmod(0o755)
        script = (ROOT / 'files/ssh-key.sh').read_text()
        script = script.replace('/run/lock/terraform-dokku.lock', str(self.root / 'lock'))
        script = script.replace('/var/lib/terraform-dokku/keys', str(self.root / 'ledger'))
        script = script.replace("pwd.getpwnam('dokku')", "type('User', (), {'pw_dir': os.environ['TEST_HOME'], 'pw_uid': os.getuid(), 'pw_gid': os.getgid()})()")
        script = script.replace("dir='/root'", "dir=os.environ['TEST_HOME']")
        self.script = self.root / 'key.sh'
        self.script.write_text(script)
        self.auth = self.root / 'home/.ssh/authorized_keys'
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}", TEST_HOME=str(self.root / 'home'), AUTH=str(self.auth))

    def run_key(self, name, key):
        encoded = base64.b64encode(key.encode()).decode()
        return subprocess.run(['bash', str(self.script), 'scope', name, encoded], env=self.env, capture_output=True, text=True)

    def test_rotation_and_revocation_preserve_unmanaged_key(self):
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertEqual(result.returncode, 0, result.stderr)
        with self.auth.open('a') as f:
            f.write('unmanaged key\n')
        result = self.run_key('second', 'ssh-ed25519 BBBB second')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('second', self.auth.read_text())
        self.assertNotIn('first', self.auth.read_text())
        result = self.run_key('', '')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.auth.read_text(), 'unmanaged key\n')

    def test_invalid_replacement_preserves_existing_key(self):
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertEqual(result.returncode, 0, result.stderr)
        original = self.auth.read_bytes()
        result = self.run_key('second', 'invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.auth.read_bytes(), original)

    def test_add_failure_restores_existing_key(self):
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertEqual(result.returncode, 0, result.stderr)
        original = self.auth.read_bytes()
        self.env['FAIL_ADD'] = 'yes'
        result = self.run_key('second', 'ssh-ed25519 BBBB second')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.auth.read_bytes(), original)

    def test_revoke_missing_ledger_does_not_require_dokku_user(self):
        script = self.script.read_text().replace(
            "type('User', (), {'pw_dir': os.environ['TEST_HOME'], 'pw_uid': os.getuid(), 'pw_gid': os.getgid()})()",
            "(_ for _ in ()).throw(KeyError('dokku user missing'))")
        self.script.write_text(script)
        result = self.run_key('', '')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.auth.exists())

    def test_termination_during_add_restores_key_and_ledger(self):
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertEqual(result.returncode, 0, result.stderr)
        original = self.auth.read_bytes()
        ledger = self.root / 'ledger/scope.json'
        old_ledger = ledger.read_bytes()
        dokku = self.root / 'bin/dokku'
        dokku.write_text('#!/bin/sh\nkill -TERM "$PPID"\nexit 1\n')
        result = self.run_key('second', 'ssh-ed25519 BBBB second')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.auth.read_bytes(), original)
        self.assertEqual(ledger.read_bytes(), old_ledger)

    def test_termination_after_ledger_commit_restores_key_and_ledger(self):
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertEqual(result.returncode, 0, result.stderr)
        original = self.auth.read_bytes()
        ledger = self.root / 'ledger/scope.json'
        old_ledger = ledger.read_bytes()
        statement = 'write_atomic(ledger,json.dumps(state).encode(),0o600,os.geteuid(),os.getegid())'
        script = self.script.read_text()
        self.assertIn(statement, script)
        script = script.replace(statement, statement + "\n            os.kill(os.getpid(),signal.SIGTERM)")
        self.script.write_text(script)
        result = self.run_key('second', 'ssh-ed25519 BBBB second')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.auth.read_bytes(), original)
        self.assertEqual(ledger.read_bytes(), old_ledger)

    def test_does_not_chown_existing_ssh_directory(self):
        ssh = self.root / 'home/.ssh'
        ssh.mkdir()
        script = self.script.read_text().replace(
            'scope,name,encoded=sys.argv[1:]',
            "_chown=os.chown\ndef checked_chown(path, uid, gid):\n    if os.path.isdir(path): raise RuntimeError('directory ownership changed')\n    return _chown(path, uid, gid)\nos.chown=checked_chown\nscope,name,encoded=sys.argv[1:]")
        self.script.write_text(script)
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_symlinked_ssh_directory(self):
        target = self.root / 'other'
        target.mkdir()
        (self.root / 'home/.ssh').symlink_to(target, target_is_directory=True)
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((target / 'authorized_keys').exists())

    def test_rejects_symlinked_dokku_home(self):
        target = self.root / 'home'
        link = self.root / 'home-link'
        link.symlink_to(target, target_is_directory=True)
        self.env['TEST_HOME'] = str(link)
        result = self.run_key('first', 'ssh-ed25519 AAAA first')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((target / '.ssh/authorized_keys').exists())

    def test_rejects_unsafe_name_without_changes(self):
        result = self.run_key('bad;touch', 'ssh-ed25519 AAAA test')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.auth.exists())


if __name__ == '__main__':
    unittest.main()
