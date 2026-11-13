"""Bounded, lease-safe ZIP directory reuse across parallel company imports.

Only compressed range blocks and ZIP directory metadata stay in runner memory.
Every range remains pinned to the source ETag. Nothing is copied into AFR.
"""
import threading
from collections import OrderedDict
from contextlib import contextmanager
from .source import open_archive


class Entry:
    def __init__(self):
        self.ready = threading.Event()
        self.leases = 0
        self.reader = self.zip = None
        self.error = None


class ArchivePool:
    def __init__(self, capacity=64, opener=open_archive):
        self.capacity = capacity
        self.opener = opener
        self.entries = OrderedDict()
        self.lock = threading.Lock()

    def evict(self):
        # Called under lock; active readers are never closed by another worker.
        for key in list(self.entries):
            if len(self.entries) <= self.capacity:
                break
            entry = self.entries[key]
            if entry.leases == 0 and entry.ready.is_set():
                del self.entries[key]
                if entry.zip is not None:
                    entry.zip.close()
                if entry.reader is not None:
                    entry.reader.close()

    @contextmanager
    def acquire(self, archive):
        key = (archive['key'], archive['etag'], archive['size'])
        with self.lock:
            entry = self.entries.get(key)
            owner = entry is None
            if owner:
                entry = Entry()
                self.entries[key] = entry
            self.entries.move_to_end(key)
            entry.leases += 1
        if owner:
            try:
                entry.reader, entry.zip = self.opener(archive)
            except Exception as exc:
                entry.error = exc
            finally:
                entry.ready.set()
        else:
            entry.ready.wait()
        try:
            if entry.error is not None:
                raise entry.error
            # ZipFile serializes seek/read on its shared file via _SharedFile.
            # Independent member handles can therefore be read concurrently.
            yield entry.zip
        finally:
            with self.lock:
                entry.leases -= 1
                if entry.error is not None and entry.leases == 0:
                    self.entries.pop(key, None)
                self.evict()


POOL = ArchivePool()
