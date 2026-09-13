"""Sanitized read-only historical-announcement snapshot on the deployment host.

Before activation: snapshot all announcement data. After activation: restrict to
historical campaigns/notices, so legitimate new announcements do not affect the
comparison. Hashes include every historical outbox column, not only sent counts.
"""
import json
import subprocess
import sys

historical = '--historical' in sys.argv
cutoff = '(SELECT activated_at FROM announcement_delivery_policy WHERE singleton)'
where = f'WHERE a.created_at < {cutoff}' if historical else ''
notice_where = f'AND (a.created_at < {cutoff} OR n.created_at < {cutoff})' if historical else ''
queries = {
    'announcements': f'SELECT a.* FROM announcements a {where}',
    'recipients': f'SELECT r.* FROM announcement_recipients r JOIN announcements a ON a.id=r.announcement_id {where}',
    'notifications': f"SELECT n.* FROM notifications n LEFT JOIN announcements a ON a.id=n.announcement_id WHERE (n.kind='admin_announcement' OR n.announcement_id IS NOT NULL) {notice_where}",
    'outbox': f"SELECT o.* FROM push_outbox o JOIN notifications n ON n.id=o.notification_id LEFT JOIN announcements a ON a.id=n.announcement_id WHERE (n.kind='admin_announcement' OR n.announcement_id IS NOT NULL) {notice_where}",
}
result = {}
for name, query in queries.items():
    sql = f"SELECT json_build_object('count',count(*),'digest',md5(COALESCE(string_agg(to_jsonb(x)::text, '' ORDER BY id),''))) FROM ({query}) x"
    raw = subprocess.check_output(['docker','exec','farmer-main-postgres-1','psql','-U','farmer_main','-d','farmer_main','-At','-c',sql], text=True)
    result[name] = json.loads(raw)
print(json.dumps(result, sort_keys=True))
