import unittest
from app import app

class WordHelpTests(unittest.TestCase):
    def test_invalid_request_rejected(self):
        for data in [[], {}, {'word': False}, {'word':'read','language':'de'}]:
            self.assertEqual(app.test_client().post('/api/word-help',json=data).status_code,400)
    def test_no_fabricated_dictionary_response(self):
        result=app.test_client().post('/api/word-help',json={'word':'read','language':'en'})
        self.assertEqual(result.status_code,422)
        self.assertNotIn('definition',result.json)
