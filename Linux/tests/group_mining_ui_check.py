"""Exercise main and tray group actions with temporary wallets and no engine/network."""
import os
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

with TemporaryDirectory(prefix='idle-group-ui-') as home:
    os.environ['HOME'] = home
    os.environ['IDLE_MINER_STATE'] = str(Path(home) / 'state')
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from PySide6.QtWidgets import QApplication
    import app
    from core import Environment, validated

    qt = QApplication([])
    qt.setQuitOnLastWindowClosed(False)
    primary = app.Window(offline_test=True)
    primary.timer.stop()
    baseline = primary.store.load()
    edit = validated(baseline)
    edit['coin'] = 'BTC'
    edit['wallets'].update(BTC='1BoatSLRHtKNngkdXEeobR76b53LETtpyT',
                           LTC='LKKHMBjCU89fyFNgSRprDoD8Jb25N8uWvd',
                           ETH='0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed')
    primary.store.save(edit, baseline)
    primary.switch_currency('BTC')

    # ETH is already open in the LTC slot. Litecoin must take a free slot.
    peer = app.Window(offline_test=True, profile='LTC', initial_coin='ETH')
    for window in (primary, peer):
        window.timer.stop()
        window.sensors.sample = lambda *_: Environment(on_ac=False)
        window.sensors.available_bytes = 0

    menu = primary.menuBar().actions()[0].menu()
    start = next(a for a in menu.actions() if a.text() == 'Start All Mining')
    with patch('app.subprocess.Popen') as launch:
        start.trigger()
        peer.tick()
        assert primary.enabled and peer.enabled
        assert primary.proc is None and peer.proc is None
        assert launch.call_count == 1
        args = launch.call_args.args[0]
        assert '--currency=LTC' in args and '--profile=LTC' not in args
        request = next(a for a in args if a.startswith('--start-configured-mining='))
        assert peer.shared_tray.permits_group_launch(float(request.split('=', 1)[1]))
        start.trigger()
        assert launch.call_count == 1, 'Repeat before launch completion must not duplicate an instance.'

    primary.rebuild_tray_menu()
    next(a for a in primary.tray_menu.actions() if a.text() == 'Stop All Mining').trigger()
    peer.tick()
    assert not primary.enabled and not peer.enabled
    peer.apply_startup([request])
    assert not peer.enabled, 'A child that starts after Stop All must stay stopped.'
    peer.quit()
    primary.quit()
print('PASS: Qt menu and tray group actions, remote start/stop, saved-wallet selection, free-slot routing and late-launch cancellation')
