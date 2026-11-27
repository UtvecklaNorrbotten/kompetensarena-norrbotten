"""Read MUCF's public Drupal form; never infer suppressed cells or totals."""
import itertools
import json
import re
import threading
import time
import unicodedata
from decimal import Decimal, InvalidOperation

import requests
from bs4 import BeautifulSoup

URL = 'https://www.mucf.se/rapporter-och-statistik/statistik-om-unga-som-varken-arbetar-eller-studerar'
UNG = 'https://ungidag.se/indikator/arbete_och_boende/varken-arbetar-eller-studerar-uvas'
PREFIX = 'filters[columns]'
AGES = ['16-24', '25-29', '16-29']
GENDERS = ['Kvinnor', 'Män']
ORIGINS = ['Inrikesfödd', 'Utrikesfödd']
PROFILES = [(False, False), (True, False), (False, True), (True, True)]


def soup(html):
    return BeautifulSoup(html, 'html.parser')


def options(page, suffix):
    field = page.find('select', attrs={'name': f'{PREFIX}{suffix}'})
    if field is None:
        raise ValueError(f'MUCF saknar urvalsfält: {suffix}')
    return {o['value']: o.get_text(' ', strip=True) for o in field.select('option')}


def parse_value(raw, percent=False):
    """Keep the exact source token next to a typed value and explicit status."""
    compact = re.sub(r'\s', '', raw)
    if compact in {'.', '..', '...', '…', '*', '**', '***'}:
        return [None, 'suppressed', raw]
    if compact == '':
        return [None, 'missing', raw]
    if percent:
        if not compact.endswith('%'):
            raise ValueError(f'Andel saknar procenttecken: {raw!r}')
        compact = compact[:-1]
    elif '%' in compact:
        raise ValueError('Procenttecken i antal')
    if not re.fullmatch(r'\d+(?:[,.]\d+)?', compact):
        raise ValueError(f'Okänt MUCF-värde: {raw!r}')
    try:
        number = Decimal(compact.replace(',', '.'))
    except InvalidOperation:
        raise ValueError('Ogiltigt MUCF-tal') from None
    if percent:
        if not 0 <= number <= 100:
            # MUCF publishes a few impossible shares (>100 %) for small older groups.
            # Keep the source token, publish no value and flag it instead of aborting the whole run.
            return [None, 'invalid_source', raw]
        return [float(number), 'observed', raw]
    if number != number.to_integral_value():
        raise ValueError('Antal är inte heltal')
    return [int(number), 'observed', raw]


def parse_table(page, year, geo, geo_label, category, category_label, gender, origin):
    table = page.select_one('#results-wrapper table')
    if table is None:
        raise ValueError('MUCF saknar resultattabell')
    headers = table.select('thead tr')
    title = headers[0].get_text(' ', strip=True)
    expected_prefix = f'{year}, ' + ('' if geo == '00' else f'{geo_label}, ')
    # MUCF uses inconsistent capitalization for names beginning with Å/Ä/Ö
    # between the select options and result headings. Preserve diacritics and
    # compare the full year/geography prefix; category validation stays exact.
    normalized_title = unicodedata.normalize('NFC', title).casefold()
    normalized_prefix = unicodedata.normalize('NFC', expected_prefix).casefold()
    if not normalized_title.startswith(normalized_prefix) or title.split(', ')[-1] != category_label:
        raise ValueError(f'MUCF returnerade fel urval: {title}')
    ages = [x.get_text(strip=True) for x in headers[1].select('em')]
    if ages != AGES:
        raise ValueError(f'MUCF har ändrat åldersgrupper: {ages}')
    if [x.get_text(strip=True) for x in headers[2].select('th')][1:] != ['Antal', 'Andel'] * 3:
        raise ValueError('MUCF har ändrat mått eller kolumnordning')
    expected = {
        ' '.join(x for x in (sex, born) if x != 'Totalt') or 'Alla': (sex, born)
        for sex, born in itertools.product(GENDERS if gender else ['Totalt'],
                                           ORIGINS if origin else ['Totalt'])
    }
    rows, seen = [], set()
    for tr in table.select('tbody tr'):
        cells = [x.get_text(' ', strip=True) for x in tr.select('td')]
        if len(cells) != 7 or cells[0] not in expected or cells[0] in seen:
            raise ValueError('MUCF-svaret har oväntade eller dubblerade rader')
        seen.add(cells[0])
        sex, born = expected[cells[0]]
        for i, age in enumerate(ages):
            rows.append([geo, age, sex, born, category,
                         *parse_value(cells[1 + i * 2]),
                         *parse_value(cells[2 + i * 2], percent=True)])
    if seen != set(expected):
        raise ValueError('MUCF-svaret saknar delgrupper')
    return rows


class RateLimit:
    """One shared pacing limit for all source workers (at most one start/second)."""
    def __init__(self):
        self.lock = threading.Lock()
        self.next_request = 0

    def wait(self):
        with self.lock:
            time.sleep(max(0, self.next_request - time.monotonic()))
            self.next_request = time.monotonic() + 1


LIMIT = RateLimit()


