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

def add_penv_distro(
    family: str,       # e.g., "debian", "alpine"
    distro_base: str,  # e.g., "debian", "ubuntu"
    version: str,      # e.g., "11", "12", "20.04"
    codename: str,     # e.g., "bullseye", "bookworm", "focal"
    release: str,      # e.g., "1.0"
    archs: List[str] = ["amd64", "i386", "arm64", "armhf"],
    aliases: List[str] = None,
    is_latest: bool = False
):
    """
    Add a penv distro with standardized naming and URL patterns.
    
    Args:
        family: Distro family for URL construction (e.g., "debian", "alpine")
        distro_base: Base distro name (debian/ubuntu)
        version: Version number (can include dots like "20.04")
        codename: Release codename
        release: penv release version
        archs: List of architectures to include
        aliases: Additional custom aliases (auto-generated ones are added automatically)
        is_latest: If True, adds base distro name as alias (e.g., "debian", "ubuntu")
    """
    distro_id = f"{distro_base}-{version}-{release}"
    version_short = version.split('.')[0]  # "20.04" -> "20"
    
    # Auto-generate aliases
    auto_aliases = [
        f"{distro_base}-{version}",  # e.g., "debian-11"
    ]
    
    # Add short version alias if different from full version
    if '.' in version:
        auto_aliases.append(f"{distro_base}-{version_short}")
    
    # Add base distro alias if this is marked as latest
    if is_latest:
        auto_aliases.append(distro_base)
    
    # Merge with custom aliases
    if aliases:
        auto_aliases.extend(aliases)
    
    # Generate URLs for each architecture
    urls = []
    for arch in archs:
        urls.append(
            Url(
                arch=arch,
                url=f"https://github.com/Aeliux/penv/releases/download/{family}-{release}/{distro_base}-{codename}-{arch}-rootfs.tar.gz"
            )
        )
    
    distros.append(
        Distro(
            id=distro_id,
            name=f"{distro_base.capitalize()} {version} {release}",
            description=f"{distro_base.capitalize()} {version} ({codename}) penv v{release} rootfs",
            urls=urls,
            aliases=auto_aliases
        )
    )

# Vanilla distros (non-penv)
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

# Penv-built distros

release = "1.0fix3"

# Debian versions
add_penv_distro(family="debian", distro_base="debian", version="11", codename="bullseye", release=release)
add_penv_distro(family="debian", distro_base="debian", version="12", codename="bookworm", release=release)
add_penv_distro(family="debian", distro_base="debian", version="13", codename="trixie", release=release, is_latest=True)

# Ubuntu versions
add_penv_distro(family="debian", distro_base="ubuntu", version="20.04", codename="focal", release=release, archs=["amd64", "i386"])
add_penv_distro(family="debian", distro_base="ubuntu", version="22.04", codename="jammy", release=release, archs=["amd64", "i386"])
add_penv_distro(family="debian", distro_base="ubuntu", version="24.04", codename="noble", release=release, archs=["amd64", "i386"], is_latest=True)

if __name__ == "__main__":
    import json
    import os
    
    calculate_checksums = True
    
    # Load existing index.json to reuse checksums
    existing_index = {"distros": {}, "addons": {}}
    if os.path.exists("index.json"):
        print("Loading existing index.json to reuse checksums")
        try:
            with open("index.json", 'r') as f:
                existing_index = json.load(f)
        except Exception as e:
            print(f"Warning: Could not load existing index.json: {e}", file=sys.stderr)
    
    index = {
        "distros": {},
        "addons": {}
    }
    
    print("Generating index")
    
    for cat, target in index.items():
        print(f"Processing {cat}")
        for entry in entries[cat]:
            print(f"Exporting {entry.id} entry in {cat}")
            data = entry.export()
            
            # Calculate checksums if requested
            if calculate_checksums:
                print("Calculating checksum")
                for url_obj in entry.urls:
                    print(f"{url_obj.arch}: {url_obj.url}")
                    if not url_obj.sha256:
                        # Try to reuse existing checksum from index.json
                        existing_checksum = None
                        if entry.id in existing_index.get(cat, {}):
                            existing_entry = existing_index[cat][entry.id]
                            for existing_url in existing_entry.get('urls', []):
                                if existing_url['url'] == url_obj.url and existing_url.get('sha256'):
                                    existing_checksum = existing_url['sha256']
                                    print(f"  Reusing existing checksum: {existing_checksum}")
                                    break
                        
                        # Only download if we don't have an existing checksum
                        if existing_checksum:
                            checksum = existing_checksum
                        else:
                            print(f"  No existing checksum found, downloading...")
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