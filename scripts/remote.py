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
_DEFAULT_OPENSSH_IDENTITY_FILES = frozenset({
    "~/.ssh/id_rsa",
    "~/.ssh/id_ecdsa",
    "~/.ssh/id_ecdsa_sk",
    "~/.ssh/id_ed25519",
    "~/.ssh/id_ed25519_sk",
    "~/.ssh/id_dsa",
    "~/.ssh/id_xmss",
    "~/.ssh/id_mldsa44_ed25519",
})
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
    if operation == "ssh_key_revoke":
        return [scope, "", ""]
    public_key_path = args.get("public_key_path")
    public_key_inline = args.get("public_key")
    if public_key_path is not None and public_key_inline is not None:
        raise ValueError("Specify either public_key_path or public_key, not both")
    if public_key_path is None and public_key_inline is None:
        return [scope, "", ""]
    if public_key_path is not None:
        public_key = existing_file(public_key_path, "public_key_path").read_text()
    else:
        public_key = string(public_key_inline, "public_key")
        if "\r" in public_key or "\n" in public_key.rstrip("\n") or not public_key.strip():
            raise ValueError("public_key must be a single nonempty SSH public key line")
    return [scope, string(args.get("name"), "name"), encoded(public_key)]


def _quote_ssh_option(value):
    if "\n" in value or "\r" in value or "\x00" in value:
        raise ValueError("SSH option value cannot contain newlines or NUL bytes")
    # OpenSSH parses -o arguments using its configuration grammar, including quotes.
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _unquote_ssh_value(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value


def _is_valid_ssh_arg(value):
    return bool(value) and not value.startswith("-") and not any(ch in value for ch in ("\n", "\r", "\x00"))


def _expand_ssh_path(raw, home_dir, host, user, port):
    """Expand leading ~/ and OpenSSH % tokens in a config path."""
    path = _unquote_ssh_value(raw.strip())
    if path == "~" and home_dir:
        path = home_dir
    elif path.startswith("~/") and home_dir:
        path = str(Path(home_dir) / path[2:])
    port_str = str(port) if port else ""
    tokens = {"%": "%", "d": home_dir, "h": host, "n": host, "r": user, "p": port_str}
    out = []
    i = 0
    while i < len(path):
        if path[i] == "%" and i + 1 < len(path) and path[i + 1] in tokens:
            out.append(tokens[path[i + 1]])
            i += 2
            continue
        out.append(path[i])
        i += 1
    return "".join(out)


def _resolve_identity_agent(raw, env_sock, home_dir, host, user, port):
    """Return (ssh -o IdentityAgent value or None, effective socket path)."""
    if raw is None:
        return None, env_sock
    val = _unquote_ssh_value(raw.strip())
    if val.lower() == "none":
        return "none", ""
    if val in ("SSH_AUTH_SOCK", "$SSH_AUTH_SOCK", "${SSH_AUTH_SOCK}"):
        return None, env_sock
    if val.startswith("$"):
        expanded = re.sub(
            r"\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)",
            lambda m: os.environ.get(m.group(1) or m.group(2), ""),
            val,
        )
        return (expanded, expanded) if expanded else ("none", "")
    expanded = _expand_ssh_path(val, home_dir, host, user, port)
    return (expanded, expanded) if expanded else ("none", "")


def _is_default_openssh_identity_files(files):
    return (
        len(files) > 1
        and files[0] == "~/.ssh/id_rsa"
        and all(f in _DEFAULT_OPENSSH_IDENTITY_FILES for f in files)
    )


def _load_ssh_config(cfg_path, home_dir, host, user, port):
    """Query OpenSSH via `ssh -G` for IdentityFile, IdentitiesOnly, and IdentityAgent."""
    empty = {"identity_files": [], "identities_only": False, "identity_agent": None}
    if not _is_valid_ssh_arg(host) or (user and not _is_valid_ssh_arg(user)):
        return empty
    args = ["ssh", "-G", "-F", str(cfg_path)]
    if port:
        args += ["-p", str(port)]
    if user:
        args += ["-l", user]
    args += ["--", host]
    env = dict(os.environ, HOME=home_dir)
    try:
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=10, check=False)
    except (OSError, subprocess.SubprocessError):
        return empty
    if result.returncode != 0:
        return empty

    identity_files = []
    identities_only = False
    identity_agent = None
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) < 2:
            continue
        key, val = parts[0].lower(), _unquote_ssh_value(parts[1].strip())
        if not val:
            continue
        if key == "identityfile":
            if val.lower() != "none":
                identity_files.append(val)
        elif key == "identitiesonly":
            identities_only = val.lower() == "yes"
        elif key == "identityagent":
            identity_agent = val

    if _is_default_openssh_identity_files(identity_files):
        identity_files = []
    return {
        "identity_files": identity_files,
        "identities_only": identities_only,
        "identity_agent": identity_agent,
    }