class Source:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers['User-Agent'] = 'KompetensarenaNorrbotten-MUCF/1.0'
        self.hidden = None
        self.requests = 0

    def request(self, url, data=None):
        for attempt in range(5):
            LIMIT.wait()
            try:
                r = self.session.request('GET' if data is None else 'POST', url,
                                         data=data, timeout=(15, 90))
                if r.status_code == 429 or r.status_code >= 500:
                    r.raise_for_status()
                r.raise_for_status()
                return r
            except (requests.Timeout, requests.ConnectionError, requests.HTTPError):
                if attempt == 4 or ('r' in locals() and 400 <= r.status_code < 500 and r.status_code != 429):
                    raise RuntimeError('MUCF-anrop misslyckades efter återförsök') from None
                time.sleep(min(30, 2 ** (attempt + 1)))

    def bootstrap(self):
        page = soup(self.request(URL).text)
        form = page.select_one('form.mucf-uvas-stats-search-form')
        if form is None:
            raise ValueError('MUCF:s statistikformulär saknas')
        self.hidden = {x['name']: x.get('value', '') for x in form.select('input[type=hidden]')}
        self.requests = 0
        return page

    def query(self, year, county='all', city='all', category='Master', gender=False, origin=False):
        if self.hidden is None or self.requests >= 100:
            self.bootstrap()
        payload = {**self.hidden, f'{PREFIX}[column_1][year]': str(year),
                   f'{PREFIX}[column_1][county]': county,
                   f'{PREFIX}[column_1][city]': city,
                   f'{PREFIX}[column_3][general_category]': category,
                   'op': 'Välj', '_triggering_element_name': 'op',
                   '_triggering_element_value': 'Välj', '_drupal_ajax': '1'}
        for name, values, enabled in [('gender', GENDERS, gender), ('origin', ORIGINS, origin)]:
            if enabled:
                for value in values:
                    payload[f'{PREFIX}[column_2][{name}][{value}]'] = value
        response = self.request(URL + '?ajax_form=1&_wrapper_format=drupal_ajax', payload)
        self.requests += 1
        commands = response.json()
        inserts = [x['data'] for x in commands if x.get('command') == 'insert' and '#results-wrapper' in x.get('data', '')]
        if len(inserts) != 1:
            # The fragment contains id="results-wrapper", not a CSS selector.
            inserts = [x['data'] for x in commands if x.get('command') == 'insert' and 'id="results-wrapper"' in x.get('data', '')]
        if len(inserts) != 1:
            raise ValueError('MUCF:s AJAX-svar har ändrat struktur')
        return soup(inserts[0])

    def geography(self):
        """SCB codes and official names from MUCF's own Ung idag index."""
        page = self.request(UNG).text
        url = re.search(r'mucf.codes\s*=\s*"([^"]+)"', page)
        xid = re.search(r'mucf.xid\s*=\s*"([^"]+)"', page)
        if not url or not xid or not url[1].startswith('https://ungidag.se/api/client/'):
            raise ValueError('Ung idag saknar geografikatalog')
        data = self.request(url[1] + '?XID=' + xid[1]).json()
        codes, names = data['regionskod'], data['regionsnamn']
        if len(codes) != len(names) or len(set(codes)) != len(codes):
            raise ValueError('Felaktig geografikatalog')
        return dict(zip(codes, names))


def name_key(name):
    return re.sub(r'\s+', ' ', name.lower().replace(' län', '').strip())


def discover(source, year, regions):
    page = source.query(year)
    county_options = options(page, '[column_1][county]')
    categories = options(page, '[column_3][general_category]')
    def code(label, length):
        matches = [c for c, n in regions.items() if len(c) == length and name_key(n) == name_key(label)]
        if len(matches) != 1:
            raise ValueError(f'Ingen entydig MUCF-geografikod för {label}')
        return matches[0]
    geos = [{'code': '00', 'label': 'Alla', 'county': 'all', 'city': 'all', 'categories': categories}]
    for county, label in county_options.items():
        if county == 'all':
            continue
        county_page = source.query(year, county)
        geos.append({'code': code(label, 2), 'label': label, 'county': county,
                     'city': 'all', 'categories': options(county_page, '[column_3][general_category]')})
        cities = options(county_page, '[column_1][city]')
        municipal_categories = None
        for city, city_label in cities.items():
            if city == 'all':
                continue
            # Municipalities expose only total and unknown activity; verify the
            # actual options on one municipality in each county and year.
            if municipal_categories is None:
                city_page = source.query(year, county, city)
                municipal_categories = options(city_page, '[column_3][general_category]')
            geos.append({'code': code(city_label, 4), 'label': city_label, 'county': county,
                         'city': city, 'categories': municipal_categories})
    if len({g['code'] for g in geos}) != len(geos) or len(geos) != len(regions):
        raise ValueError('MUCF-formuläret och Ung idag har olika geografisk täckning')
    return sorted(geos, key=lambda g: (not g['code'].startswith('25'), len(g['code']), g['code']))


def queries(geos):
    for geo in geos:
        for category, label in geo['categories'].items():
            # Origin selections hide/reset activity categories in MUCF's form.
            for gender, origin in PROFILES if category == 'Master' else PROFILES[:2]:
                key = ':'.join([geo['code'], category, str(int(gender)), str(int(origin))])
                yield key, geo, category, label, gender, origin
