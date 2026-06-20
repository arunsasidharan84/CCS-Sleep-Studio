#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <flutter-bundle> <output.rpm> <full|lite>" >&2
  exit 2
fi

bundle_dir=$1
output_rpm=$2
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
top_dir="$work_dir/rpmbuild"
source_dir="$top_dir/SOURCES"
mkdir -p "$source_dir/bundle" "$top_dir/SPECS"
cp -a "$bundle_dir/." "$source_dir/bundle/"
install -m 0644 "$repo_root/frontend/assets/logo.png" \
  "$source_dir/scoringnidra.png"

cat > "$source_dir/scoringnidra.desktop" <<EOF
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

cat > "$top_dir/SPECS/scoringnidra.spec" <<EOF
%global debug_package %{nil}
Name:           $package_name
Version:        $version
Release:        1%{?dist}
Summary:        $description
License:        Proprietary
URL:            https://github.com/arunsasidharan84/ScoringNidra
BuildArch:      x86_64
Requires:       gtk3, glibc, libstdc++, util-linux-libs, xz-libs
Conflicts:      $conflicts

%description
ScoringNidra is a desktop application for polysomnography review,
sleep staging, and advanced quantitative EEG analysis.

%prep

%build

%install
mkdir -p \
  %{buildroot}/usr/lib/scoringnidra \
  %{buildroot}/usr/bin \
  %{buildroot}/usr/share/applications \
  %{buildroot}/usr/share/icons/hicolor/256x256/apps
cp -a %{_sourcedir}/bundle/. %{buildroot}/usr/lib/scoringnidra/
ln -s ../lib/scoringnidra/ScoringNidra %{buildroot}/usr/bin/scoringnidra
install -m 0644 %{_sourcedir}/scoringnidra.desktop \
  %{buildroot}/usr/share/applications/scoringnidra.desktop
install -m 0644 %{_sourcedir}/scoringnidra.png \
  %{buildroot}/usr/share/icons/hicolor/256x256/apps/scoringnidra.png

%files
/usr/bin/scoringnidra
/usr/lib/scoringnidra
/usr/share/applications/scoringnidra.desktop
/usr/share/icons/hicolor/256x256/apps/scoringnidra.png

%changelog
* Sat Jun 20 2026 ScoringNidra Project <noreply@github.com> - $version-1
- Automated desktop release
EOF

rpmbuild --define "_topdir $top_dir" --target x86_64 \
  -bb "$top_dir/SPECS/scoringnidra.spec"
built_rpm=$(find "$top_dir/RPMS" -type f -name '*.rpm' -print -quit)
if [[ -z "$built_rpm" ]]; then
  echo "rpmbuild did not produce an RPM package." >&2
  exit 1
fi
mkdir -p "$(dirname "$output_rpm")"
cp "$built_rpm" "$output_rpm"
rpm -qip "$output_rpm"
rpm -qlp "$output_rpm" | grep -E \
  '/usr/bin/scoringnidra|/usr/lib/scoringnidra/ScoringNidra|scoringnidra.desktop'
