#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run as root' >&2; exit 1; }
# shellcheck disable=SC2015
[ "$#" = 3 ] && [ "${#1}" -le 200 ] && [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] && { [[ -z $2 && -z $3 ]] || [[ $2 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ && -n $3 ]]; } || { echo 'Usage: ssh-key <scope> <name> <base64-key> (empty name and key revoke)' >&2; exit 1; }
exec 9>/run/lock/terraform-dokku.lock
flock -w 600 9 || { echo 'Timed out waiting for Dokku provisioning lock' >&2; exit 1; }
python3 - "$@" <<'PY'
import base64,json,os,pathlib,pwd,signal,subprocess,sys,tempfile
scope,name,encoded=sys.argv[1:]
ledgerdir=pathlib.Path('/var/lib/terraform-dokku/keys')
ledger=ledgerdir/(scope+'.json')
if ledger.is_symlink(): raise SystemExit('Refusing symlink for key state')
# No owner means there is nothing to revoke, even if Dokku was never installed.
if not name and not ledger.exists(): sys.exit(0)
user=pwd.getpwnam('dokku'); home=pathlib.Path(user.pw_dir); ssh=home/'.ssh'; auth=ssh/'authorized_keys'
if home.is_symlink() or not home.is_dir(): raise SystemExit('Dokku home must be a real directory')
if ssh.is_symlink() or (ssh.exists() and not ssh.is_dir()): raise SystemExit('Dokku .ssh must be a real directory')
ledgerdir.mkdir(parents=True,mode=0o700,exist_ok=True)
if auth.is_symlink(): raise SystemExit('Refusing symlink for key state')

def snapshot(path):
    if not path.exists(): return None
    st=path.stat()
    return (path.read_bytes(),st.st_mode & 0o7777,st.st_uid,st.st_gid)

auth_before=snapshot(auth); ledger_before=snapshot(ledger)
old=json.loads(ledger_before[0]) if ledger_before else None
before=auth_before[0] if auth_before else None
lines=(before or b'').splitlines(keepends=True)
oldline=base64.b64decode(old['line']) if old else None
if oldline and sum(line.rstrip(b'\n')==oldline for line in lines)>1: raise SystemExit('Ambiguous previously managed key')
if oldline: lines=[line for line in lines if line.rstrip(b'\n')!=oldline]

class Interrupted(Exception): pass

def on_signal(signum, frame):
    raise Interrupted(f'Interrupted by signal {signum}')

signals={signal.SIGHUP,signal.SIGINT,signal.SIGTERM}
for sig in signals: signal.signal(sig,on_signal)

def block_signals():
    return signal.pthread_sigmask(signal.SIG_BLOCK,signals)

def write_atomic(path,data,mode,uid,gid):
    fd,tmp=tempfile.mkstemp(prefix='.terraform-dokku-',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as f: f.write(data)
        os.chown(tmp,uid,gid); os.chmod(tmp,mode)
        mask=block_signals()
        try: os.replace(tmp,path)
        finally: signal.pthread_sigmask(signal.SIG_SETMASK,mask)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def restore(path,previous):
    if previous is None: path.unlink(missing_ok=True)
    else: write_atomic(path,*previous)

def rollback():
    # Prevent a second signal from interrupting restoration of either file.
    mask=block_signals()
    errors=[]
    try:
        for path,previous in ((auth,auth_before),(ledger,ledger_before)):
            try: restore(path,previous)
            except Exception as exc: errors.append(f'{path}: {exc}')
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK,mask)
    if errors: print('Key rollback failed: '+ '; '.join(errors),file=sys.stderr)

def ensure_ssh_directory():
    if home.is_symlink() or not home.is_dir(): raise RuntimeError('Dokku home must be a real directory')
    try:
        os.mkdir(ssh,0o700)
    except FileExistsError:
        pass
    else:
        os.chown(ssh,user.pw_uid,user.pw_gid,follow_symlinks=False)
    if ssh.is_symlink() or not ssh.is_dir(): raise RuntimeError('Dokku .ssh must be a real directory')

def transaction(keypath=None,key=None,marker=None):
    try:
        write_atomic(auth,b''.join(lines),0o600,user.pw_uid,user.pw_gid)
        if name:
            # Stop the whole Dokku subprocess group before restoring the files.
            # A surviving sshcommand child could otherwise overwrite a rollback.
            mask=block_signals()
            try:
                proc=subprocess.Popen(['dokku','ssh-keys:add',name,keypath],start_new_session=True, preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK,mask))
            except BaseException:
                signal.pthread_sigmask(signal.SIG_SETMASK,mask)
                raise
            try:
                signal.pthread_sigmask(signal.SIG_SETMASK,mask)
                if proc.wait() != 0: raise subprocess.CalledProcessError(proc.returncode,proc.args)
            except BaseException:
                try: os.killpg(proc.pid,signal.SIGKILL)
                except ProcessLookupError: pass
                proc.wait()
                raise
            after=auth.read_bytes().splitlines()
            new=[line for line in after if marker in line]
            if len(new)!=1: raise RuntimeError('Could not identify added key uniquely')
            state={'name':name,'key':base64.b64encode(key.rstrip(b'\n')).decode(),'line':base64.b64encode(new[0]).decode()}
            write_atomic(ledger,json.dumps(state).encode(),0o600,os.geteuid(),os.getegid())
        else:
            mask=block_signals()
            try: ledger.unlink()
            finally: signal.pthread_sigmask(signal.SIG_SETMASK,mask)
    except BaseException:
        rollback()
        raise

if name:
    key=base64.b64decode(encoded,validate=True)
    if b'\n' in key.rstrip(b'\n') or b'\r' in key or not key.strip(): raise SystemExit('Expected exactly one public key')
    marker=(' NAME=\\"'+name+'\\" ').encode()
    if any(marker in line for line in lines): raise SystemExit('Key name already belongs to another key')
    fd,keypath=tempfile.mkstemp(prefix='terraform-dokku-key-',dir='/root')
    try:
        with os.fdopen(fd,'wb') as f: f.write(key.rstrip(b'\n')+b'\n')
        subprocess.run(['ssh-keygen','-lf',keypath],check=True,stdout=subprocess.DEVNULL)
        if old and old['name']==name and old.get('key')==base64.b64encode(key.rstrip(b'\n')).decode() and oldline in [x.rstrip(b'\n') for x in (before or b'').splitlines(keepends=True)]: sys.exit(0)
        ensure_ssh_directory()
        transaction(keypath,key,marker)
    finally: os.unlink(keypath)
elif old:
    ensure_ssh_directory()
    transaction()
PY
