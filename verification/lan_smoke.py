"""Actual HTTP on the laptop LAN address; not a physical-phone test."""
from pathlib import Path
import sys,time,json,threading
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R.parent/'AksharBuddy/backend'))
import requests
from werkzeug.serving import make_server
from app import app
server=make_server('0.0.0.0',0,app,threaded=True)
thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
base=f'http://192.168.29.68:{server.server_port}'
session=requests.Session();session.trust_env=False
report={'base':base,'scope':'Laptop HTTP stack via LAN IPv4; physical phone and router not tested'}
try:
    health=session.get(base+'/health',timeout=10);health.raise_for_status()
    assert health.json()['version']=='lan-repair-1'
    report['health']=health.json()
    start=time.perf_counter()
    with (R/'fixtures/scanned.pdf').open('rb') as f:
        upload=session.post(base+'/api/extraction-jobs',files={'file':('scanned.pdf',f)},data={'language':'en'},timeout=15)
    assert upload.status_code==202,upload.text
    report['upload_and_enqueue_seconds']=round(time.perf_counter()-start,3)
    url=base+'/api/extraction-jobs/'+upload.json()['jobId'];stages=[]
    for _ in range(300):
        response=session.get(url,timeout=5);response.raise_for_status();job=response.json()
        stage={k:job[k] for k in ['stage','page','pages','completedPages'] if k in job}
        if not stages or stages[-1]!=stage:stages.append(stage)
        if job['state']!='working':break
        time.sleep(.1)
    assert job['state']=='complete',job
    assert '12 books' in job['result']['originalText']
    assert job['result']['fontSize']>0
    report.update(total_seconds=round(time.perf_counter()-start,3),stages=stages,timings=job['result']['timings'])
    report['passed']=True
finally:
    server.shutdown();server.server_close()
    (R/'lan-smoke.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
