"""kOS TV: añade una versión del complemento al catálogo de Jellyfin.

El catálogo (manifest.json) es lo que Jellyfin lee al añadir el repositorio
en Panel > Complementos > Repositorios. Va como archivo de la publicación fija
«complemento», en una dirección que no cambia (ver kostv.json).

Uso: python3 catalogo.py <catálogo actual o ""> <versión> <url del zip>
         <md5> <novedades> <salida>
"""
import datetime
import json
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
info = json.load(open(os.path.join(here, "kostv.json"), encoding="utf-8"))
current, version, url, checksum, changelog, out = sys.argv[1:7]


def parts(v):
    return tuple(int(x) for x in v.split("."))


versions = []
if current and os.path.exists(current):
    for plugin in json.load(open(current, encoding="utf-8")):
        if plugin.get("guid") == info["guid"]:
            versions = plugin.get("versions", [])

newest = max((parts(v["version"]) for v in versions), default=None)
if any(v["version"] == version for v in versions):
    sys.exit(f"La versión {version} ya está en el catálogo.")
if newest is not None and parts(version) <= newest:
    sys.exit(f"La versión {version} tiene que ser mayor que la última, {'.'.join(map(str, newest))}.")

versions.insert(0, {
    "version": version,
    "changelog": changelog,
    "targetAbi": info["targetAbi"],
    "sourceUrl": url,
    "checksum": checksum,
    "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "dependencies": [],
})
catalog = [{
    "guid": info["guid"],
    "name": info["name"],
    "overview": info["overview"],
    "description": info["description"],
    "owner": info["owner"],
    "category": info["category"],
    "imageUrl": info["imageUrl"],
    "versions": versions,
}]
json.dump(catalog, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print(f"Catálogo con {len(versions)} versiones; la última, {version}.")