def _resolve_agent_ssh_args(host, user, port):
    """Resolve OpenSSH auth flags from SSH_AUTH_SOCK and ~/.ssh/config via `ssh -G`."""
    env_sock = os.environ.get("SSH_AUTH_SOCK", "")
    home_env = os.environ.get("HOME", "").strip()
    home_dir = str(Path(home_env).expanduser()) if home_env else ""
    settings = {"identity_files": [], "identities_only": False, "identity_agent": None}
    if home_dir:
        cfg_path = Path(home_dir) / ".ssh" / "config"
        if cfg_path.is_file():
            settings = _load_ssh_config(cfg_path, home_dir, host, user, port)

    agent_opt, effective_agent = _resolve_identity_agent(
        settings["identity_agent"], env_sock, home_dir, host, user, port
    )

    resolved_identities = []
    seen = set()
    for raw in settings["identity_files"]:
        expanded = _expand_ssh_path(raw, home_dir, host, user, port)
        if not expanded or "\n" in expanded or "\r" in expanded or "\x00" in expanded:
            continue
        candidate = None
        if Path(expanded).is_file():
            candidate = expanded
        elif not expanded.endswith(".pub") and Path(expanded + ".pub").is_file():
            candidate = expanded + ".pub"
        if candidate and candidate not in seen:
            seen.add(candidate)
            resolved_identities.append(candidate)

    has_disk_private_key = any(not path.endswith(".pub") for path in resolved_identities)
    if not effective_agent and not has_disk_private_key:
        raise ValueError("Agent authentication requires SSH_AUTH_SOCK; otherwise supply ssh_private_key_path")

    args = []
    if agent_opt is not None:
        val = "none" if agent_opt == "none" else _quote_ssh_option(agent_opt)
        args += ["-o", f"IdentityAgent={val}"]

    identities_only = settings["identities_only"]
    if resolved_identities:
        args += ["-o", f"IdentitiesOnly={'yes' if identities_only else 'no'}"]
        for path in resolved_identities:
            args += ["-i", path]
    elif identities_only and not settings["identity_files"]:
        # Preserve OpenSSH's default ~/.ssh/id_* matching when IdentitiesOnly=yes has no explicit IdentityFile.
        args += ["-o", "IdentitiesOnly=yes"]
    elif identities_only:
        args += ["-o", "IdentityFile=none", "-o", "IdentitiesOnly=yes"]
    else:
        args += ["-o", "IdentityFile=none", "-o", "IdentitiesOnly=no"]
    return args


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
    quoted_hosts = _quote_ssh_option(str(known_hosts))
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
        command += _resolve_agent_ssh_args(host, user, port)
    remote_args = operation_args(operation, payload.get("args", {}))
    # The only remote shell command has a fixed executable and quoted arguments.
    remote_command = shlex.join(["sudo", "-n", "bash", "-s", "--", *remote_args])
    command += ["--", host, remote_command]
    script = (ROOT / SCRIPTS[operation]).read_text()
    if operation in {"install_docker", "install_dokku"}:
        # Scripts arrive over stdin, so bundle the shared guard without relying
        # on a module checkout or sourced helper file on the remote host.
        script = (ROOT / "files/ubuntu.sh").read_text() + "\n" + script
    return command, script, timeout


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
