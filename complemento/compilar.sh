#!/usr/bin/env bash
# kOS TV: compila el complemento del servidor y prepara el zip que instala
# Jellyfin, con la identidad de kOS TV (complemento/kostv.json).
#
# Uso: complemento/compilar.sh <versión> [carpeta de salida]
#   <versión>: X.Y.Z.N. X.Y.Z es la versión oficial en la que se basa y N la
#   nuestra sobre ella (3.1.0.1 = la oficial 3.1.0 y nuestro primer cambio).
#
# Deja en la carpeta de salida el zip y un .md5 con su suma (la que pide el
# catálogo de Jellyfin).
set -euo pipefail

VERSION="${1:?Falta la versión, por ejemplo 3.1.0.1}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "La versión tiene que ser X.Y.Z.N (por ejemplo 3.1.0.1): $VERSION" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${2:-$ROOT/salida}"
BACKEND="$ROOT/Jellyfin/backend"
PUBLISH="$BACKEND/bin/Release/net8.0/publish"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

echo "--- Compilando el complemento kOS TV $VERSION ---"
# Desde cero, para que el paquete no lleve nada de una compilación anterior.
rm -rf "$BACKEND/bin/Release" "$BACKEND/obj/Release"
dotnet publish "$BACKEND/Moonfin.Server.csproj" \
  -c Release \
  -o "$PUBLISH" \
  -p:AssemblyVersion="$VERSION" \
  -p:FileVersion="$VERSION" \
  -p:Version="$VERSION"

echo "--- Comprobando el paquete ---"
dotnet run --project "$ROOT/Jellyfin/tools/verify-plugin/VerifyPlugin.csproj" \
  -c Release -- "$PUBLISH/Moonfin.Server.dll" "$VERSION"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$PUBLISH/Moonfin.Server.dll" "$PUBLISH/SharpCompress.dll" "$STAGE/"
cp "$BACKEND/assets/logo.png" "$STAGE/logo.png"

# meta.json: lo que Jellyfin lee del complemento instalado.
python3 - "$ROOT/kostv.json" "$VERSION" "$STAGE/meta.json" <<'EOF'
import datetime, json, sys
info = json.load(open(sys.argv[1], encoding="utf-8"))
meta = {
    "category": info["category"],
    "changelog": "",
    "description": info["description"],
    "guid": info["guid"],
    "name": info["name"],
    "overview": info["overview"],
    "owner": info["owner"],
    "targetAbi": info["targetAbi"],
    "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "version": sys.argv[2],
    "status": "Active",
    "autoUpdate": True,
    "imagePath": "logo.png",
    "assemblies": info["assemblies"],
}
json.dump(meta, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF

mkdir -p "$OUT"
ZIP="$OUT/kOS-TV-complemento-$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -q -r "$ZIP" .)
md5sum "$ZIP" | awk '{print toupper($1)}' > "$ZIP.md5"
echo "Listo: $ZIP (md5 $(cat "$ZIP.md5"))"
