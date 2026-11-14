#!/usr/bin/env python3
"""Run a module operation over verified, noninteractive system OpenSSH.

Terraform passes paths and desired configuration through DOKKU_REMOTE_PAYLOAD.
Private key contents are read only by OpenSSH, never by Terraform or this runner.
"""

import base64
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = {
    "install_docker": "files/install-docker.sh",
    "configure_docker": "modules/docker-daemon-config/files/docker-config.sh",
    "install_dokku": "files/install.sh",
    "plugins": "files/plugins.sh",
    "ssh_key": "files/ssh-key.sh",
    "ssh_key_revoke": "files/ssh-key.sh",
}


def string(value, label):
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ValueError(f"{label} must be a nonempty string")
    return value


def existing_file(value, label):
    path = Path(string(value, label)).expanduser().resolve()
    if not path.is_file():
        raise ValueError(f"{label} must name an existing regular file")
    if "\n" in str(path) or "\r" in str(path):
        raise ValueError(f"{label} cannot contain newlines")
    return path


def boolean(value, label):
    if not isinstance(value, bool):
        raise ValueError(f"{label} must be a boolean")
    return "true" if value else "false"


def encoded(value):
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def operation_args(operation, args):
    if not isinstance(args, dict):
        raise ValueError("args must be an object")
    if operation == "install_docker":
        return [string(args.get("docker_version"), "docker_version"),
                string(args.get("containerd_version"), "containerd_version")]
    if operation == "configure_docker":
        config = string(args.get("config"), "config")
        if not isinstance(json.loads(config), dict):
            raise ValueError("Docker configuration must be a JSON object")
        return [encoded(config), boolean(args.get("allow_storage_migration", False), "allow_storage_migration")]
    if operation == "install_dokku":
        return [string(args.get("version"), "version"), string(args.get("hostname"), "hostname"),
                boolean(args.get("allow_upgrade", False), "allow_upgrade")]
    if operation == "plugins":
        if args.get("remove_unlisted", False) is not False:
            raise ValueError("Automatic plugin removal is unsupported; uninstall explicitly on the server")
        plugins = args.get("plugins")
        if not isinstance(plugins, list):
            raise ValueError("plugins must be an array")
        return [encoded(json.dumps(plugins, separators=(",", ":")))]
    scope = string(args.get("management_id"), "management_id")
    if operation == "ssh_key_revoke" or args.get("public_key_path") is None:
        return [scope, "", ""]
    public_key = existing_file(args["public_key_path"], "public_key_path").read_text()
    return [scope, string(args.get("name"), "name"), encoded(public_key)]


def build_request(payload):
    """Return (OpenSSH argv, script text, timeout) without opening a connection."""
    if not isinstance(payload, dict):
        raise ValueError("DOKKU_REMOTE_PAYLOAD must be a JSON object")
    operation = payload.get("operation")
    if operation not in SCRIPTS:
        raise ValueError("Unknown remote operation")
    host = string(payload.get("host"), "host")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        if len(host) > 253 or not all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", p)
                                      for p in host.rstrip(".").split(".")):
            raise ValueError("host must be an IP address or DNS hostname") from None
    user = string(payload.get("user"), "user")
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*\$?", user):
        raise ValueError("Invalid SSH user")
    port = payload.get("port", 22)
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError("port must be an integer between 1 and 65535")
    timeout = payload.get("operation_timeout", 1800)
    if type(timeout) is not int or not 60 <= timeout <= 7200:
        raise ValueError("operation_timeout must be an integer between 60 and 7200")
    known_hosts = existing_file(payload.get("known_hosts_path"), "known_hosts_path")
    # OpenSSH parses -o arguments using its configuration grammar, including quotes.
    quoted_hosts = '"' + str(known_hosts).replace("\\", "\\\\").replace('"', '\\"') + '"'
    command = [
        "ssh", "-F", "/dev/null", "-T", "-p", str(port), "-l", user,
        "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", f"UserKnownHostsFile={quoted_hosts}", "-o", "GlobalKnownHostsFile=/dev/null",
        "-o", "UpdateHostKeys=no", "-o", "ForwardAgent=no",
        "-o", "ClearAllForwardings=yes", "-o", "PermitLocalCommand=no",
        "-o", "ControlMaster=no", "-o", "ControlPath=none",
        "-o", "ConnectTimeout=30", "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=3",
    ]
    key = payload.get("private_key_path")
    if key is not None:
        command += ["-o", "IdentitiesOnly=yes", "-i", str(existing_file(key, "private_key_path"))]
    else:
        if not os.environ.get("SSH_AUTH_SOCK"):
            raise ValueError("Agent authentication requires SSH_AUTH_SOCK; otherwise supply ssh_private_key_path")
        command += ["-o", "IdentityFile=none", "-o", "IdentitiesOnly=no"]
    remote_args = operation_args(operation, payload.get("args", {}))
    # The only remote shell command has a fixed executable and quoted arguments.
    remote_command = shlex.join(["sudo", "-n", "bash", "-s", "--", *remote_args])
    command += ["--", host, remote_command]
    return command, (ROOT / SCRIPTS[operation]).read_text(), timeout


def main():
    try:
        payload = json.loads(os.environ.get("DOKKU_REMOTE_PAYLOAD", ""))
        command, script, timeout = build_request(payload)
        result = subprocess.run(command, input=script, text=True, timeout=timeout, check=False)
        return result.returncode if result.returncode >= 0 else 1
    except subprocess.TimeoutExpired:
        print("Remote operation timed out; inspect the server before retrying", file=sys.stderr)
        return 1
    except (ValueError, OSError) as exc:
        print(f"Remote operation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
