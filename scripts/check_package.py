#!/usr/bin/env python3
"""Exercise a tracked Git archive as an external Terraform/OpenTofu consumer.

No real SSH connections occur: a temporary ssh executable records requests and
returns success. The consumer, module cache, and state are moved before destroy.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {
    'main.tf', 'versions.tf', 'variables.tf', 'outputs.tf', 'plugins.tf',
    'scripts/remote.py', 'files/ubuntu.sh', 'files/install.sh', 'files/install-docker.sh',
    'files/plugins.sh', 'files/ssh-key.sh',
    'modules/docker-daemon-config/main.tf', 'modules/docker-daemon-config/variables.tf',
    'modules/docker-daemon-config/outputs.tf', 'modules/docker-daemon-config/versions.tf',
    'modules/docker-daemon-config/files/docker-config.sh',
}


def run(command, *, cwd=None, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {shlex.join(command)}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def check_package(ref, cli):
    executable = shutil.which(cli)
    if not executable:
        raise RuntimeError(f'{cli} is not installed')
    with tempfile.TemporaryDirectory(prefix='dokku-package-check-') as temp:
        root = Path(temp)
        archive = root / 'module.zip'
        run(['git', 'archive', '--format=zip', f'--output={archive}', ref], cwd=ROOT)
        with zipfile.ZipFile(archive) as package:
            corrupt = package.testzip()
            if corrupt:
                raise RuntimeError(f'Git archive has a corrupt member: {corrupt}')
            names = set(package.namelist())
            missing = REQUIRED - names
            if missing:
                raise RuntimeError(f'Git archive is missing required files: {sorted(missing)}')
            forbidden = [name for name in names if any(part in {'.git', '.terraform'} for part in Path(name).parts)
                         or name.endswith(('.tfstate', '.tfstate.backup', '.tfvars', '.tfvars.json', '.pem', '.key'))
                         or Path(name).name in {'id_rsa', 'id_ed25519'}]
            if forbidden:
                raise RuntimeError(f'Git archive contains local state or credentials: {sorted(forbidden)}')

        bin_dir = root / 'bin'
        bin_dir.mkdir()
        fake_ssh = bin_dir / 'ssh'
        fake_ssh.write_text('''#!/usr/bin/env python3
import json,os,sys
record={'args':sys.argv[1:],'script':sys.stdin.read()}
with open(os.environ['PACKAGE_SSH_LOG'],'a') as log:
    log.write(json.dumps(record)+'\\n')
''')
        fake_ssh.chmod(0o755)
        log = root / 'ssh.jsonl'
        env = dict(os.environ, PATH=f'{bin_dir}{os.pathsep}{os.environ.get("PATH", "")}',
                   PACKAGE_SSH_LOG=str(log), TF_IN_AUTOMATION='1')
        env.pop('TF_DATA_DIR', None)
        env.pop('TF_CLI_ARGS', None)
        for name in list(env):
            if name.startswith(('TF_VAR_', 'TF_CLI_ARGS_')):
                del env[name]
        identity = root / 'identity'
        identity.write_text('TEST-PRIVATE-KEY-SENTINEL\n')
        identity.chmod(0o600)
        known_hosts = root / 'known_hosts'
        known_hosts.write_text('example.test ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnly\n')
        public_key = root / 'deploy.pub'
        public_key.write_text('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnly fixture\n')
        initial = root / 'original-consumer'
        initial.mkdir()
        # JSON strings are valid HCL string literals, including paths with spaces.
        hcl = f'''module "dokku" {{
  source                    = {json.dumps(archive.as_uri())}
  ssh_host                  = "example.test"
  ssh_user                  = "ubuntu"
  ssh_private_key_path      = {json.dumps(str(identity))}
  ssh_known_hosts_path      = {json.dumps(str(known_hosts))}
  dokku_ssh_public_key_path = {json.dumps(str(public_key))}
  dokku_ssh_key_name        = "package-check"
  management_id             = "package-check-owner"
  docker_daemon_config      = "{{}}"
}}
'''
        (initial / 'main.tf').write_text(hcl)

        def invoke(directory, *args):
            return run([executable, f'-chdir={directory}', *args, '-no-color'], env=env)

        invoke(initial, 'init', '-input=false')
        invoke(initial, 'validate')
        invoke(initial, 'plan', '-input=false')
        invoke(initial, 'apply', '-input=false', '-auto-approve')
        state = json.loads(invoke(initial, 'show', '-json'))
        modules = state['values']['root_module']['child_modules']
        module = next(item for item in modules if item['address'] == 'module.dokku')
        owner = next(item for item in module['resources'] if item['address'] == 'module.dokku.terraform_data.key_ownership')
        owner_input = owner['values']['input']
        if 'runner' in owner_input or str(initial) in json.dumps(owner_input):
            raise RuntimeError('Key ownership state contains an absolute runner path')
        if 'TEST-PRIVATE-KEY-SENTINEL' in json.dumps(state):
            raise RuntimeError('Private key contents appeared in Terraform state')
        before = [json.loads(line) for line in log.read_text().splitlines()]
        if not before or not any(' NAME=' in item['script'] for item in before):
            raise RuntimeError('Fake SSH did not receive the key registration script')
        for marker in ('docker_requested=', 'old_hostname='):
            streamed = [item['script'] for item in before if marker in item['script']]
            if len(streamed) != 1 or 'require_supported_ubuntu()' not in streamed[0]:
                raise RuntimeError(f'Fake SSH did not receive Ubuntu guard with installer {marker}')
        relocated = root / 'relocated-consumer'
        shutil.move(str(initial), relocated)
        if initial.exists():
            raise RuntimeError('Original consumer path remains available')
        invoke(relocated, 'destroy', '-input=false', '-auto-approve')
        after = [json.loads(line) for line in log.read_text().splitlines()]
        revocations = []
        for item in after[len(before):]:
            args = shlex.split(item['args'][-1])
            if args == ['sudo', '-n', 'bash', '-s', '--', 'package-check-owner', '', '']:
                revocations.append(item)
        if len(revocations) != 1 or 'Key rollback failed' not in revocations[0]['script']:
            raise RuntimeError('Relocated destroy did not run the expected key-revocation script')
        print(f'{cli}: archive {ref} initialized, planned, applied and destroyed after relocation')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='HEAD', help='Git ref to archive (default: HEAD)')
    parser.add_argument('--cli', choices=['terraform', 'tofu'], default='terraform')
    args = parser.parse_args()
    try:
        check_package(args.ref, args.cli)
    except (OSError, RuntimeError, KeyError, StopIteration, ValueError) as exc:
        print(f'Package check failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
