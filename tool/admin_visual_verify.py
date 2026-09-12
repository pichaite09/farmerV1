"""Rendered Chromium verification of the explicitly synthetic harness."""
import json
import os
from pathlib import Path
from playwright.sync_api import sync_playwright

out = Path(os.getenv('ADMIN_EVIDENCE', '/tmp/farmer-admin-evidence')); out.mkdir(exist_ok=True)
url = os.getenv('ADMIN_VISUAL_URL', 'http://127.0.0.1:8765/')
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=['--no-sandbox'])
    errors, requests = [], []
    for width in [1440, 390]:
        page = browser.new_page(viewport={'width':width,'height':1000}, device_scale_factor=1)
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('response', lambda r: requests.append({'url':r.url,'status':r.status}))
        page.goto(url, wait_until='networkidle')
        page.locator('flt-semantics-placeholder').wait_for(state='attached', timeout=60000)
        page.locator('flt-semantics-placeholder').evaluate_all('(els)=>els.forEach(e=>e.click())')
        page.get_by_text('ภาพรวมระบบ', exact=True).wait_for(timeout=60000)
        page.wait_for_timeout(1500)
        prefix = 'desktop' if width == 1440 else 'mobile'
        page.screenshot(path=str(out/f'{prefix}-overview.png'))
        if width == 390:
            page.mouse.click(117, 954)
        else:
            page.get_by_text('ข้อมูลเกษตร', exact=True).first.click()
        page.get_by_text('ปลูกข้าวฤดูฝน', exact=False).first.wait_for()
        page.wait_for_timeout(500)
        page.screenshot(path=str(out/f'{prefix}-records.png'))
        page.get_by_text('ปลูกข้าวฤดูฝน', exact=False).first.click(force=True)
        page.get_by_text('รายละเอียดข้อมูล', exact=True).wait_for()
        page.wait_for_timeout(500)
        page.screenshot(path=str(out/f'{prefix}-detail.png'))
        page.get_by_text('ปิด', exact=True).click()
        page.get_by_text('รายละเอียดข้อมูล', exact=True).wait_for(state='hidden')
        # Flutter's modal barrier remains during the closing animation.
        page.wait_for_timeout(500)
        if width == 390:
            page.mouse.click(195, 954)
        else:
            page.get_by_text('ผู้ใช้งาน', exact=True).first.click()
        page.get_by_role('textbox').first.wait_for()
        page.wait_for_timeout(500)
        page.screenshot(path=str(out/f'{prefix}-users.png'))
        (out/f'{prefix}-dom.txt').write_text(page.locator('body').inner_text())
        page.close()
    (out/'network.json').write_text(json.dumps({'errors':errors,'responses':requests},indent=2))
    assert not errors, errors
    fonts = [r for r in requests if 'MaterialIcons-Regular.otf' in r['url']]
    assert len(fonts) == 2 and all('/releases/' in r['url'] and r['status'] == 200 for r in fonts), fonts
    assert all(r['status'] < 400 for r in requests), requests
    print(json.dumps({'screenshots':len(list(out.glob('*.png'))),'pageErrors':errors,'fontRequests':fonts},indent=2))
    browser.close()
