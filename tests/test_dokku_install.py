"""Exercise Dokku version selection with isolated paths and fake apt tools."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'files/install.sh'


class DokkuInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'bin').mkdir()
        (self.root / 'apt/sources.list.d').mkdir(parents=True)
        (self.root / 'home').mkdir()
        self.state = self.root / 'installed'
        self.log = self.root / 'calls'
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        STATE=str(self.state), CALLS=str(self.log),
                        VERSIONS='0.36.0-rc1 0.35.9 0.35.10 0.35.2',
                        FAKE_INSTALLED='false')
        self.bin('id', 'echo 0')
        self.bin('flock', 'exit 0')
        self.bin('curl', 'exit 0')
        self.bin('install', 'exit 0')
        self.bin('debconf-set-selections', 'cat >/dev/null')
        self.bin('apt-cache', '''[ "${FAIL_CACHE:-false}" = false ] || exit 1
printf ' dokku | 99.99.99 | https://untrusted.example/ubuntu/ noble/main amd64 Packages\\n'
for version in $VERSIONS; do
  printf ' dokku | %s | https://packagecloud.io/dokku/dokku/ubuntu/ noble/main amd64 Packages\\n' "$version"
done''')
        self.bin('dpkg-query', '''if [ ! -f "$STATE" ]; then exit 1; fi
case "$*" in *Status-Status*) printf 'installed '; cat "$STATE" ;; *) cat "$STATE" ;; esac''')
        self.bin('dpkg', '''python3 - "$@" <<'PY'
import sys
_, a, op, b = sys.argv[1:]
def v(s): return tuple(int(x) for x in s.split('.'))
raise SystemExit(not {'gt': v(a)>v(b), 'lt': v(a)<v(b), 'ge': v(a)>=v(b), 'le': v(a)<=v(b), 'eq': v(a)==v(b)}[op])
PY''')
        self.bin('apt-get', '''echo "$*" >> "$CALLS"
for arg in "$@"; do
  case "$arg" in dokku=*)
    [ "${FAIL_INSTALL:-false}" = false ] || exit 1
    printf '%s' "${arg#dokku=}" > "$STATE";;
  esac
done''')
        self.bin('dokku', '''echo "dokku $*" >> "$CALLS"
if [ "$1" = version ]; then cat "$STATE"; fi''')
        os_release = self.root / 'os-release'
        self.os_release = os_release
        os_release.write_text('ID=ubuntu\nVERSION_ID=24.04\nVERSION_CODENAME=noble\n')
        script = ((ROOT / 'files/ubuntu.sh').read_text() + '\n' + SCRIPT.read_text())
        script = script.replace('/run/lock/terraform-dokku.lock', str(self.root / 'lock'))
        script = script.replace('/root/terraform-dokku.', str(self.root / 'terraform-dokku.'))
        script = script.replace('/home/dokku', str(self.root / 'home'))
        script = script.replace('/etc/apt', str(self.root / 'apt'))
        script = script.replace('/etc/os-release', str(os_release))
        script = script.replace('set -euo pipefail', '''set -euo pipefail
command() {
  if [ "$1" = -v ] && [ "$2" = dokku ] && [ "$FAKE_INSTALLED" = false ]; then return 1; fi
  builtin command "$@"
}''', 1)
        self.script = self.root / 'install.sh'
        self.script.write_text(script)

    def bin(self, name, body):
        path = self.root / 'bin' / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_install(self, version, upgrade=False, installed=None):
        if installed is not None:
            self.state.write_text(installed)
            self.env['FAKE_INSTALLED'] = 'true'
        return subprocess.run(['bash', str(self.script), version, 'dokku.example.test',
                               str(upgrade).lower()], env=self.env, capture_output=True, text=True)

    def test_supported_ubuntu_versions_and_other_releases(self):
        for version, codename in [('22.04', 'jammy'), ('24.04', 'noble'), ('26.04', 'resolute')]:
            with self.subTest(version=version):
                self.os_release.write_text(f'ID=ubuntu\nVERSION_ID={version}\nVERSION_CODENAME={codename}\n')
                result = self.run_install('0.35.9')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f'ubuntu/ {codename} main', (self.root / 'apt/sources.list.d/dokku.list').read_text())
        for distro, version in [('ubuntu', '25.10'), ('debian', '26.04')]:
            with self.subTest(distro=distro, version=version):
                self.os_release.write_text(f'ID={distro}\nVERSION_ID={version}\nVERSION_CODENAME=other\n')
                self.log.unlink(missing_ok=True)
                result = self.run_install('0.35.9')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.log.exists())

    def test_fresh_latest_selects_highest_stable_version(self):
        result = self.run_install('latest')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), '0.35.10')
        self.assertIn('dokku domains:set-global dokku.example.test', self.log.read_text())

    def test_existing_latest_keeps_installed_version_without_upgrade(self):
        result = self.run_install('latest', installed='0.35.2')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), '0.35.2')
        self.assertIn('dokku domains:set-global dokku.example.test', self.log.read_text())

    def test_existing_latest_upgrades_only_when_allowed(self):
        result = self.run_install('latest', upgrade=True, installed='0.35.2')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), '0.35.10')

    def test_latest_does_not_downgrade_newer_existing_version(self):
        result = self.run_install('latest', upgrade=True, installed='0.40.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), '0.40.0')

    def test_explicit_pin_is_installed(self):
        result = self.run_install('0.35.9')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), '0.35.9')

    def test_explicit_upgrade_requires_permission(self):
        result = self.run_install('0.35.10', installed='0.35.2')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), '0.35.2')

    def test_explicit_downgrade_is_rejected(self):
        result = self.run_install('0.35.2', upgrade=True, installed='0.35.10')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), '0.35.10')

    def test_package_index_failure_propagates(self):
        self.env['FAIL_CACHE'] = 'true'
        result = self.run_install('latest')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state.exists())

    def test_missing_latest_fails_without_install(self):
        self.env['VERSIONS'] = '0.36.0-rc1 0.36.0~beta'
        result = self.run_install('latest')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state.exists())

    def test_package_install_failure_propagates(self):
        self.env['FAIL_INSTALL'] = 'true'
        result = self.run_install('latest')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state.exists())


if __name__ == '__main__':
    unittest.main()
