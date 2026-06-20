#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <flutter-bundle> <output.deb> <full|lite>" >&2
  exit 2
fi

bundle_dir=$1
output_deb=$2
variant=$3
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ! -x "$bundle_dir/ScoringNidra" ]]; then
  echo "Linux bundle executable not found: $bundle_dir/ScoringNidra" >&2
  exit 1
fi
if [[ "$variant" != "full" && "$variant" != "lite" ]]; then
  echo "Variant must be 'full' or 'lite'." >&2
  exit 2
fi

version=$(awk '/^version:/ {print $2; exit}' "$repo_root/frontend/pubspec.yaml")
version=${version%%+*}
package_name=scoringnidra
display_name=ScoringNidra
conflicts=scoringnidra-lite
description="Sleep EEG visualization, scoring, and quantitative analysis"
if [[ "$variant" == "lite" ]]; then
  package_name=scoringnidra-lite
  display_name="ScoringNidra Lite"
  conflicts=scoringnidra
  description="Sleep EEG visualization, manual scoring, and quantitative analysis"
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
package_root="$work_dir/package"
install_dir="$package_root/usr/lib/scoringnidra"

mkdir -p \
  "$package_root/DEBIAN" \
  "$install_dir" \
  "$package_root/usr/bin" \
  "$package_root/usr/share/applications" \
  "$package_root/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle_dir/." "$install_dir/"
ln -s ../lib/scoringnidra/ScoringNidra "$package_root/usr/bin/scoringnidra"
install -m 0644 "$repo_root/frontend/assets/logo.png" \
  "$package_root/usr/share/icons/hicolor/256x256/apps/scoringnidra.png"

installed_size=$(du -sk "$package_root/usr" | awk '{print $1}')
cat > "$package_root/DEBIAN/control" <<EOF
Package: $package_name
Version: $version
Section: science
Priority: optional
Architecture: amd64
Installed-Size: $installed_size
Depends: libgtk-3-0, libblkid1, liblzma5
Conflicts: $conflicts
Maintainer: ScoringNidra Project <noreply@github.com>
Homepage: https://github.com/arunsasidharan84/ScoringNidra
Description: $description
 ScoringNidra is a desktop application for polysomnography review,
 sleep staging, and advanced quantitative EEG analysis.
EOF

cat > "$package_root/usr/share/applications/scoringnidra.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$display_name
Comment=$description
Exec=/usr/bin/scoringnidra
Icon=scoringnidra
Terminal=false
Categories=Science;Education;MedicalSoftware;
StartupNotify=true
StartupWMClass=ScoringNidra
EOF

mkdir -p "$(dirname "$output_deb")"
dpkg-deb --build --root-owner-group "$package_root" "$output_deb"
dpkg-deb --info "$output_deb"
dpkg-deb --contents "$output_deb" | grep -E \
  'usr/bin/scoringnidra|usr/lib/scoringnidra/ScoringNidra|scoringnidra.desktop'
