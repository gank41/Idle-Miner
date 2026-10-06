from pathlib import Path
import os, shutil, fcntl, json, shlex
home=Path.home(); state=home/'.config/idle-miner';state.mkdir(parents=True,exist_ok=True,mode=0o700)
# Hold all stable profile locks before replacing shared executable/source files.
# Keep the lock files themselves: removing one would permit a second controller.
locks=[]
quota=open(state/'quota.lock','a');fcntl.flock(quota,fcntl.LOCK_EX)
for name in ('app.lock','BTC.lock','LTC.lock','DOGE.lock','default.engine.lock','BTC.engine.lock','LTC.engine.lock','DOGE.engine.lock'):
 lock=open(state/name,'a')
 try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 except BlockingIOError:raise SystemExit('Quit ALL Idle Miner currency windows first, then run the installer again. Your settings have not changed.')
 locks.append(lock)
root=home/'.local/share/idle-miner';root.mkdir(parents=True,exist_ok=True)
build=Path(os.environ['IDLE_MINER_BUILD'])
for name in ('app.py','core.py','coordination.py','platform_linux.py','network.py','icon.png','README.txt','LICENSE.txt'):
 shutil.copy2(name,root/name)
for source,name in ((build/'xmrig-build/xmrig','xmrig'),(build/'idle-build/idle-monitor','idle-monitor'),(build/'miner-supervisor','miner-supervisor')):
 shutil.copy2(source,root/name);(root/name).chmod(0o755)
shutil.copy2('vendor/xmrig-6.26.0.tar.gz',root/'xmrig-6.26.0-source.tar.gz')
shutil.copytree('idle-helper',root/'idle-helper-source',dirs_exist_ok=True)
shutil.copy2('supervisor.c',root/'supervisor.c')
launcher=home/'.local/bin/idle-miner';launcher.parent.mkdir(parents=True,exist_ok=True)
launcher.write_text('#!/bin/sh\nexec /usr/bin/python3 '+shlex.quote(str(root/'app.py'))+' "$@"\n');launcher.chmod(0o755)
# Desktop entry quoting follows the Desktop Entry specification, not a shell.
def desktop_quote(p):
 return '"'+str(p).replace('\\','\\\\').replace('"','\\"').replace('`','\\`').replace('$','\\$').replace('%','%%')+'"'
entry='[Desktop Entry]\nType=Application\nName=Idle Miner\nComment=Mining that makes room for your work\nExec='+desktop_quote(launcher)+'\nIcon='+str(root/'icon.png')+'\nTerminal=false\nCategories=Utility;\nStartupNotify=false\n'
apps=home/'.local/share/applications';apps.mkdir(parents=True,exist_ok=True)
(apps/'idle-miner.desktop').write_text(entry)
print('Installed in '+str(root))
