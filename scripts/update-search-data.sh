#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
temp_dir="$(mktemp -d /private/tmp/spotmoji-search-data.XXXXXX)"

cleanup() {
	/usr/bin/trash "$temp_dir"
}
trap cleanup EXIT

npm pack --silent --pack-destination "$temp_dir" \
	emojibase-data@17.0.0 \
	emojilib@4.0.3 >/dev/null

mkdir -p "$temp_dir/emojibase" "$temp_dir/emojilib"
tar -xzf "$temp_dir/emojibase-data-17.0.0.tgz" -C "$temp_dir/emojibase"
tar -xzf "$temp_dir/emojilib-4.0.3.tgz" -C "$temp_dir/emojilib"

swift "$repo_root/Tools/generate_search_metadata.swift" \
	"$repo_root/Sources/Spotmoji/Resources/emojis.json" \
	"$temp_dir/emojibase/package/en/data.json" \
	"$temp_dir/emojilib/package/dist/emoji-en-US.json" \
	"$temp_dir/emojibase/package/en/shortcodes" \
	"$repo_root/Sources/Spotmoji/Resources/emoji-search.json"
