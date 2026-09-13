import subprocess
import sys
script = '''import os,sys
from app.database import engine
from sqlalchemy import text
assert engine.url.database=='farmer_main_test' and engine.url.host=='postgres'
with engine.connect() as c:
 assert c.execute(text('select current_database()')).scalar()=='farmer_main_test'
 print('verified isolated DB', flush=True)
os.environ['ALLOW_DESTRUCTIVE_TEST_DB']='1'
import pytest
sys.exit(pytest.main(ARGS))
'''.replace('ARGS', repr(sys.argv[1:] or ['tests', '-q', '--tb=short', '-p', 'no:cacheprovider']))
r = subprocess.run(['ssh','farmer-main-213','docker','exec','-i','-e','PYTHONPATH=/app','farmer-main-staging-api-1','python','-'], input=script, text=True)
sys.exit(r.returncode)
