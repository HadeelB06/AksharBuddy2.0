import unittest
from unittest.mock import patch
from app import app
from modules.local_model import _validate_output, process_structured_content

class LocalModelContractTests(unittest.TestCase):
    def setUp(self): self.client = app.test_client()
    def test_invalid_language_and_input(self):
        for data in [[],{}, {'text':False},{'text':'Hello','language':'de'}]:
            self.assertEqual(self.client.post('/api/simplify-text',json=data).status_code,400)
    def test_unchanged_output_is_not_a_quality_pass(self):
        with patch('routes.simplify_text_routes.local_simplify',return_value='Read this.'):
            result=self.client.post('/api/simplify-text',json={'text':'Read this.','language':'en'})
            self.assertEqual(result.status_code,200)
            self.assertFalse(result.json['changed'])
            self.assertEqual(result.json['provider'],'local-indicbart')
    def test_model_failure_does_not_silently_return_original(self):
        with patch('routes.simplify_text_routes.local_simplify',side_effect=RuntimeError('secret')):
            result=self.client.post('/api/simplify-text',json={'text':'Read this.'})
            self.assertEqual(result.status_code,503)
            self.assertNotIn('secret',result.text)
    def test_legacy_endpoint_shares_validation_and_errors(self):
        self.assertEqual(self.client.post('/process/text-format',json={'text':42}).status_code,400)
        with patch('routes.simplify_text_routes.local_simplify',side_effect=RuntimeError('private')):
            result=self.client.post('/process/text-format',json={'text':'Hello'})
            self.assertEqual(result.status_code,503)
            self.assertNotIn('private',result.text)
    def test_numbers_and_negation_are_guarded(self):
        for original,output,lang in [('Take 2 tablets','Take 3 tablets','en'),('Do not enter','Do enter','en'),('मत जाओ','जाओ','hi'),('जाऊ नका नाही','जाऊ नका','mr')]:
            with self.subTest(lang=lang),self.assertRaises(ValueError): _validate_output(original,output,lang)
    def test_tables_are_not_rewritten(self):
        structure={'type':'document','blocks':[{'type':'table','headers':['Price'],'rows':[['20']]}]}
        with patch('modules.local_model.process_text') as generate:
            self.assertEqual(process_structured_content(structure,'en'),structure)
            generate.assert_not_called()
    def test_word_definition_limitation_is_explicit(self):
        for lang in ('en','hi','mr'):
            result=self.client.post('/api/word-help',json={'word':'read','language':lang})
            self.assertEqual(result.status_code,422)
            self.assertIn('Saved meanings',result.json['error'])

if __name__=='__main__': unittest.main()
