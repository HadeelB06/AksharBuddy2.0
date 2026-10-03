from pathlib import Path
import io,json,time,sys
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R.parent/'AksharBuddy/backend'))
from app import app
from modules.performance import trace
from unittest.mock import patch
results=[]
for name in ['tiny.png','tiny.png','normal.png','digital.pdf','scanned.pdf']:
    measure={}; token=trace.set(measure)
    data=(R/'fixtures'/name).read_bytes();start=time.perf_counter()
    with patch('modules.local_model.process_text',side_effect=AssertionError('Keep my words called AI')), app.test_client() as client:
        response=client.post('/api/format-text?language=en',data={'file':(io.BytesIO(data),name)},content_type='multipart/form-data')
    trace.reset(token)
    payload=response.get_json()
    row=dict(file=name,status=response.status_code,seconds=round(time.perf_counter()-start,3),stages=measure,bytes=len(data),text=payload.get('originalText',''),transport='Flask test client; excludes Wi-Fi transfer',model_inference=False)
    results.append(row)
    (R/'after-timings.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print({k:v for k,v in row.items() if k!='text'},flush=True)
