"""Import SCB's matching matrix; retain semantics and shares, discard Excel layout."""
import gzip
import hashlib
from html.parser import HTMLParser
import io
import json
import math
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request
import zipfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'src/data/matching-map/catalog.json'
PUBLIC = ROOT / 'public/data/matching-map'
SOURCE = 'https://www.scb.se/AM9906'
SUBJECTS = ['Helt', 'Delvis', 'Inte']
LEVELS = ['Rätt', 'För hög', 'För låg']


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        href = dict(attrs).get('href', '')
        if tag == 'a' and 'matchningskarta' in href.lower() and href.lower().endswith('.xlsx'):
            self.links.append(urllib.parse.urljoin(SOURCE, href))


def download(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'KompetensarenaNorrbotten/1.0'})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def sheet_rows(book, name):
    strings = [''.join(s.itertext()) for s in ET.fromstring(book.read('xl/sharedStrings.xml'))]
    sheets = ET.fromstring(book.read('xl/workbook.xml'))
    sheet = next(s for s in sheets.findall('.//{*}sheet') if s.attrib['name'] == name)
    rels = ET.fromstring(book.read('xl/_rels/workbook.xml.rels'))
    target = next(r.attrib['Target'] for r in rels if r.attrib['Id'] == sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'])
    path = target.lstrip('/') if target.startswith('/') else 'xl/' + target
    result = []
    for row in ET.fromstring(book.read(path)).findall('.//{*}sheetData/{*}row'):
        values = {}
        for cell in row:
            column = re.sub(r'\d', '', cell.attrib['r'])
            value = cell.find('{*}v')
            if value is not None:
                values[column] = strings[int(value.text)] if cell.attrib.get('t') == 's' else value.text
            elif cell.find('{*}is') is not None:
                values[column] = ''.join(cell.find('{*}is').itertext())
        result.append(values)
    return result


def share(value):
    if value is None or value.strip() in ('', '.', '..', '...', '…'):
        return None
    number = float(value)
    if not math.isfinite(number) or not 0 <= number <= 1:
        raise ValueError(f'Invalid share: {value}')
    return number  # Keep original precision; never renormalize or round before sorting.


def parse_workbook(data):
    book = zipfile.ZipFile(io.BytesIO(data))
    source_rows = sheet_rows(book, 'Matchningskarta - long format')
    explanation = sheet_rows(book, 'Förklaring')
    notes = [r['A'] for r in explanation if r.get('A')]
    year_text = ' '.join(notes)
    year_match = re.search(r'År (20\d{2})', year_text)
    assessment_match = re.search(r'Trender och [Pp]rognoser (20\d{2})', ' '.join(str(r) for r in source_rows[:10]))
    if not year_match or not assessment_match:
        raise ValueError('Source years missing; inspect SCB workbook before publishing')
    header = next(r for r in source_rows if r.get('G') == 'Bedömning')
    if header.get('E') != 'Andel av yrke per utbildningsgrupp' or header.get('F') != 'Andel av utbildningsgrupp per yrke':
        raise ValueError('Share definitions changed')
    educations, occupations, rows, seen = {}, {}, [], set()
    for r in source_rows:
        if r.get('G') in (None, 'Bedömning'):
            continue
        parent, education, occupation = (r[k].strip() for k in ('B', 'C', 'D'))
        education_code, education_name = education.split(' ', 1)
        parent_code, parent_name = parent.split(' ', 1)
        occupation_code, occupation_name = occupation.split(' ', 1)
        subject, level = r['G'].split(', ')
        if subject not in SUBJECTS or level not in LEVELS:
            raise ValueError(f'Unknown assessment: {r["G"]}')
        e = {'name': education_name, 'group': parent_code, 'groupName': parent_name}
        if education_code in educations and educations[education_code] != e:
            raise ValueError('Conflicting education definitions')
        if occupation_code in occupations and occupations[occupation_code] != occupation_name:
            raise ValueError('Conflicting occupation definitions')
        educations[education_code] = e
        occupations[occupation_code] = occupation_name
        key = education_code, occupation_code
        if key in seen:
            raise ValueError(f'Duplicate combination {key}')
        seen.add(key)
        rows.append([*key, share(r.get('E')), share(r.get('F')), SUBJECTS.index(subject), LEVELS.index(level)])
    if not rows or len(rows) != len(educations) * len(occupations):
        raise ValueError('Incomplete education/occupation matrix')
    # E shares cover occupations within each detailed education. F shares need not total 1.
    for education in educations:
        values = [r[2] for r in rows if r[0] == education]
        if all(v is not None for v in values) and abs(sum(values) - 1) > 1e-8:
            raise ValueError(f'Occupation shares do not sum to one for {education}')
    return {'year': year_match[1], 'assessmentYear': assessment_match[1],
            'educations': educations, 'occupations': occupations, 'notes': notes}, sorted(rows)


def main():
    links = Links()
    links.feed(download(SOURCE).decode('utf-8'))
    urls = list(dict.fromkeys(links.links))
    if len(urls) != 1 or urllib.parse.urlparse(urls[0]).hostname not in ('www.scb.se', 'scb.se'):
        raise ValueError('Expected exactly one SCB matching workbook link')
    data = download(urls[0])
    digest = hashlib.sha256(data).hexdigest()
    old = json.loads(CATALOG.read_text()) if CATALOG.exists() else {}
    if old.get('sourceHash') == digest and old.get('workbook') == urls[0] and os.environ.get('FORCE_REFRESH') != 'true':
        print('SCB matching map unchanged')
        return
    metadata, rows = parse_workbook(data)
    payload = json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode()
    payload_hash = hashlib.sha256(payload).hexdigest()
    filename = f'matrix-{payload_hash[:16]}.json'
    import base64
    wrapped = json.dumps({'gzip': base64.b64encode(gzip.compress(payload, mtime=0)).decode()}, separators=(',', ':'))
    catalog = {**metadata, 'source': SOURCE, 'workbook': urls[0], 'sourceHash': digest,
               'matrixHash': payload_hash, 'file': filename, 'rowCount': len(rows), 'geography': 'Riket'}
    PUBLIC.mkdir(parents=True, exist_ok=True)
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    (PUBLIC / filename).write_text(wrapped)
    # Publish pointers only after the complete workbook has passed validation.
    temporary = CATALOG.with_suffix('.tmp')
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(CATALOG)
    for path in PUBLIC.glob('matrix-*.json'):
        if path.name != filename:
            path.unlink()
    print(f'Validated {len(rows)} combinations, {len(metadata["educations"])} educations, {len(metadata["occupations"])} occupations; year {metadata["year"]}')


if __name__ == '__main__':
    main()
