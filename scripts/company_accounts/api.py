"""Existing ETL bearer credentials; do not log payloads or signed URLs."""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request


def call(action, body=None, **params):
    root = os.environ['ETL_BASE_URL'].rstrip('/') + '/api/public/jobs/company-data'
    headers = {'Authorization': 'Bearer ' + os.environ['ETL_PUBLISH_KEY'], 'Accept': 'application/json'}
    if body is None:
        url = root + '?' + urllib.parse.urlencode({'action': action, **params})
        data = None
    else:
        url = root
        data = json.dumps({'action': action, **body}, ensure_ascii=False, separators=(',', ':')).encode()
        headers['Content-Type'] = 'application/json'
    for attempt in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data, headers), timeout=180) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code not in (408, 429, 500, 502, 503, 504) or attempt == 5:
                # Source payloads, bearer values and storage tokens never appear in errors.
                detail = ''
                if exc.code == 400:
                    try:
                        payload = json.load(exc)
                        paths = ['.'.join(str(p) for p in issue.get('path', [])) for issue in payload.get('issues', [])[:5]]
                        if paths:
                            detail = ' (schema paths: ' + ', '.join(paths) + ')'
                    except (ValueError, OSError, AttributeError):
                        pass
                raise RuntimeError(f'ETL {action}: HTTP {exc.code}' + detail) from None
        except (TimeoutError, OSError):
            if attempt == 5:
                raise RuntimeError(f'ETL {action}: network failure') from None
        time.sleep(min(30, 2 ** attempt))


def upload(package, sha):
    signed = call('upload', {'sha256': sha})
    if not signed.get('exists'):
        req = urllib.request.Request(signed['signed_url'], package, {'Content-Type': 'application/zip'}, method='PUT')
        try:
            with urllib.request.urlopen(req, timeout=180) as response:
                response.read()
        except urllib.error.HTTPError as exc:
            # A lost successful upload is safe to retry: the next call finds it.
            if exc.code not in (400, 409):
                raise RuntimeError(f'Source archive upload: HTTP {exc.code}') from None
    return signed['path']


def log(source, status, period, details, error=None):
    body = dict(source_id=source, status=status, period=period, details=details)
    if error:
        body['error'] = error
    return call('log', body)
