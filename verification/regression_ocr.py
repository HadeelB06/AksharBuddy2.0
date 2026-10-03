from pathlib import Path
import sys,json,io,time,re,unicodedata
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R.parent/'AksharBuddy/backend'))
from app import app
old=R.parents[1]/'hadeel_major project/verification/ocr-final'
def normalize(t):
    t=unicodedata.normalize('NFC',t).casefold()
    return ''.join(c if unicodedata.category(c)[0] in 'LNM' else ' ' for c in t).split()
def distance(a,b):
    row=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        new=[i]
        for j,y in enumerate(b,1):new.append(min(new[-1]+1,row[j]+1,row[j-1]+(x!=y)))
        row=new
    return row[-1]
results=[]
for prior in json.loads((old/'results.json').read_text(encoding='utf-8')):
    name=prior['name']; extension='.pdf' if name.endswith('pdf') else '.png'
    path=old/(name+extension)
    if name=='en-real-handwriting':path=old/'handwritten_text.jpg'
    start=time.perf_counter()
    with app.test_client() as c:
        response=c.post('/api/format-text',data={'language':prior['language'],'file':(io.BytesIO(path.read_bytes()),path.name)})
    actual=response.json.get('originalText',''); a=normalize(prior['expected']); b=normalize(actual)
    result=dict(name=name,language=prior['language'],seconds=round(time.perf_counter()-start,3),status=response.status_code,wer=round(distance(a,b)/max(1,len(a)),4),previousWER=prior['word_error_rate'],actual=actual)
    results.append(result);(R/'ocr-regression.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print({k:v for k,v in result.items() if k!='actual'},flush=True)
