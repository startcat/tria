#!/bin/bash
# Prepara una versión de tria y, con --publish, la publica: la etiqueta, la release de GitHub con el binario universal
# y la fórmula del tap de Homebrew (startcat/homebrew-tap).
#
# Uso: scripts/release.sh <versión> [--publish] [--yes] [--tap-dir <ruta>]
#
# Sin --publish es un ensayo: lo deja todo en dist/ y no sube nada. Con --publish pregunta antes de cada paso que sube
# algo, salvo con --yes. El tap, por defecto, es ../homebrew-tap.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

version=""
publish=false
assume_yes=false
tap_dir="../homebrew-tap"
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) publish=true ;;
    --yes) assume_yes=true ;;
    --tap-dir) shift; tap_dir="${1:?falta la ruta de --tap-dir}" ;;
    -*) fail "opción desconocida: $1" ;;
    *) [ -z "$version" ] || fail "sobra un argumento: $1"; version="$1" ;;
  esac
  shift
done
[ -n "$version" ] || fail "uso: scripts/release.sh <versión> [--publish] [--yes] [--tap-dir <ruta>]"

# Antes de compilar nada: la versión es la del código y no hay cambios sin commit.
source_version=$(sed -n 's/.*public static let version = "\(.*\)"/\1/p' Sources/TriaKit/TriaInfo.swift)
[ "$version" = "$source_version" ] || fail "la versión no coincide: pides $version y TriaInfo.version es $source_version"
[ -z "$(git status --porcelain)" ] || fail "el árbol no está limpio: haz commit o descarta los cambios antes"

tag="v$version"
if $publish; then
  # Lo que hace falta para publicar, también antes de compilar: si falta algo, mejor saberlo ya.
  git remote get-url github >/dev/null 2>&1 || fail "falta el remoto github (git remote add github https://github.com/startcat/tria.git)"
  gh auth status >/dev/null 2>&1 || fail "gh no tiene sesión: gh auth login"
  [ -f "$tap_dir/Formula/tria.rb" ] || fail "no encuentro la fórmula en $tap_dir/Formula/tria.rb"
  git -C "$tap_dir" remote get-url origin >/dev/null 2>&1 || fail "el tap de $tap_dir no tiene remoto origin"
  # Una etiqueta que ya existe vale si es la de este commit (se repite tras un fallo a medias); si no, se para.
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    [ "$(git rev-list -n 1 "$tag")" = "$(git rev-parse HEAD)" ] || fail "la etiqueta $tag ya existe y no es de este commit"
  fi
fi

ask() {
  $assume_yes && return 0
  local answer
  read -r -p "$1 [s/N] " answer
  [ "$answer" = "s" ] || [ "$answer" = "S" ]
}

echo "== Pruebas"
swift test

echo "== Binario universal"
scripts/build-release.sh
# La firma ad hoc, explícita: un binario universal hecho con lipo puede quedar sin ella, y en arm64 no arrancaría.
codesign --force -s - dist/tria
codesign --verify dist/tria
archs=$(lipo -archs dist/tria)
[[ $archs == *arm64* && $archs == *x86_64* ]] || fail "faltan arquitecturas: $archs"

echo "== Fuera de su carpeta, como lo instala Homebrew"
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
cp dist/tria "$probe/tria"
TRIA_LANG=en "$probe/tria" --version | grep -q "$version" || fail "--version no dice $version"
TRIA_LANG=en "$probe/tria" --help | grep -q "sorts documents" || fail "la ayuda en inglés no sale"

echo "== Paquete"
package="tria-$version-macos.tar.gz"
cp LICENSE README.md "$probe/"
# Sin los ficheros ._ de los atributos extendidos de macOS.
COPYFILE_DISABLE=1 tar -czf "dist/$package" -C "$probe" tria LICENSE README.md
(cd dist && shasum -a 256 "$package" > "$package.sha256")
sha=$(cut -d' ' -f1 "dist/$package.sha256")
echo "dist/$package"
echo "sha256 $sha"

if ! $publish; then
  echo "Ensayo hecho: no se ha subido nada."
  exit 0
fi

ask "¿Creo la etiqueta $tag y la subo a github y a origin?" || fail "parado antes de la etiqueta"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git tag -a "$tag" -m "tria $version"
git push github "$tag"
git push origin "$tag"

ask "¿Creo la release $tag en startcat/tria con $package?" || fail "parado antes de la release"
if gh release view "$tag" --repo startcat/tria >/dev/null 2>&1; then
  # Ya existe (un intento anterior): se sustituye el paquete, que es el que corresponde al SHA-256 de la fórmula.
  gh release upload "$tag" "dist/$package" --repo startcat/tria --clobber
else
  gh release create "$tag" "dist/$package" --repo startcat/tria --title "tria $version" --notes "Lyncat Tria $version.

Install with \`brew install startcat/tap/tria\`. Documentation: https://tria.lyn.cat/en/docs"
fi

url="https://github.com/startcat/tria/releases/download/$tag/$package"
sed -i '' -e "s|^  url \".*\"|  url \"$url\"|" -e "s|^  sha256 \".*\"|  sha256 \"$sha\"|" "$tap_dir/Formula/tria.rb"
git -C "$tap_dir" add Formula/tria.rb
git -C "$tap_dir" diff --cached --quiet || git -C "$tap_dir" commit -m "tria $version"
ask "¿Subo la fórmula de tria $version a startcat/homebrew-tap?" || fail "parado antes de subir la fórmula"
git -C "$tap_dir" push -u origin HEAD:main

echo "Publicado: tria $version."
