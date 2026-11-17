"""Synthetic examples only. Production comparison runs separately in Actions."""
import io
import json
import sys
import unittest
import urllib.error
import zipfile
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from company_accounts.bolagsverket_api import Client, ApiError, NoRedirect, normalize_documents, newest
from company_accounts.compare_api import inspect


def document(identifier='synthetic-a',period='2025-12-31',registered='2026-06-01'):
    return dict(dokumentId=identifier,rapporteringsperiodTom=period,registreringstidpunkt=registered)


class Metadata(unittest.TestCase):
    def test_empty_is_distinct_from_unexpected_schema(self):
        self.assertEqual(normalize_documents({'dokument':[]}),[])
        for data in ({},[],{'dokument':None},{'dokument':[{}]}):
            with self.assertRaises(ApiError):normalize_documents(data)

    def test_latest_period_before_registration(self):
        old=document('old','2024-12-31','2026-07-01')
        new=document('new','2025-12-31','2026-06-01')
        self.assertIs(newest([old,new]),new)

    def test_date_only_registration_and_same_day_conflict(self):
        first=document('first',registered='2026-06-01')
        corrected=document('corrected',registered='2026-06-02')
        self.assertIs(newest([first,corrected]),corrected)
        with self.assertRaises(ApiError):newest([first,document('conflict')])

    def test_timezone_ordering_not_lexical(self):
        first=document('first',registered='2026-06-01T12:00:00+02:00')
        corrected=document('corrected',registered='2026-06-01T11:00:00Z')
        self.assertIs(newest([first,corrected]),corrected)

    def test_missing_mixed_precision_or_invalid_dates_are_not_guessed(self):
        for rows in ([document(period='2025-99-99')],[document(registered=None),document('other')],
                     [document(),document('other',registered='2026-06-02T12:00:00Z')]):
            with self.assertRaises(ApiError):newest(rows)

    def test_pdf_is_detected_from_bytes_not_name(self):
        self.assertEqual(inspect(b'%PDF-1.7 synthetic')['pdf'],1)
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w') as archive:
            archive.writestr('synthetic.bin',b'%PDF-1.7')
            archive.writestr('synthetic.xhtml',b'<html/>')
        self.assertEqual(inspect(stream.getvalue()),{'pdf':1,'xhtml':1})
        with self.assertRaises(ApiError):inspect(b'not a document')


class Authentication(unittest.TestCase):
    def client(self):
        with patch.dict('os.environ',BOLAGSVERKET_CLIENT_ID='synthetic-id',BOLAGSVERKET_CLIENT_SECRET='synthetic-secret'):
            return Client()

    def test_missing_secrets_fail_without_request(self):
        with patch.dict('os.environ',BOLAGSVERKET_CLIENT_ID='',BOLAGSVERKET_CLIENT_SECRET=''):
            with self.assertRaises(ApiError):Client()

    def test_token_cached_and_renewed(self):
        client=self.client()
        response=json.dumps({'access_token':'synthetic-token','expires_in':300}).encode()
        with patch.object(client,'_request',return_value=response) as request,patch('time.monotonic',return_value=0):
            self.assertEqual(client._access_token(),'synthetic-token')
            self.assertEqual(client._access_token(),'synthetic-token')
            self.assertEqual(request.call_count,1)
        with patch.object(client,'_request',return_value=response) as request,patch('time.monotonic',return_value=400):
            client._access_token()
            self.assertEqual(request.call_count,1)

    def test_401_gets_one_renewal_and_no_infinite_retry(self):
        client=self.client()
        with patch.object(client,'_access_token',return_value='synthetic-token') as token, \
             patch.object(client,'_request',side_effect=[ApiError('Bolagsverket HTTP 401'),b'ok']):
            self.assertEqual(client._authorized('/synthetic'),b'ok')
            self.assertEqual(token.call_count,2)
        with patch.object(client,'_access_token',return_value='synthetic-token'), \
             patch.object(client,'_request',side_effect=ApiError('Bolagsverket HTTP 401')) as request:
            with self.assertRaises(ApiError):client._authorized('/synthetic')
            self.assertEqual(request.call_count,2)

    def test_error_payload_and_url_never_leak(self):
        client=self.client()
        error=urllib.error.HTTPError('https://synthetic.example/secret-identifier',403,'synthetic-secret',{},io.BytesIO(b'synthetic-secret'))
        with patch.object(client.opener,'open',side_effect=error),patch('time.sleep'):
            with self.assertRaisesRegex(ApiError,'^Bolagsverket HTTP 403$'):
                client._request('https://synthetic.example',None,{},100)

    def test_retry_after_and_rate_limit_apply(self):
        client=self.client()
        error=urllib.error.HTTPError('https://synthetic.example',429,'retry',{'Retry-After':'3'},io.BytesIO())
        response=MagicMock()
        response.__enter__.return_value.read.return_value=b'ok'
        with patch.object(client.opener,'open',side_effect=[error,response]),patch('time.monotonic',return_value=0),patch('time.sleep') as sleep:
            self.assertEqual(client._request('https://synthetic.example',None,{},100),b'ok')
            self.assertEqual(client.requests,2)
            self.assertIn(unittest.mock.call(3),sleep.call_args_list)
            self.assertIn(unittest.mock.call(1.2),sleep.call_args_list)

    def test_redirects_and_oversized_responses_fail_closed(self):
        with self.assertRaises(ApiError):NoRedirect().redirect_request(None,None,302,'',{},'https://synthetic.example')
        client=self.client()
        response=MagicMock()
        response.__enter__.return_value.read.return_value=b'oversized'
        with patch.object(client.opener,'open',return_value=response),patch('time.sleep'):
            with self.assertRaises(ApiError):client._request('https://synthetic.example',None,{},1)


if __name__=='__main__':unittest.main()
