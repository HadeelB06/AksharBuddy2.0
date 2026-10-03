from pathlib import Path
import io,json,time,sys,functools
R=Path(__file__).resolve().parent; sys.dont_write_bytecode=True
sys.path.insert(0,str(R.parents[1]/'hadeel_major project/AksharBuddy/backend'))
from PIL import Image,ImageDraw,ImageFont
import pymupdf
F=R/'fixtures';F.mkdir(exist_ok=True)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',32)
for name,size,lines in [('tiny',(760,180),['Nina has 12 books.','Do not move the blue box.']),('normal',(1400,1900),['Reading practice','Nina has 12 books. Do not move the blue box.','The office opens at 10 AM and closes at 6 PM.']*7)]:
 im=Image.new('RGB',size,'white');d=ImageDraw.Draw(im)
 for i,line in enumerate(lines):d.text((25,20+65*i),line,fill='black',font=font)
 im.save(F/(name+'.png'))
for name,scanned,count in [('digital',False,3),('scanned',True,3)]:
 doc=pymupdf.open()
 for i in range(count):
  p=doc.new_page()
  if scanned:p.insert_image(p.rect,filename=str(F/'normal.png'))
  else:p.insert_text((40,70),f'Page {i+1}. Nina has 12 books. Do not move the blue box. The office opens at 10 AM.',fontsize=14)
 doc.save(F/(name+'.pdf'));doc.close()
from app import app
import modules.ocr as ocr
measure={}
def wrap(name):
 original=getattr(ocr,name)
 @functools.wraps(original)
 def timed(*a,**kw):
  t=time.perf_counter()
  try:return original(*a,**kw)
  finally:measure[name]=measure.get(name,0)+time.perf_counter()-t
 setattr(ocr,name,timed)
for name in ['_get_reader','_deskew_image','_detect_table_grid','_tesseract_detections','preprocess_image','_easyocr_detections']:wrap(name)
# Measure recognition separately from the one-time initialization.
old=ocr._get_reader
def get_reader():
 r=old()
 if r is not None and not getattr(r,'_profile_wrapped',False):
  fn=r.readtext
  def read(*a,**kw):
   t=time.perf_counter()
   try:return fn(*a,**kw)
   finally:measure['easyocr_recognition']=measure.get('easyocr_recognition',0)+time.perf_counter()-t
  r.readtext=read;r._profile_wrapped=True
 return r
ocr._get_reader=get_reader
results=[]
for name in ['tiny.png','tiny.png','normal.png','digital.pdf','scanned.pdf']:
 measure={};data=(F/name).read_bytes();t=time.perf_counter()
 with app.test_client() as c:response=c.post('/api/format-text?language=en',data={'file':(io.BytesIO(data),name)},content_type='multipart/form-data')
 payload=response.get_json();row={'file':name,'status':response.status_code,'seconds':round(time.perf_counter()-t,3),'stages':{k:round(v,3) for k,v in measure.items()},'bytes':len(data),'text':payload.get('originalText',''),'transport':'Flask test client; excludes Wi-Fi transfer','model_inference':False}
 results.append(row);(R/'before-timings.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print({k:v for k,v in row.items() if k!='text'},flush=True)
