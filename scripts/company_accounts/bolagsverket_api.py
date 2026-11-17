"""Bounded production HVD client. Credentials/tokens/payloads never in logs."""
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = 'https://gw.api.bolagsverket.se/vardefulla-datamangder/v1'
TOKEN = 'https://portal.api.bolagsverket.se/oauth2/token'


class ApiError(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ApiError('Unexpected API redirect')


class Client:
    def __init__(self):
        self.client_id = os.environ.get('BOLAGSVERKET_CLIENT_ID', '').strip()
        self.secret = os.environ.get('BOLAGSVERKET_CLIENT_SECRET', '').strip()
        if not self.client_id or not self.secret:
            raise ApiError('Missing Bolagsverket GitHub secrets')
        self.opener = urllib.request.build_opener(NoRedirect())
        self.token = None
        self.expires = 0
        self.next_request = 0
        self.requests = 0

    def _request(self, url, data, headers, limit):
        for attempt in range(5):
            time.sleep(max(0, self.next_request-time.monotonic()))
            self.next_request = time.monotonic()+1.2  # <=50 requests/minute, including retries/token.
            self.requests += 1
            try:
                with self.opener.open(urllib.request.Request(url, data, headers), timeout=90) as response:
                    content = response.read(limit+1)
                if len(content)>limit:
                    raise ApiError('API response exceeded size limit')
                return content
            except urllib.error.HTTPError as exc:
                if exc.code not in (408,429,500,502,503,504) or attempt==4:
                    # HTTPError includes URL (document/company ID); never propagate it.
                    raise ApiError(f'Bolagsverket HTTP {exc.code}') from None
                retry = exc.headers.get('Retry-After', '')
                delay = min(120, int(retry)) if retry.isdigit() else min(30,2**attempt)
            except (TimeoutError,OSError):
                if attempt==4:
                    raise ApiError('Bolagsverket network failure') from None
                delay = min(30,2**attempt)
            time.sleep(delay)

    def _access_token(self):
        if self.token and time.monotonic()<self.expires:
            return self.token
        data = urllib.parse.urlencode(dict(grant_type='client_credentials',client_id=self.client_id,
            client_secret=self.secret,scope='vardefulla-datamangder:read')).encode()
        raw = self._request(TOKEN,data,{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},100_000)
        try:
            result = json.loads(raw)
            token, ttl = result['access_token'], int(result['expires_in'])
            if not isinstance(token,str) or not token or ttl<=0:
                raise ValueError()
        except (ValueError,KeyError,TypeError):
            raise ApiError('Unexpected OAuth response schema') from None
        self.token = token
        self.expires = time.monotonic()+max(0,ttl-min(60,ttl/2))
        return token

    def _authorized(self, path, data=None, limit=40_000_000):
        for refresh in range(2):
            headers = {'Authorization':'Bearer '+self._access_token(),'Accept':'application/json, application/zip, application/pdf'}
            if data is not None:
                headers['Content-Type']='application/json'
            try:
                return self._request(BASE+path,data,headers,limit)
            except ApiError as exc:
                if str(exc)!='Bolagsverket HTTP 401' or refresh:
                    raise
                self.token = None  # One controlled renewal after an expired/revoked token.

    def documents(self, org_nr):
        if not re.fullmatch(r'\d{10}',org_nr):
            raise ApiError('Invalid company identifier')
        raw = self._authorized('/dokumentlista',json.dumps({'identitetsbeteckning':org_nr}).encode(),2_000_000)
        try:
            result = json.loads(raw)
        except ValueError:
            raise ApiError('Unexpected document-list JSON') from None
        return normalize_documents(result)

    def document(self, document_id):
        if not isinstance(document_id,str) or not document_id or len(document_id)>500:
            raise ApiError('Invalid document identifier')
        return self._authorized('/dokument/'+urllib.parse.quote(document_id,safe=''))


def normalize_documents(result):
    if not isinstance(result,dict) or 'dokument' not in result or not isinstance(result['dokument'],list):
        raise ApiError('Unexpected document-list schema')
    documents = result['dokument']
    for row in documents:
        if not isinstance(row,dict) or not isinstance(row.get('dokumentId'),str):
            raise ApiError('Unexpected document metadata schema')
        # Keep unknown fields in memory but never guess period/order from IDs.
        for field in ('rapporteringsperiodTom','registreringstidpunkt'):
            if row.get(field) is not None and not isinstance(row[field],str):
                raise ApiError('Unexpected document date schema')
    return documents


def newest(documents):
    """Select only if period and registration order are explicit and unambiguous."""
    if not documents:
        return None
    if any(not re.fullmatch(r'\d{4}-\d{2}-\d{2}',d.get('rapporteringsperiodTom') or '') for d in documents):
        raise ApiError('Document period missing or unsupported')
    from datetime import date
    try:
        for d in documents:
            date.fromisoformat(d['rapporteringsperiodTom'])
    except ValueError:
        raise ApiError('Invalid document period') from None
    period = max(d['rapporteringsperiodTom'] for d in documents)
    candidates = [d for d in documents if d['rapporteringsperiodTom']==period]
    if len(candidates)==1:
        return candidates[0]
    from datetime import datetime, timezone
    try:
        registrations = [d['registreringstidpunkt'] for d in candidates]
        date_only = [bool(re.fullmatch(r'\d{4}-\d{2}-\d{2}',r)) for r in registrations]
        if any(date_only) and not all(date_only):
            raise ValueError()
        # API v1 documents date precision. Different days can be ordered;
        # two distinct reports on the same day remain explicitly ambiguous.
        dated = [(datetime.fromisoformat(d['registreringstidpunkt'].replace('Z','+00:00')+('T00:00:00+00:00' if all(date_only) else '')),d) for d in candidates]
        if any(t.tzinfo is None for t,_ in dated):
            raise ValueError()
        latest = max(t.astimezone(timezone.utc) for t,_ in dated)
        chosen = [d for t,d in dated if t.astimezone(timezone.utc)==latest]
    except (KeyError,TypeError,ValueError):
        raise ApiError('Ambiguous report registration order') from None
    if len({d['dokumentId'] for d in chosen})!=1:
        raise ApiError('Ambiguous same-time reports')
    return chosen[0]


if __name__=='__main__':
    try:
        client = Client()
        # Public AB reference supplied in the user's earlier R integration.
        # Only counts are printed, never identities, document IDs or payloads.
        rows = client.documents('5592457187')
        print(json.dumps({'oauth_verified':True,'document_list_verified':True,
                          'reference_documents_listed':len(rows),'requests':client.requests}))
    except Exception as exc:
        print(json.dumps({'oauth_verified':False,'error':str(exc) if isinstance(exc,ApiError) else type(exc).__name__}))
        raise SystemExit(1)
