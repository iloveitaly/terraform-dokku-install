"""Exercise daemon configuration transaction with isolated paths and fake services."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "modules/docker-daemon-config/files/docker-config.sh"


class DockerConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "bin").mkdir()
        (self.root / "docker").mkdir()
        self.log = self.root / "calls"
        self.config = self.root / "docker/daemon.json"
        self.bin("id", 'echo 0')
        self.bin("flock", 'exit 0')
        self.bin("dockerd", 'exit 0')
        self.bin("docker", 'exit 0')
        self.bin("sleep", 'exit 0')
        self.bin("systemctl", '''echo "$*" >> "$CALLS"
if [ "$1" = restart ]; then
  n=$(cat "$COUNT" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$COUNT"
  [ "$n" -ne 1 ]
fi''')
        script = SCRIPT.read_text().replace('/run/lock/terraform-dokku.lock', str(self.root / 'lock'))
        script = script.replace('/root/terraform-dokku.', str(self.root / 'terraform-dokku.'))
        script = script.replace('/etc/docker', str(self.root / 'docker'))
        self.script = self.root / 'configure.sh'
        self.script.write_text(script)
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        CALLS=str(self.log), COUNT=str(self.root / 'count'))

    def bin(self, name, body):
        path = self.root / 'bin' / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_config(self, data):
        encoded = base64.b64encode(data.encode()).decode()
        return subprocess.run(['bash', str(self.script), encoded, 'false'],
                              env=self.env, capture_output=True, text=True)

    def test_restart_failure_restores_previous_config(self):
        original = '{"log-driver":"json-file"}\n'
        self.config.write_text(original)
        result = self.run_config('{"log-driver":"local"}')
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text(), original)
        self.assertEqual(self.log.read_text().count('restart docker'), 2)

    def test_restart_failure_removes_new_config_if_none_existed(self):
        result = self.run_config('{"log-driver":"local"}')
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.config.exists())
        self.assertEqual(self.log.read_text().count('restart docker'), 2)

    def test_readiness_failure_restores_previous_config(self):
        self.config.write_text('{}')
        self.bin('systemctl', '''echo "$*" >> "$CALLS"
if [ "$1" = restart ]; then
  n=$(cat "$COUNT" 2>/dev/null || echo 0)
  echo $((n + 1)) > "$COUNT"
  exit 0
fi
[ "$(cat "$COUNT")" -gt 1 ]''')
        result = self.run_config('{"log-driver":"local"}')
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text(), '{}')
        self.assertEqual(self.log.read_text().count('restart docker'), 2)

    def test_interruption_restores_previous_config(self):
        self.config.write_text('{}')
        self.bin('systemctl', '''echo "$*" >> "$CALLS"
if [ "$1" = restart ]; then
  n=$(cat "$COUNT" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$COUNT"
  if [ "$n" = 1 ]; then kill -TERM "$PPID"; fi
fi
exit 0''')
        result = self.run_config('{"log-driver":"local"}')
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text(), '{}')
        self.assertEqual(self.log.read_text().count('restart docker'), 2)

    def test_storage_change_with_existing_data_is_rejected(self):
        self.config.write_text('{}')
        self.bin('docker', 'if [ "$1" = ps ]; then echo existing; fi')
        result = self.run_config('{"data-root":"/new-root"}')
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text(), '{}')
        self.assertFalse(self.log.exists())

    def test_storage_change_with_only_volumes_is_rejected(self):
        self.config.write_text('{}')
        self.bin('docker', 'if [ "$1" = volume ]; then echo existing-volume; fi')
        result = self.run_config('{"data-root":"/new-root"}')
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text(), '{}')
        self.assertFalse(self.log.exists())

    def test_invalid_json_does_not_modify_config_or_restart(self):
        self.config.write_text('{}')
        for data in ('bad json', '[]', 'null'):
            with self.subTest(data=data):
                result = self.run_config(data)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.config.read_text(), '{}')
                self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
