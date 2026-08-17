#!/bin/zsh

# Archive both iOS and macOS variants and export release artifacts.

set -euo pipefail
setopt NULL_GLOB

project_dir="${0:A:h}"
project_path="$project_dir/EhViewer.xcodeproj"
scheme="EhViewer"
configuration="Release"
release_directory="$project_dir/release"
timestamp="$(/bin/date '+%Y%m%d-%H%M%S')"
build_directory="$project_dir/.build/release/$timestamp"

if [[ $# -gt 0 ]]; then
    print "Usage: $0" >&2
    exit 2
fi

if [[ ! -d "$project_path" ]]; then
    print "Xcode project not found: $project_path" >&2
    exit 1
fi

/bin/mkdir -p "$release_directory" "$build_directory"

archive_platform() {
    local platform="$1"
    local sdk="$2"
    local archive_path="$3"

    print "==> Archiving $sdk"
    /usr/bin/xcodebuild \
        -project "$project_path" \
        -scheme "$scheme" \
        -configuration "$configuration" \
        -destination "generic/platform=$platform" \
        -sdk "$sdk" \
        -archivePath "$archive_path" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        SKIP_INSTALL=NO \
        archive
}

application_path_from_archive() {
    local archive_path="$1"
    local application_relative_path=""

    if [[ -f "$archive_path/Info.plist" ]]; then
        application_relative_path=$(
            /usr/libexec/PlistBuddy \
                -c 'Print :ApplicationProperties:ApplicationPath' \
                "$archive_path/Info.plist" 2>/dev/null || true
        )
    fi

    if [[ -n "$application_relative_path" && -d "$archive_path/Products/$application_relative_path" ]]; then
        print -r -- "$archive_path/Products/$application_relative_path"
        return
    fi

    local app_candidates=("$archive_path/Products/Applications"/*.app(N))
    if [[ ${#app_candidates[@]} -eq 0 ]]; then
        print "No .app was found in: $archive_path/Products/Applications" >&2
        return 1
    fi
    print -r -- "${app_candidates[1]}"
}

application_version() {
    local app_path="$1"
    local version

    version=$(
        /usr/libexec/PlistBuddy \
            -c 'Print :CFBundleShortVersionString' \
            "$app_path/Info.plist" 2>/dev/null || true
    )
    if [[ -z "$version" ]]; then
        print "Unable to read CFBundleShortVersionString from: $app_path" >&2
        return 1
    fi
    print -r -- "$version"
}

validate_ipa() {
    local ipa_path="$1"
    local app_name="$2"
    local archive_listing

    /usr/bin/unzip -tq "$ipa_path"
    archive_listing=$(/usr/bin/unzip -Z1 "$ipa_path")
    if [[ "$archive_listing" == *"__MACOSX/"* ]]; then
        print "The generated IPA contains an unexpected __MACOSX directory." >&2
        return 1
    fi
    if [[ "$archive_listing" != *"Payload/$app_name.app/"* ]]; then
        print "The generated IPA is missing Payload/$app_name.app/." >&2
        return 1
    fi

    local unexpected_entry
    unexpected_entry=$(
        print -r -- "$archive_listing" | /usr/bin/awk '
            {
                path = tolower($0)
                if (path ~ /(^|\/)(\.ds_store|\.git|\.build|deriveddata|sourcepackages|xcuserdata)(\/|$)/ ||
                    path ~ /(^|\/)\.env($|\.)/ ||
                    path ~ /\.(swift|xcuserstate|p12|pfx|key)$/ ||
                    path ~ /(^|\/)(__preview|[^\/]+\.debug)\.dylib$/) {
                    print $0
                    exit
                }
            }
        '
    )
    if [[ -n "$unexpected_entry" ]]; then
        print "The generated IPA contains an unexpected development or sensitive file: $unexpected_entry" >&2
        return 1
    fi
}

package_ipa() {
    local app_path="$1"
    local output_path="$2"
    local app_name="${app_path:t}"
    app_name="${app_name%.app}"
    local package_directory="$build_directory/ipa"
    local payload_directory="$package_directory/Payload"
    local ipa_path="$package_directory/$app_name.ipa"

    /bin/mkdir -p "$payload_directory"
    /usr/bin/ditto "$app_path" "$payload_directory/$app_name.app"
    (
        cd "$package_directory"
        /usr/bin/zip -qry "$ipa_path" Payload
    )
    /bin/cp -f "$ipa_path" "$output_path"
    validate_ipa "$output_path" "$app_name"

    print "IPA:    $output_path"
    print "Size:   $(/usr/bin/stat -f '%z bytes' "$output_path")"
    print "SHA256: $(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
}

package_dmg() {
    local app_path="$1"
    local output_path="$2"
    local app_name="${app_path:t}"
    app_name="${app_name%.app}"
    local staging_directory="$build_directory/dmg"

    /bin/mkdir -p "$staging_directory"
    /usr/bin/ditto "$app_path" "$staging_directory/$app_name.app"
    /bin/ln -s /Applications "$staging_directory/Applications"
    /usr/bin/hdiutil create \
        -volname "EhViewer $version" \
        -srcfolder "$staging_directory" \
        -ov \
        -format UDZO \
        "$output_path" >/dev/null
    /usr/bin/hdiutil imageinfo "$output_path" >/dev/null

    print "DMG:    $output_path"
    print "Size:   $(/usr/bin/stat -f '%z bytes' "$output_path")"
    print "SHA256: $(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
}

ios_archive="$build_directory/EhViewer-iOS.xcarchive"
macos_archive="$build_directory/EhViewer-macOS.xcarchive"

archive_platform iOS iphoneos "$ios_archive"
ios_app_path="$(application_path_from_archive "$ios_archive")"
version="$(application_version "$ios_app_path")"
ipa_output="$release_directory/EhViewer-$version.ipa"
dmg_output="$release_directory/EhViewer-$version-macOS.dmg"

archive_platform macOS macosx "$macos_archive"
macos_app_path="$(application_path_from_archive "$macos_archive")"

print "==> Packaging version $version"
package_ipa "$ios_app_path" "$ipa_output"
package_dmg "$macos_app_path" "$dmg_output"

print ""
print "Release artifacts written to: $release_directory"
print "Build archives retained in:   $build_directory"
