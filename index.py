#!/usr/bin/env python3

from dataclasses import dataclass, field
from typing import Dict, List

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
    distroIds: List[str]

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

if __name__ == "__main__":
    import json
    
    index = {
        "distros": {},
        "addons": {}
    }
    
    for cat, target in index.items():
        for entry in entries[cat]:
            data = entry.export()
            for id in [entry.id] + entry.aliases:
                target[id] = data
    
    with open("index.json", 'w') as f:
        js = json.dumps(index, indent=2)
        f.write(js)