import io
import time
import unittest
from unittest.mock import patch
from PIL import Image
import pymupdf
from werkzeug.datastructures import FileStorage
from app import app
from input_processing.pdf_processor import process_pdf
from modules.output_guard import validate

class RepairTests(unittest.TestCase):
    def test_health_identifies_repair(self):
        self.assertEqual(app.test_client().get('/health').json['version'], 'lan-repair-1')

    def test_changed_details_rejected(self):
        cases = [('Pay 20%.', 'Pay 20.'), ('Come at 10:30.', 'Come at 10:40.'),
                 ('Due 12/03/2026.', 'Due 03/12/2026.'), ('Take 5 mg.', 'Take 5 kg.'),
                 ('Do not enter.', 'Do enter.'), ('Contact Nina Patel.', 'Contact Mira Patel.'),
                 ('Nina has 12 books.', 'Mira has 12 books.'), ('Due 12 May.', 'Due 12 June.')]
        for original, candidate in cases:
            with self.subTest(original=original), self.assertRaises(ValueError):
                validate(original, candidate, 'en')

    def test_shared_script_language_switch_rejected(self):
        for original, candidate, language in [('यह ठीक है।','हे ठीक आहे।','hi'),
                                                ('हे ठीक आहे।','यह ठीक है।','mr')]:
            with self.assertRaises(ValueError): validate(original,candidate,language)

    def test_safe_values_preserved(self):
        validate('The charge is 20%.', 'Pay 20%.', 'en')

    def test_short_digital_pdf_never_ocr(self):
        doc=pymupdf.open(); page=doc.new_page(); page.insert_text((50,50),'12 books')
        data=doc.tobytes();doc.close()
        with patch('input_processing.pdf_processor.extract_text_from_pil',side_effect=AssertionError('native PDF OCR')):
            result=process_pdf(FileStorage(io.BytesIO(data),filename='short.pdf'))
        self.assertEqual(result['extractedText'], '12 books')

    def test_async_extraction_never_loads_model(self):
        content=io.BytesIO(); Image.new('RGB',(200,100),'white').save(content,format='PNG')
        with patch('modules.local_model._load',side_effect=AssertionError('AI loaded')), \
             patch('input_processing.image_processor.extract_document_from_bytes',return_value={'text':'Nina has 12 books.', 'structure':None}):
            client=app.test_client()
            response=client.post('/api/extraction-jobs',data={'file':(io.BytesIO(content.getvalue()),'test.png')})
            self.assertEqual(response.status_code,202)
            key=response.json['jobId']
            for _ in range(100):
                job=client.get('/api/extraction-jobs/'+key).json
                if job['state'] != 'working':break
                time.sleep(.02)
            self.assertEqual(job['state'],'complete',job)
            self.assertEqual(job['result']['originalText'],'Nina has 12 books.')

if __name__=='__main__':unittest.main()
