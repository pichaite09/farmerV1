from pathlib import Path
import shutil
import subprocess

import pytest


WORKER = Path(__file__).parents[2] / 'web' / 'push_service_worker.js'
HARNESS = Path(__file__).with_name('push_service_worker_harness.js')


def test_service_worker_deduplicates_notifications_durably_and_preserves_click_url():
    if not WORKER.is_file():
        pytest.skip('Web service worker is tested in the Web artifact job')
    source = WORKER.read_text()

    assert 'indexedDB.open' in source
    assert "createObjectStore('notifications'" in source
    assert 'notificationId' in source
    push_handler = source.split('});\n\nfunction openNotificationDb', 1)[0]
    show_index = push_handler.index('showNotification(title, options)')
    assert 'store.put(' not in push_handler
    assert 'await markNotificationShown' in push_handler
    assert show_index < push_handler.index('await markNotificationShown')
    assert 'try {' in push_handler
    assert 'catch (_) {' in push_handler
    assert 'data: { url, notificationId }' in source
    assert 'event.notification.data && event.notification.data.url' in source


def test_service_worker_serializes_concurrent_duplicate_pushes():
    if shutil.which('node') is None or not HARNESS.is_file():
        pytest.skip('Web service-worker harness runs in the Web artifact job')
    result = subprocess.run(
        ['node', str(HARNESS)],
        cwd=WORKER.parents[1],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr or result.stdout