#!/bin/bash
# On a Mac with Xcode and CocoaPods: installs, prebuilds iOS, and builds the StrictProbe scheme (a local module whose
# podspec sets SWIFT_TREAT_WARNINGS_AS_ERRORS and whose Swift only imports ExpoModulesCore) for a generic iOS device,
# unsigned. Exits 1 while the build fails on warnings in expo-modules-core's own headers, 0 once it succeeds, and 2 when
# a step fails another way. It then compares the three headers with expo/expo's main.
# runs outside Git Bash: on a Mac
set -uo pipefail

cd "$(dirname "$0")" || exit 2

readonly HEADERS=(
  ios/Interfaces/FileSystem/EXFileSystemInterface.h
  ios/Utilities/EXImageLoader.h
  ios/Legacy/ModuleRegistryAdapter/EXModuleRegistryHolderReactModule.h
)

step_failed() {
  echo "SUMMARY: step failed: $1"
  exit 2
}

package_version() {
  node -p "require('./node_modules/$1/package.json').version" 2>/dev/null || printf 'not installed'
}

if [ ! -d node_modules ]; then
  npm install --no-audit --no-fund >install.log 2>&1 || step_failed "npm install (install.log)"
fi
product=$(sw_vers -productName) || step_failed "sw_vers"
product_version=$(sw_vers -productVersion) || step_failed "sw_vers"
xcode_version=$(xcodebuild -version | head -n 1) || step_failed "xcodebuild -version"
pod_version=$(pod --version) || step_failed "pod --version"
node_version=$(node --version) || step_failed "node --version"
package_versions=""
for package in expo expo-modules-core react-native; do
  version=$(package_version "$package") || exit 2
  package_versions+=", $package $version"
done
echo "System: $product $product_version, $xcode_version, CocoaPods $pod_version, node $node_version$package_versions"

npx --no-install expo prebuild --platform ios --clean >prebuild.log 2>&1 || step_failed "expo prebuild (prebuild.log)"
workspace=$(find ios -maxdepth 1 -name "*.xcworkspace" | head -n 1)
[ -n "$workspace" ] || step_failed "prebuild wrote no .xcworkspace"

echo "\$ xcodebuild -workspace $workspace -scheme StrictProbe -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build"
xcodebuild -workspace "$workspace" -scheme StrictProbe -configuration Release -destination generic/platform=iOS \
  -derivedDataPath build/derived-data CODE_SIGNING_ALLOWED=NO build >build.log 2>&1
status=$?
echo "exit $status"
header_errors=$(grep -E '/ExpoModulesCore\.framework/Headers/(EXFileSystemInterface|EXImageLoader|EXModuleRegistryHolderReactModule)\.h:[0-9]+:[0-9]+: error: ' build.log |
  sed -E 's#^.*/(ExpoModulesCore\.framework/Headers/)#…/\1#' | LC_ALL=C sort -u)
[ -n "$header_errors" ] && echo "$header_errors"
grep -m 1 -E '^\*\* BUILD (SUCCEEDED|FAILED) \*\*' build.log

main=$(git ls-remote https://github.com/expo/expo.git refs/heads/main | cut -c 1-10)
package=node_modules/expo-modules-core
for header in "${HEADERS[@]}"; do
  if curl -sfL "https://raw.githubusercontent.com/expo/expo/$main/packages/expo-modules-core/$header" -o main-header.h &&
    cmp -s "$package/$header" main-header.h; then
    echo "$header: the installed copy matches expo/expo main at $main"
  else
    echo "$header: differs from expo/expo main at $main, or could not be fetched"
  fi
done

if [ "$status" -eq 0 ]; then
  echo "SUMMARY: fixed: the module builds with warnings as errors, importing ExpoModulesCore"
  exit 0
fi
if [ -n "$header_errors" ]; then
  count=$(grep -c '' <<<"$header_errors")
  echo "SUMMARY: defect: building ExpoModulesCore's Clang module with the module's warnings as errors fails on $count warnings in expo-modules-core's own headers"
  exit 1
fi
tail -n 30 build.log
echo "SUMMARY: step failed: the build failed another way (build.log)"
exit 2
