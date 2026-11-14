#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run as root' >&2; exit 1; }
[ "$#" = 1 ] || { echo 'Usage: plugins <base64-json-array>' >&2; exit 1; }
exec 9>/run/lock/terraform-dokku.lock
flock -w 600 9 || { echo 'Timed out waiting for Dokku provisioning lock' >&2; exit 1; }
python3 - "$1" <<'PY'
import base64,json,os,re,subprocess,sys
plugins=json.loads(base64.b64decode(sys.argv[1], validate=True))
if not isinstance(plugins,list): raise SystemExit('Expected a plugin array')
names=set()
for p in plugins:
    if not isinstance(p,dict) or set(p)!={'name','url','revision'}: raise SystemExit('Each plugin requires name, url and revision')
    n,u,r=(p[k] for k in ('name','url','revision'))
    if not all(isinstance(x,str) for x in (n,u)) or (r is not None and not isinstance(r,str)) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]*',n) or not re.fullmatch(r'https://[^\s]+',u) or (r is not None and not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._/-]*',r)) or (r is not None and ('..' in r or r.endswith('/') or '//' in r)) or n in names: raise SystemExit('Invalid or duplicate plugin; invalid revision')
    names.add(n)
def expected_revision(url, revision):
    if revision is None: return None
    if re.fullmatch(r'[0-9a-f]{40}', revision): return revision
    if revision.startswith('refs/'):
        patterns=[revision,revision+'^{}']
    else:
        patterns=['refs/heads/'+revision,'refs/tags/'+revision,'refs/tags/'+revision+'^{}']
    env=dict(os.environ, GIT_TERMINAL_PROMPT='0')
    result=subprocess.run(['git','ls-remote','--exit-code',url,*patterns],check=True,text=True,capture_output=True,env=env)
    refs={ref:commit for commit,ref in (line.split('\t',1) for line in result.stdout.splitlines())}
    bases=[ref for ref in refs if not ref.endswith('^{}')]
    if len(bases)!=1: raise SystemExit(f'Plugin revision {revision} is ambiguous or missing')
    return refs.get(bases[0]+'^{}',refs[bases[0]])
for p in plugins:
    n,u,r=(p[k] for k in ('name','url','revision'))
    expected=expected_revision(u,r)
    installed=subprocess.run(['dokku','plugin:installed',n],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
    path='/var/lib/dokku/plugins/available/'+n
    if installed:
        existing=subprocess.check_output(['git','-C',path,'remote','get-url','origin'],text=True).strip()
        if existing != u: raise SystemExit(f'Plugin {n} has source {existing}, expected {u}; change it manually')
        actual=subprocess.check_output(['git','-C',path,'rev-parse','HEAD'],text=True).strip()
        if expected is not None and actual != expected: subprocess.run(['dokku','plugin:update',n,r],check=True)
    else: subprocess.run(['dokku','plugin:install',u,'--name',n]+(['--committish',r] if r is not None else []),check=True)
    actual=subprocess.check_output(['git','-C',path,'rev-parse','HEAD'],text=True).strip()
    if expected is not None and actual != expected: raise SystemExit(f'Plugin {n} revision mismatch: expected {expected}, got {actual}')
PY
