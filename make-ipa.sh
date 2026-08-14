#!/bin/zsh

# Package the latest Xcode archive as an IPA that can be re-signed by a
# sideloading tool such as AltStore, SideStore, or Sideloadly.

set -euo pipefail
setopt NULL_GLOB

project_dir="${0:A:h}"
archive_root="$HOME/Library/Developer/Xcode/Archives"

if [[ $# -gt 2 ]]; then
    print "Usage: $0 [path/to/App.xcarchive] [output.ipa]" >&2
    exit 2
fi

if [[ $# -ge 1 ]]; then
    archive_path="${1:A}"
else
    archive_candidates=("$archive_root"/*/*.xcarchive(Nom))
    if [[ ${#archive_candidates} -eq 0 ]]; then
        print "No .xcarchive was found in $archive_root" >&2
        print "Create an archive in Xcode first, then run this script again." >&2
        exit 1
    fi
    archive_path="${archive_candidates[1]}"
fi

if [[ ! -d "$archive_path" ]]; then
    print "Archive not found: $archive_path" >&2
    exit 1
fi

application_relative_path=""
if [[ -f "$archive_path/Info.plist" ]]; then
    application_relative_path=$(
        /usr/libexec/PlistBuddy \
            -c 'Print :ApplicationProperties:ApplicationPath' \
            "$archive_path/Info.plist" 2>/dev/null || true
    )
fi

if [[ -n "$application_relative_path" && -d "$archive_path/Products/$application_relative_path" ]]; then
    app_path="$archive_path/Products/$application_relative_path"
else
    app_candidates=("$archive_path/Products/Applications"/*.app(N))
    if [[ ${#app_candidates} -eq 0 ]]; then
        print "No .app was found in: $archive_path/Products/Applications" >&2
        exit 1
    fi
    app_path="${app_candidates[1]}"
fi

app_name="${app_path:t}"
app_name="${app_name%.app}"
output_path="${2:-$HOME/Desktop/${app_name}-resign.ipa}"
if [[ "$output_path" != /* ]]; then
    output_path="$project_dir/$output_path"
fi

output_directory="${output_path:h}"
/bin/mkdir -p "$output_directory"

work_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ehviewer-ipa.XXXXXX")
trap 'find "$work_dir" -depth -delete >/dev/null 2>&1 || true' EXIT

payload_directory="$work_dir/Payload"
/bin/mkdir "$payload_directory"
/usr/bin/ditto "$app_path" "$payload_directory/$app_name.app"

ipa_path="$work_dir/$app_name.ipa"
(
    cd "$work_dir"
    /usr/bin/zip -qry "$ipa_path" Payload
)
/bin/cp -f "$ipa_path" "$output_path"

/usr/bin/unzip -tq "$output_path"
archive_listing=$(/usr/bin/unzip -Z1 "$output_path")
if [[ "$archive_listing" == *"__MACOSX/"* ]]; then
    print "The generated IPA contains an unexpected __MACOSX directory." >&2
    exit 1
fi
if [[ "$archive_listing" != *"Payload/$app_name.app/"* ]]; then
    print "The generated IPA is missing Payload/$app_name.app/." >&2
    exit 1
fi
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
    exit 1
fi

print "Archive: $archive_path"
print "App:     $app_path"
print "Output:  $output_path"
print "Size:    $(/usr/bin/stat -f '%z bytes' "$output_path")"
print "SHA-256: $(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
