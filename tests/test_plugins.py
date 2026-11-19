"""Check that failed Dokku plugin installation is reported to Terraform."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PluginTests(unittest.TestCase):
    def test_install_failure_propagates(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, body in {
                'id': 'echo 0',
                'flock': 'exit 0',
                'dokku': 'if [ "$1" = plugin:installed ]; then exit 1; fi\nexit 42',
            }.items():
                file = root / name
                file.write_text('#!/bin/sh\n' + body + '\n')
                file.chmod(0o755)
            script = (ROOT / 'files/plugins.sh').read_text().replace('/run/lock/terraform-dokku.lock', str(root / 'lock'))
            file = root / 'plugins.sh'
            file.write_text(script)
            data = base64.b64encode(json.dumps([{'name': 'test', 'url': 'https://example.com/a/b.git', 'revision': 'a' * 40}]).encode()).decode()
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}")
            result = subprocess.run(['bash', str(file), data], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('plugin:install', result.stderr)


class PluginReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.head = self.root / 'head'
        self.head.write_text('a' * 40)
        self.log = self.root / 'calls'
        commands = {
            'id': 'echo 0',
            'flock': 'exit 0',
            'git': """if [ "$1" = -c ] && [ "$2" = "safe.directory=/var/lib/dokku/plugins/available/test" ] && [ "$3" = -C ] && [ "$4" = /var/lib/dokku/plugins/available/test ]; then
  if [ "$5" = remote ]; then printf '%s\\n' "$PLUGIN_URL"; exit 0; fi
  if [ "$5" = rev-parse ]; then cat "$HEAD_FILE"; exit 0; fi
fi
exit 1""",
            'dokku': """echo "$*" >> "$CALLS"
if [ "$1" = plugin:installed ]; then exit "${INSTALLED_EXIT:-0}"; fi
if [ "$1" = plugin:install ]; then printf '%s' "${INSTALL_HEAD:-$UPDATE_HEAD}" > "$HEAD_FILE"; exit 0; fi
if [ "$1" = plugin:update ]; then printf '%s' "$UPDATE_HEAD" > "$HEAD_FILE"; exit 0; fi
exit 1""",
        }
        for name, body in commands.items():
            path = self.root / name
            path.write_text('#!/bin/sh\n' + body + '\n')
            path.chmod(0o755)
        script = (ROOT / 'files/plugins.sh').read_text().replace('/run/lock/terraform-dokku.lock', str(self.root / 'lock'))
        self.script = self.root / 'plugins.sh'
        self.script.write_text(script)
        self.env = dict(os.environ, PATH=f"{self.root}:{os.environ['PATH']}", PLUGIN_URL='https://example.com/a/b.git', HEAD_FILE=str(self.head), UPDATE_HEAD='b' * 40, CALLS=str(self.log))

    def run_plugin(self, revision):
        data = base64.b64encode(json.dumps([{'name': 'test', 'url': 'https://example.com/a/b.git', 'revision': revision}]).encode()).decode()
        return subprocess.run(['bash', str(self.script), data], env=self.env, capture_output=True, text=True)

    def test_source_mismatch_rejected(self):
        self.env['PLUGIN_URL'] = 'https://example.com/a/other.git'
        result = self.run_plugin('a' * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('expected', result.stderr)
        self.assertNotIn('plugin:update', self.log.read_text())

    def test_current_revision_is_noop(self):
        result = self.run_plugin('a' * 40)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('plugin:update', self.log.read_text())

    def test_revision_update_is_verified(self):
        result = self.run_plugin('b' * 40)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('plugin:update test', self.log.read_text())
        self.assertEqual(self.head.read_text(), 'b' * 40)

    def test_update_revision_mismatch_fails(self):
        self.env['UPDATE_HEAD'] = 'c' * 40
        result = self.run_plugin('b' * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('revision mismatch', result.stderr)

    def test_fresh_install_verifies_revision(self):
        self.env['INSTALLED_EXIT'] = '1'
        self.env['INSTALL_HEAD'] = 'b' * 40
        result = self.run_plugin('b' * 40)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('plugin:install https://example.com/a/b.git --name test --committish', self.log.read_text())
        self.assertEqual(self.head.read_text(), 'b' * 40)


if __name__ == '__main__':
    unittest.main()
