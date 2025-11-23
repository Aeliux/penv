#!/usr/bin/env python3

from dataclasses import dataclass, field
from typing import Dict, List, Optional
import hashlib
import urllib.request
import sys

class Exportable:
    def export(self):
        data = {}
        for k, v in vars(self).items():
            if k.startswith("_") or k in ("aliases",):
                continue

            if isinstance(v, Exportable):
                data[k] = v.export()
            elif isinstance(v, list):
                data[k] = [item.export() if isinstance(item, Exportable) else item for item in v]
            else:
                data[k] = v
        return data

@dataclass(frozen=True)
class Url(Exportable):
    arch: str
    url: str
    sha256: Optional[str] = None  # SHA256 checksum

def calculate_sha256_from_url(url: str) -> str:
    """Download and calculate SHA256 checksum for a URL."""
    print(f"Calculating checksum for: {url}", file=sys.stderr)
    sha256_hash = hashlib.sha256()
    
    try:
        with urllib.request.urlopen(url) as response:
            for chunk in iter(lambda: response.read(8192), b""):
                sha256_hash.update(chunk)
        
        checksum = sha256_hash.hexdigest()
        print(f"  → {checksum}", file=sys.stderr)
        return checksum
    except Exception as e:
        print(f"  → Error: {e}", file=sys.stderr)
        return ""

@dataclass(frozen=True)
class Entry(Exportable):
    id: str
    name: str
    description: str
    urls: List[Url]
    aliases: list[str]


@dataclass(frozen=True)
class Distro(Entry):
    pass

@dataclass(frozen=True)
class Addon(Entry):
    distroIds: List[str] = None  # Empty means compatible with all distros
    
    def __post_init__(self):
        if self.distroIds is None:
            object.__setattr__(self, 'distroIds', [])

entries: Dict[str, List[Entry]] = {
    "distros": [],
    "addons": []
}

distros: List[Distro] = entries["distros"]
addons: List[Addon] = entries["addons"]

distros.append(
    Distro(
        id="ubuntu-24.04-vanilla",
        name="Ubuntu 24.04 vanilla",
        description="Ubuntu 24.04 base rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz",
                sha256="f66a0d91d822e3a60450ee88a99f9464b23e63f0ae43e0f6ade9c21a3bb3c84f"
            )
        ],
        aliases=["ubuntu-24-vanilla", "ubuntu-vanilla"]
    )
)

distros.append(
    Distro(
        id="alpine-3.22-vanilla",
        name="Alpine 3.22 vanilla",
        description="Alpine linux 3.22 mini rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz",
                sha256="b27c30c7557a8b7cab55cb5f2d79b93f9e906be67c32b89a0f49efcd6d2f5c0c"
            )
        ],
        aliases=["alpine-3-vanilla", "alpine-vanilla"]
    )
)

if __name__ == "__main__":
    import json
    import sys
    
    # Check if --calculate-checksums flag is provided
    calculate_checksums = "--calculate-checksums" in sys.argv
    
    index = {
        "distros": {},
        "addons": {}
    }
    
    for cat, target in index.items():
        for entry in entries[cat]:
            data = entry.export()
            
            # Calculate checksums if requested and missing
            if calculate_checksums:
                for url_obj in entry.urls:
                    if not url_obj.sha256:
                        print(f"Missing checksum for {entry.id} ({url_obj.arch})", file=sys.stderr)
            
            for id in [entry.id] + entry.aliases:
                target[id] = data
    
    with open("index.json", 'w') as f:
        js = json.dumps(index, indent=2)
        f.write(js)
    
    print("✓ Index generated successfully", file=sys.stderr)