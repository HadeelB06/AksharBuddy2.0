"""Conservative deterministic checks, not a proof of semantic equivalence."""
import re
import unicodedata
from collections import Counter

def normalized(text):
    return ''.join(str(unicodedata.digit(c)) if c.isdecimal() else c
                   for c in unicodedata.normalize('NFKC', text)).casefold()

def critical_values(text):
    # Preserve decimal separators, dates, times, percentages and attached units.
    value = normalized(text)
    return Counter(re.sub(r'\s+', '', m.group()) for m in re.finditer(
        r'(?:[$₹€£]\s*)?\d+(?:[.,:/-]\d+)*(?:\s*(?:%|percent\b|per cent\b|टक्के|प्रतिशत|kg\b|mg\b|ml\b|km\b|am\b|pm\b|°[cf]))?', value))

def validate(original, candidate, language):
    source, target = normalized(original), normalized(candidate)
    if critical_values(original) != critical_values(candidate):
        raise ValueError('The model changed a number, date, time or unit. Your original is preserved.')
    if source == target:
        return
    negatives = {'en': ['not','never','without','no','unless','cannot',"can't","don't",'must','before','after'],
                 'hi': ['नहीं','न','मत','बिना'], 'mr': ['नाही','नको','नयेत','नये','नका','नसल्यास']}[language]
    tokens = lambda t: re.split(r'[\s,.;:!?।()]+', t)
    for word in negatives:
        if tokens(source).count(word) != tokens(target).count(word):
            raise ValueError('The model changed an instruction. Your original is preserved.')
    # Names/acronyms written in Latin script must survive unchanged.
    names = set(re.findall(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b|\b[A-Z]{2,}\b', original))
    names.update(set(re.findall(r'\b[A-Z][a-z]+\b', original)) -
                 {'The','A','An','If','Although','Because','Before','After','Please','Do','Take','Read','Pay','Contact','Submit','Keep','Use','This','That','These','Those','You','It','He','She','They','We','I'})
    if any(name not in candidate for name in names):
        raise ValueError('The model changed a name or abbreviation. Your original is preserved.')
    date_words = 'january february march april may june july august september october november december monday tuesday wednesday thursday friday saturday sunday जनवरी फरवरी मार्च अप्रैल मई जून जुलाई अगस्त सितंबर अक्टूबर नवंबर दिसंबर सोमवार मंगलवार बुधवार गुरुवार शुक्रवार शनिवार रविवार जानेवारी फेब्रुवारी एप्रिल मे ऑगस्ट सप्टेंबर नोव्हेंबर डिसेंबर'.split()
    for word in date_words:
        if tokens(source).count(word) != tokens(target).count(word):
            raise ValueError('The model changed a calendar detail. Your original is preserved.')
    if language == 'en':
        if re.search(r'[\u0900-\u097f]', candidate):
            raise ValueError('The model changed the language. Your original is preserved.')
    else:
        # Hindi and Marathi share a script: script checks alone cannot distinguish them.
        # Require positive grammatical evidence; uncertain rewrites are rejected.
        hints = {'hi': {'है','हैं','हूँ','करें','चाहिए','कृपया','लिए','होगा','गया'},
                 'mr': {'आहे','आहेत','होते','करा','पाहिजे','कृपया','साठी','होईल','नाही'}}
        selected = hints[language] - hints['mr' if language == 'hi' else 'hi']
        other = hints['mr' if language == 'hi' else 'hi'] - hints[language]
        words = set(tokens(target))
        if not words.intersection(selected) or words.intersection(other):
            raise ValueError('The output language could not be confirmed. Your original is preserved.')
