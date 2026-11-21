#!/usr/bin/env bash
# kOS TV: comprueba que el complemento ya compilado funciona con varias versiones
# de Jellyfin. Lo carga con las DLL reales de cada versión (de NuGet) y mira que
# se resuelva cada referencia que hace a Jellyfin, que compile cada método y que
# las tareas programadas den sus disparadores. El complemento se compila contra
# 10.10, así que algo que Jellyfin cambió después compila sin avisar y solo
# falla en el servidor, al usarse (MissingMethodException).
#
# Uso: comprobar.sh <Moonfin.Server.dll> [versiones de Jellyfin…]
#   Sin versiones, las de siempre: 10.10.0 (contra la que se compila), 10.10.7
#   (la última 10.10, que ya quitó cosas de la 10.10.0), 10.11.11 y 12.4.0.
#   La DLL tiene que estar en su carpeta de publicación (con SharpCompress.dll).
#
# Hace falta el SDK de .NET 10. Termina con error si alguna versión tiene algo roto.
set -euo pipefail

DLL="${1:?Falta la DLL del complemento (Moonfin.Server.dll)}"
shift
VERSIONS=("$@")
if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=(10.10.0 10.10.7 10.11.11 12.4.0)
fi
[ -f "$DLL" ] || { echo "No existe $DLL" >&2; exit 2; }
DLL="$(cd "$(dirname "$DLL")" && pwd)/$(basename "$DLL")"

TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
# Fuera de la carpeta de la herramienta: se borra al terminar.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$TOOL/bin" "$TOOL/obj"' EXIT

failed=()
for v in "${VERSIONS[@]}"; do
  echo "--- Jellyfin $v ---"
  out="$WORK/$v"
  # Una carpeta obj por versión, para que no se pisen sus paquetes.
  dotnet build "$TOOL/AbiCheck.csproj" -c Release -nologo -v quiet \
    -p:JfVer="$v" \
    -p:BaseIntermediateOutputPath="$WORK/obj-$v/" \
    -p:MSBuildProjectExtensionsPath="$WORK/obj-$v/" \
    -o "$out" >"$WORK/build-$v.log" 2>&1 || { cat "$WORK/build-$v.log"; exit 2; }
  # La DLL junto a las de Jellyfin, y lo que lleva el complemento al lado.
  mkdir -p "$out/plugin"
  cp "$(dirname "$DLL")"/*.dll "$out/plugin/"
  if ! dotnet "$out/AbiCheck.dll" "$out/plugin/$(basename "$DLL")"; then
    failed+=("$v")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "El complemento tiene referencias rotas con Jellyfin ${failed[*]}." >&2
  exit 1
fi
echo "El complemento es compatible con Jellyfin ${VERSIONS[*]}."
