from pathlib import Path
import os, shutil, fcntl, json, shlex
from startup import login_entry
home=Path.home();stage=os.environ.get('IDLE_MINER_STAGE')
locks=[]
if stage:
 if os.environ.get('IDLE_MINER_UPDATE')!='1':raise SystemExit('Staging is reserved for a verified built-in update.')
 root=Path(stage)
 if not root.is_absolute() or root.exists():raise SystemExit('Update staging folder must be a new absolute path.')
 root.mkdir(parents=True,mode=0o700)
else:
 state=home/'.config/idle-miner';state.mkdir(parents=True,exist_ok=True,mode=0o700)
 # Stable profile and supervisor leases protect the complete shared install.
 from updates import installation_locks
 import contextlib
 guard=installation_locks(state,timeout=0)
 try:guard.__enter__()
 except TimeoutError:raise SystemExit('Quit ALL Idle Miner currency windows first, then run the installer again. Your settings have not changed.')
 root=home/'.local/share/idle-miner';root.mkdir(parents=True,exist_ok=True)
build=Path(os.environ['IDLE_MINER_BUILD'])
for name in ('app.py','core.py','coordination.py','shared_tray.py','updates.py','startup.py','platform_linux.py','network.py','icon.png','update_public_key.txt','README.txt','LICENSE.txt'):
 shutil.copy2(name,root/name)
for source,name in ((build/'xmrig-build/xmrig','xmrig'),(build/'idle-build/idle-monitor','idle-monitor'),(build/'miner-supervisor','miner-supervisor')):
 shutil.copy2(source,root/name);(root/name).chmod(0o755)
shutil.copy2('vendor/xmrig-6.26.0.tar.gz',root/'xmrig-6.26.0-source.tar.gz')
shutil.copytree('idle-helper',root/'idle-helper-source',dirs_exist_ok=True)
shutil.copy2('supervisor.c',root/'supervisor.c')
if stage:
 print('Prepared update in '+str(root));raise SystemExit(0)
launcher=home/'.local/bin/idle-miner';launcher.parent.mkdir(parents=True,exist_ok=True)
launcher.write_text('#!/bin/sh\nexec /usr/bin/python3 '+shlex.quote(str(root/'app.py'))+' "$@"\n');launcher.chmod(0o755)
# Desktop entry quoting follows the Desktop Entry specification, not a shell.
def desktop_quote(p):
 return '"'+str(p).replace('\\','\\\\').replace('"','\\"').replace('`','\\`').replace('$','\\$').replace('%','%%')+'"'
entry='[Desktop Entry]\nType=Application\nName=Idle Miner\nComment=Mining that makes room for your work\nExec='+desktop_quote(launcher)+'\nIcon='+str(root/'icon.png')+'\nTerminal=false\nCategories=Utility;\nStartupNotify=false\n'
apps=home/'.local/share/applications';apps.mkdir(parents=True,exist_ok=True)
(apps/'idle-miner.desktop').write_text(entry)
autostart=home/'.config/autostart/idle-miner.desktop'
if autostart.exists():autostart.write_text(login_entry(entry,autostart.read_text()))
print('Installed in '+str(root))
