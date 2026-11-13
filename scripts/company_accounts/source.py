"""Bolagsverket's public bulk listing and verified HTTP Range ZIP access.

No credentials, third party mirrors or complete bulk downloads are required.
The listing's ETag is pinned with If-Match throughout a ZIP read.
"""
import io
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = 'https://vardefulla-datamangder.bolagsverket.se/arsredovisningar-bulkfiler'


def request(url, headers=None):
    for attempt in range(6):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}), timeout=90)
        except urllib.error.HTTPError as exc:
            if exc.code not in (429, 500, 502, 503, 504):
                raise
            delay = min(60, int(exc.headers.get('Retry-After', 2 ** attempt)))
        except (TimeoutError, OSError):
            delay = 2 ** attempt
        if attempt == 5:
            raise RuntimeError('Source unavailable after six attempts')
        time.sleep(delay)


def archives():
    marker = None
    seen = set()
    while True:
        query = {'prefix': 'arsredovisningar/', 'delimiter': '\\'}
        if marker:
            query['marker'] = marker
        with request(ROOT + '?' + urllib.parse.urlencode(query)) as response:
            root = ET.fromstring(response.read())
        ns = {'s': 'http://s3.amazonaws.com/doc/2006-03-01/'}
        if root.tag != '{' + ns['s'] + '}ListBucketResult':
            raise ValueError('Unexpected bulk listing, refusing an empty success')
        rows = root.findall('s:Contents', ns)
        for row in rows:
            def field(name):
                return row.findtext('s:' + name, namespaces=ns)
            key = field('Key')
            if key.endswith('.zip'):
                yield dict(key=key, etag=field('ETag'), size=int(field('Size')),
                           modified=field('LastModified'))
        if root.findtext('s:IsTruncated', namespaces=ns) != 'true':
            break
        next_marker = root.findtext('s:NextMarker', namespaces=ns) or (rows[-1].findtext('s:Key', namespaces=ns) if rows else None)
        if not next_marker or next_marker in seen:
            raise ValueError('Bulk listing cursor did not advance')
        seen.add(next_marker)
        marker = next_marker


class RangeReader(io.RawIOBase):
    """Seekable read-only remote object; holds at most one 128 KiB block."""
    def __init__(self, archive):
        self.url = ROOT + '/' + urllib.parse.quote(archive['key'], safe='/')
        self.size = archive['size']
        self.etag = archive['etag']
        self.position = 0
        self.cached_start = -1
        self.cached = b''
        self.bytes_downloaded = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        target = offset if whence == 0 else self.position + offset if whence == 1 else self.size + offset
        if target < 0:
            raise ValueError('Negative seek')
        self.position = target
        return target

    def read(self, size=-1):
        size = self.size - self.position if size < 0 else min(size, self.size - self.position)
        if size <= 0:
            return b''
        if self.cached_start <= self.position and self.position + size <= self.cached_start + len(self.cached):
            offset = self.position - self.cached_start
            self.position += size
            return self.cached[offset:offset + size]
        start = self.position
        end = min(self.size - 1, start + max(size, 131072) - 1)
        with request(self.url, {'Range': f'bytes={start}-{end}', 'If-Match': self.etag,
                                'Accept-Encoding': 'identity'}) as response:
            if response.status != 206 or response.headers.get('Content-Range') != f'bytes {start}-{end}/{self.size}':
                raise ValueError('Server did not honor HTTP Range; refusing full bulk download')
            data = response.read(end - start + 2)
        if len(data) != end - start + 1:
            raise ValueError('Incomplete or oversized range response')
        self.bytes_downloaded += len(data)
        self.cached_start, self.cached = start, data
        self.position += size
        return data[:size]


def open_archive(archive):
    reader = RangeReader(archive)
    return reader, zipfile.ZipFile(reader)
