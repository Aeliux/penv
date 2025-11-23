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
        print(checksum)
        return checksum
    except Exception as e:
        print()
        print(f"Error: {e}", file=sys.stderr)
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
    distroIds: List[str] = field(default_factory=list)

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
                url="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz"
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
                url="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz"
            )
        ],
        aliases=["alpine-3-vanilla", "alpine-vanilla"]
    )
)

distros.append(
    Distro(
        id="debian-11-1.0fix3",
        name="Debian 11 1.0fix3",
        description="Debian 11 (bullseye) penv v1.0fix3 rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bullseye-amd64-rootfs.tar.gz"
            ),
            Url(
                arch="i386",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bullseye-i386-rootfs.tar.gz"
            ),
            Url(
                arch="arm64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bullseye-arm64-rootfs.tar.gz"
            ),
            Url(
                arch="armhf",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bullseye-armhf-rootfs.tar.gz"
            )
        ],
        aliases=["debian-11-1.0", "debian-11", "debian"]
    )
)

distros.append(
    Distro(
        id="debian-12-1.0fix3",
        name="Debian 12 1.0fix3",
        description="Debian 12 (bookworm) penv v1.0fix3 rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bookworm-amd64-rootfs.tar.gz"
            ),
            Url(
                arch="i386",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bookworm-i386-rootfs.tar.gz"
            ),
            Url(
                arch="arm64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bookworm-arm64-rootfs.tar.gz"
            ),
            Url(
                arch="armhf",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-bookworm-armhf-rootfs.tar.gz"
            )
        ],
        aliases=["debian-12-1.0", "debian-12", "debian"]
    )
)

distros.append(
    Distro(
        id="debian-13-1.0fix3",
        name="Debian 13 1.0fix3",
        description="Debian 13 (trixie) penv v1.0fix3 rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-trixie-amd64-rootfs.tar.gz"
            ),
            Url(
                arch="i386",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-trixie-i386-rootfs.tar.gz"
            ),
            Url(
                arch="arm64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-trixie-arm64-rootfs.tar.gz"
            ),
            Url(
                arch="armhf",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/debian-trixie-armhf-rootfs.tar.gz"
            )
        ],
        aliases=["debian-13-1.0", "debian-13", "debian"]
    )
)

distros.append(
    Distro(
        id="ubuntu-20.04-1.0fix3",
        name="Ubuntu 20.04 1.0fix3",
        description="Ubuntu 20.04 (focal) penv v1.0fix3 rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/ubuntu-focal-amd64-rootfs.tar.gz"
            ),
            Url(
                arch="i386",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/ubuntu-focal-i386-rootfs.tar.gz"
            )
        ],
        aliases=["ubuntu-20.04-1.0", "ubuntu-20.04", "ubuntu-20", "ubuntu"]
    )
)

distros.append(
    Distro(
        id="ubuntu-22.04-1.0fix3",
        name="Ubuntu 22.04 1.0fix3",
        description="Ubuntu 22.04 (jammy) penv v1.0fix3 rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/ubuntu-jammy-amd64-rootfs.tar.gz"
            ),
            Url(
                arch="i386",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/ubuntu-jammy-i386-rootfs.tar.gz"
            )
        ],
        aliases=["ubuntu-22.04-1.0", "ubuntu-22.04", "ubuntu-22", "ubuntu"]
    )
)

distros.append(
    Distro(
        id="ubuntu-24.04-1.0fix3",
        name="Ubuntu 24.04 1.0fix3",
        description="Ubuntu 24.04 (noble) penv v1.0fix3 rootfs",
        urls=[
            Url(
                arch="amd64",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/ubuntu-noble-amd64-rootfs.tar.gz"
            ),
            Url(
                arch="i386",
                url="https://github.com/Aeliux/penv/releases/download/debian-1.0fix3/ubuntu-noble-i386-rootfs.tar.gz"
            )
        ],
        aliases=["ubuntu-24.04-1.0", "ubuntu-24.04", "ubuntu-24", "ubuntu"]
    )
)

if __name__ == "__main__":
    import json
    
    calculate_checksums = True
    
    index = {
        "distros": {},
        "addons": {}
    }
    
    print("Generating index")
    
    for cat, target in index.items():
        print(f"Processing {cat}")
        for entry in entries[cat]:
            print(f"Exporting {entry} entry in {cat}")
            data = entry.export()
            
            # Calculate checksums if requested
            if calculate_checksums:
                print("Calculating checksum")
                for url_obj in entry.urls:
                    print(f"{url_obj.arch}: {url_obj.url}")
                    if not url_obj.sha256:
                        checksum = calculate_sha256_from_url(url_obj.url)
                        if checksum:
                            for url_data in data['urls']:
                                if url_data['url'] == url_obj.url:
                                    url_data['sha256'] = checksum
                                    break
            
            for id in [entry.id] + entry.aliases:
                print(f"Adding alias: {id}")
                target[id] = data
    
    print("Writing index.json")
    
    with open("index.json", 'w') as f:
        js = json.dumps(index, indent=2)
        f.write(js)
    
    print("Index generated successfully")