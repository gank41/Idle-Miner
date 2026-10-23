"""Explicit user-session startup policy; shared by desktop entry installer and UI."""
from configparser import ConfigParser, Error
from core import COINS, valid_wallet

def startup_plan(settings,profile,args,login_enabled):
    if profile!='default':
        return (profile,()) if '--start-mining' in args and valid_wallet(settings['wallets'].get(profile,''),profile) else (None,())
    if '--login-startup' not in args or not login_enabled or not settings['start_mining_at_login']:return None,()
    coins=[coin for coin in COINS if valid_wallet(settings['wallets'].get(coin,''),coin)]
    if not coins:return None,()
    selected=settings['coin'] if settings['coin'] in coins else coins[0]
    return selected,tuple(coin for coin in coins if coin!=selected)

def autostart_enabled(path):
    parser=ConfigParser(interpolation=None)
    try:
        parser.read_string(path.read_text());entry=parser['Desktop Entry']
        return not entry.getboolean('Hidden',False) and entry.getboolean('X-GNOME-Autostart-enabled',True)
    except (OSError,Error,KeyError,ValueError):return False

def login_entry(regular,previous=None):
    # Only the autostart copy receives the login marker. Desktop Exec uses its
    # own quoting rules; appending a fixed argument leaves those quotes intact.
    lines=[]
    for line in regular.splitlines():
        if line.startswith('Exec=') and not line.endswith(' --login-startup'):line+=' --login-startup'
        lines.append(line)
    if previous is not None:
        for line in previous.splitlines():
            if line.startswith(('Hidden=','X-GNOME-Autostart-enabled=')):
                key=line.split('=',1)[0]+'=';lines=[old for old in lines if not old.startswith(key)];lines.append(line)
    return '\n'.join(lines)+'\n'

def save_login_preference(store,enabled):
    baseline=store.load();edited={**baseline,'start_mining_at_login':bool(enabled)}
    return store.save(edited,baseline)
