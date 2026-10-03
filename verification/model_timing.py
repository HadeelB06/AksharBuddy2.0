from pathlib import Path
import sys,time,json
R=Path(__file__).resolve().parent
before='--before' in sys.argv
workspace=R.parents[1]
backend=(workspace/'hadeel_major project' if before else R.parent)/'AksharBuddy/backend'
sys.path.insert(0,str(backend));sys.path.append(str(workspace/'hadeel-model-runtime'))
from modules import local_model as model
measure={}
load=model._load
def timed_load():
    start=time.perf_counter()
    try:return load()
    finally:measure['load_or_reuse']=round(time.perf_counter()-start,3)
model._load=timed_load
cases=[('en','Nina has 12 books. Do not move the blue box.'),
       ('hi','रीमा के पास 12 किताबें हैं। किताबें बाहर मत ले जाएं।'),
       ('mr','रीमाकडे 12 पुस्तके आहेत. पुस्तके बाहेर नेऊ नका.')]
results=[]
quality='--quality' in sys.argv
if quality:
    cases=[(r['language'],r['input']) for r in json.loads((R/'heldout.json').read_text(encoding='utf-8'))]
for language,text in (cases if quality else cases*2):
    start=time.perf_counter();output='';error=None
    try:output=model.process_text(text,language)
    except Exception as exc:error=str(exc)
    elapsed=round(time.perf_counter()-start,3)
    row=dict(language=language,input=text,output=output,error=error,seconds=elapsed,
             model_load_seconds=measure.get('load_or_reuse'),
             inference_and_validation_seconds=round(elapsed-measure.get('load_or_reuse',0),3),
             changed=output.strip()!=text.strip() if output else False)
    results.append(row)
    (R/('model-quality.json' if quality else 'model-before.json' if before else 'model-after.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print({k:v for k,v in row.items() if k not in ('input','output')},flush=True)
