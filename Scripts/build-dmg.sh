#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_name="PINGGO"
app_path="$project_root/dist/$app_name.app"
dmg_path="$project_root/dist/$app_name.dmg"

"$project_root/Scripts/build-app.sh"

stage_dir=$(mktemp -d "/tmp/${app_name}_dmg.XXXXXX")
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

# ditto preserves the bundle's metadata and code-signature files.
ditto "$app_path" "$stage_dir/$app_name.app"
ln -s /Applications "$stage_dir/Applications"

hdiutil create \
  -volname "$app_name" \
  -srcfolder "$stage_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

hdiutil verify "$dmg_path"
echo "Built and verified $dmg_path"
