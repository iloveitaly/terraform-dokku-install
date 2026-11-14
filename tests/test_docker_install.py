"""Check Docker's supported OS gate and repository selection without host changes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DockerInstallOsTests(unittest.TestCase):
    def run_installer(self, distro, version, codename):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            apt = root / 'apt'
            (apt / 'sources.list.d').mkdir(parents=True)
            calls = root / 'calls'
            # Fail at the second apt update, after the repository file is written,
            # to avoid invoking package resolution or system service commands.
            commands = {
                'id': 'echo 0',
                'flock': 'exit 0',
                'install': 'exit 0',
                'curl': 'exit 0',
                'dpkg': 'echo amd64',
                'apt-get': '''echo "$*" >> "$CALLS"
if [ "$(wc -l < "$CALLS" | tr -d ' ')" -ge 3 ]; then exit 77; fi''',
            }
            for name, body in commands.items():
                path = bin_dir / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            release = root / 'os-release'
            release.write_text(f'ID={distro}\nVERSION_ID={version}\nVERSION_CODENAME={codename}\n')
            script = (ROOT / 'files/ubuntu.sh').read_text() + '\n' + (ROOT / 'files/install-docker.sh').read_text()
            script = script.replace('/run/lock/terraform-dokku.lock', str(root / 'lock'))
            script = script.replace('/etc/os-release', str(release))
            script = script.replace('/etc/apt', str(apt))
            script = script.replace('/root/terraform-dokku.', str(root / 'terraform-dokku.'))
            script = script.replace('set -euo pipefail', '''set -euo pipefail
command() {
  if [ "$1" = -v ] && [ "$2" = cloud-init ]; then return 1; fi
  builtin command "$@"
}''', 1)
            local_script = root / 'installer.sh'
            local_script.write_text(script)
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", CALLS=str(calls))
            result = subprocess.run(['bash', str(local_script), '28.5.2', '1.7.28'],
                                    env=env, capture_output=True, text=True)
            repo = apt / 'sources.list.d/docker.list'
            return result, repo.read_text() if repo.exists() else None, calls.exists()

    def test_supported_ubuntu_releases_select_their_repository(self):
        for version, codename in [('22.04', 'jammy'), ('24.04', 'noble'), ('26.04', 'resolute')]:
            with self.subTest(version=version):
                result, repo, called = self.run_installer('ubuntu', version, codename)
                self.assertEqual(result.returncode, 77, result.stderr)
                self.assertTrue(called)
                self.assertIn(f'https://download.docker.com/linux/ubuntu {codename} stable', repo)

    def test_other_distributions_or_releases_are_rejected_before_apt(self):
        for distro, version in [('ubuntu', '25.10'), ('debian', '26.04')]:
            with self.subTest(distro=distro, version=version):
                result, repo, called = self.run_installer(distro, version, 'other')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(called)
                self.assertIsNone(repo)


class DockerInstallVersionsTests(unittest.TestCase):
    def run_installer(self, release, docker, containerd, available_docker, available_containerd):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            apt = root / 'apt'
            (apt / 'sources.list.d').mkdir(parents=True)
            (apt / 'preferences.d').mkdir()
            calls = root / 'calls'
            commands = {
                'id': 'echo 0',
                'flock': 'exit 0',
                'curl': 'exit 0',
                'install': 'case "${3:-}" in */docker.pref) cat "$3" >> "$CALLS";; esac\nexit 0',
                'systemctl': 'exit 0',
                'docker': 'exit 0',
                'dpkg': 'if [ "$1" = --print-architecture ]; then echo amd64; else exit 1; fi',
                'dpkg-query': 'test -f "$STATEDIR/$3" || exit 1; cat "$STATEDIR/$3"',
                'apt-cache': """case "$2" in
  docker-ce|docker-ce-cli) version=$DOCKER_AVAILABLE ;;
  containerd.io) version=$CONTAINERD_AVAILABLE ;;
  *) exit 1 ;;
esac
printf ' %s | %s-1~ubuntu.test | example stable\\n' "$2" "$version"
""",
                'apt-get': """echo "$*" >> "$CALLS"
for arg in "$@"; do
  case "$arg" in docker-ce=*|docker-ce-cli=*|containerd.io=*)
    printf '%s' "${arg#*=}" > "$STATEDIR/${arg%%=*}" ;;
  esac
done""",
            }
            for name, body in commands.items():
                path = bin_dir / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            os_release = root / 'os-release'
            code = {'22.04': 'jammy', '24.04': 'noble', '26.04': 'resolute'}[release]
            os_release.write_text(f'ID=ubuntu\nVERSION_ID={release}\nVERSION_CODENAME={code}\n')
            script = (ROOT / 'files/ubuntu.sh').read_text() + '\n' + (ROOT / 'files/install-docker.sh').read_text()
            script = script.replace('/run/lock/terraform-dokku.lock', str(root / 'lock'))
            script = script.replace('/etc/os-release', str(os_release))
            script = script.replace('/etc/apt', str(apt))
            script = script.replace('/root/terraform-dokku.', str(root / 'terraform-dokku.'))
            script = script.replace('set -euo pipefail', """set -euo pipefail
command() {
  if [ "$1" = -v ] && [ "$2" = cloud-init ]; then return 1; fi
  builtin command "$@"
}""", 1)
            local_script = root / 'installer.sh'
            local_script.write_text(script)
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", CALLS=str(calls),
                       STATEDIR=str(root), DOCKER_AVAILABLE=available_docker,
                       CONTAINERD_AVAILABLE=available_containerd)
            result = subprocess.run(['bash', str(local_script), docker, containerd],
                                    env=env, capture_output=True, text=True)
            return result, calls.read_text() if calls.exists() else ''

    def test_auto_uses_fixed_pins_for_each_ubuntu_release(self):
        for release, docker, containerd in [('22.04', '28.5.2', '1.7.28'),
                                           ('24.04', '28.5.2', '1.7.28'),
                                           ('26.04', '29.4.3', '2.2.5')]:
            with self.subTest(release=release):
                result, calls = self.run_installer(release, 'auto', 'auto', docker, containerd)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f'docker-ce={docker}-1~ubuntu.test', calls)
                self.assertIn(f'containerd.io={containerd}-1~ubuntu.test', calls)
                for package, expected in [('docker-ce', docker), ('docker-ce-cli', docker), ('containerd.io', containerd)]:
                    self.assertIn(f'Package: {package}\nPin: version {expected}-1~ubuntu.test\nPin-Priority: 990', calls)

    def test_explicit_and_auto_versions_are_resolved_independently(self):
        result, calls = self.run_installer('26.04', '30.0.1', 'auto', '30.0.1', '2.2.5')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('docker-ce=30.0.1-1~ubuntu.test', calls)
        self.assertIn('containerd.io=2.2.5-1~ubuntu.test', calls)
        result, calls = self.run_installer('26.04', 'auto', '2.3.0', '29.4.3', '2.3.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('docker-ce=29.4.3-1~ubuntu.test', calls)
        self.assertIn('containerd.io=2.3.0-1~ubuntu.test', calls)

    def test_unavailable_explicit_pin_does_not_fall_back(self):
        result, calls = self.run_installer('26.04', '28.5.2', 'auto', '29.4.3', '2.2.5')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No docker-ce package for upstream version 28.5.2', result.stderr)
        self.assertNotIn('docker-ce=', calls)


if __name__ == '__main__':
    unittest.main()
