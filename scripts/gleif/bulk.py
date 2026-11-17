"""Stream the pinned public RR/REPEX CSV files; retain only requested LEIs."""
import csv
import hashlib
import io
import os
import tempfile
import urllib.parse
import zipfile
from collections import defaultdict
from .client import MANIFEST,GleifError

FIELDS={'rr':{'Relationship.StartNode.NodeID','Relationship.EndNode.NodeID','Relationship.RelationshipType',
              'Relationship.RelationshipStatus','Registration.RegistrationStatus','DeletedAt'},
        'repex':{'LEI','Exception.Category','Exception.Reason.1','DeletedAt'}}
VERSIONS={'rr':'RR_2.1','repex':'REPEX_2.1'}


def read_csv(path,kind,needed,expected_count):
    selected=defaultdict(list);n=0
    with zipfile.ZipFile(path) as z:
        entries=[i for i in z.infolist() if not i.is_dir()]
        if len(entries)!=1 or not entries[0].filename.endswith('.csv') or entries[0].file_size>4_000_000_000:
            raise GleifError('Unexpected GLEIF archive')
        with io.TextIOWrapper(z.open(entries[0]),encoding='utf-8-sig',newline='') as f:
            reader=csv.DictReader(f)
            if not FIELDS[kind].issubset(reader.fieldnames or []):raise GleifError('Unknown GLEIF CSV contract')
            idkey='Relationship.StartNode.NodeID' if kind=='rr' else 'LEI'
            for row in reader:
                n+=1
                if None in row:raise GleifError('Invalid CSV width')
                if row[idkey] in needed:
                    selected[row[idkey]].append({k:v for k,v in row.items() if v})
    if n!=expected_count:raise GleifError('GLEIF source record count mismatch')
    return dict(selected)


def load(client,needed):
    data=client.json(MANIFEST)['data'];release=data['publish_date'];manifest={};selected={}
    for kind in ('rr','repex'):
        f=data[kind]['full_file']['csv'];u=urllib.parse.urlparse(f['url'])
        if f['cdf_version']!=VERSIONS[kind] or data[kind]['publish_date']!=release or f['format']!='csv':
            raise GleifError('Unknown GLEIF release contract')
        if u.scheme!='https' or u.netloc!='goldencopy.gleif.org' or not u.path.startswith('/storage/golden-copy-files/'):
            raise GleifError('Untrusted bulk source')
        if not 0<f['size']<=120_000_000:raise GleifError('GLEIF file size outside bound')
        # The source files are temporary, never uploaded as Actions artifacts.
        with tempfile.TemporaryDirectory(prefix='gleif-') as directory:
            path=os.path.join(directory,kind+'.zip');sha=hashlib.sha256();size=0
            with client.response(f['url']) as response,open(path,'wb') as out:
                while True:
                    chunk=response.read(1024*1024)
                    if not chunk:break
                    size+=len(chunk)
                    if size>f['size']:raise GleifError('Oversized GLEIF bulk source')
                    sha.update(chunk);out.write(chunk)
            if size!=f['size']:raise GleifError('Incomplete GLEIF download')
            selected[kind]=read_csv(path,kind,needed,f['record_count'])
            manifest[kind]={'url':f['url'],'sha256':sha.hexdigest(),'size':size,
                'record_count':f['record_count'],'cdf_version':f['cdf_version']}
    return selected,{'release':release,'files':manifest,'license':'CC0-1.0'}
