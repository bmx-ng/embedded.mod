#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$(cd "$module_root/../.." && pwd)"
bmk="${UI_TEST_BMK:-$sdk/bin/bmk}"
requested_target="${1:-all}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/embedded-ui-tiers.XXXXXX")"

cleanup() {
	if [[ "${UI_TEST_KEEP:-0}" == "1" ]]; then
		printf 'UI tier artifacts retained in %s\n' "$work_dir"
	else
		rm -rf -- "$work_dir"
	fi
}
trap cleanup EXIT

case "$requested_target" in
	pico|esp32|all) ;;
	*)
		printf 'usage: %s [pico|esp32|all]\n' "$0" >&2
		exit 2
		;;
esac

file_size() {
	wc -c < "$1" | tr -d '[:space:]'
}

linker_map() {
	local output="$1"
	if [[ -s "$output.elf.map" ]]; then
		printf '%s\n' "$output.elf.map"
	elif [[ -s "$output.map" ]]; then
		printf '%s\n' "$output.map"
	else
		return 1
	fi
}

require_symbol() {
	local map_file="$1"
	local symbol="$2"
	local description="$3"
	if ! grep -q "$symbol" "$map_file"; then
		printf 'missing %s in %s\n' "$description" "$map_file" >&2
		exit 1
	fi
}

reject_symbol() {
	local map_file="$1"
	local symbol="$2"
	local description="$3"
	if grep -q "$symbol" "$map_file"; then
		printf 'unexpected %s in %s\n' "$description" "$map_file" >&2
		exit 1
	fi
}

check_maximum() {
	local value="$1"
	local maximum="$2"
	local description="$3"
	if (( value > maximum )); then
		printf '%s is %d bytes; budget is %d bytes\n' "$description" "$value" "$maximum" >&2
		exit 1
	fi
}

check_range() {
	local value="$1"
	local minimum="$2"
	local maximum="$3"
	local description="$4"
	if (( value < minimum || value > maximum )); then
		printf '%s is %d bytes; expected %d..%d bytes\n' \
			"$description" "$value" "$minimum" "$maximum" >&2
		exit 1
	fi
}

build_tier() {
	local platform="$1"
	local board="$2"
	local fixture="$3"
	local output_dir="$work_dir/$platform"
	local output="$output_dir/$fixture"
	local command=("$bmk" makeapp)
	mkdir -p "$output_dir"
	if [[ "${UI_TEST_REBUILD:-1}" == "1" ]]; then command+=(-a); fi
	if [[ "$platform" == "pico" ]]; then
		"${command[@]}" -r -l pico -g arm -board "$board" \
			-o "$output" "$module_root/tests/$fixture.bmx"
	else
		"${command[@]}" -r -board "$board" \
			-o "$output" "$module_root/tests/$fixture.bmx"
	fi
	if [[ ! -s "$output.bin" ]] || ! linker_map "$output" >/dev/null; then
		printf 'missing firmware or linker map for %s/%s\n' "$platform" "$fixture" >&2
		exit 1
	fi
}

run_target() {
	local platform="$1"
	local board="$2"
	local passive_max controls_max interactive_max
	if [[ "$platform" == "pico" ]]; then
		passive_max="${UI_TEST_PICO_PASSIVE_MAX:-200000}"
		controls_max="${UI_TEST_PICO_CONTROLS_MAX:-250000}"
		interactive_max="${UI_TEST_PICO_INTERACTIVE_MAX:-260000}"
	else
		passive_max="${UI_TEST_ESP32_PASSIVE_MAX:-380000}"
		controls_max="${UI_TEST_ESP32_CONTROLS_MAX:-430000}"
		interactive_max="${UI_TEST_ESP32_INTERACTIVE_MAX:-440000}"
	fi

	build_tier "$platform" "$board" embedded_ui_display_only
	build_tier "$platform" "$board" embedded_ui_controls_only
	build_tier "$platform" "$board" embedded_ui_interactive_adapter

	local output_dir="$work_dir/$platform"
	local passive_map controls_map interactive_map
	passive_map="$(linker_map "$output_dir/embedded_ui_display_only")"
	controls_map="$(linker_map "$output_dir/embedded_ui_controls_only")"
	interactive_map="$(linker_map "$output_dir/embedded_ui_interactive_adapter")"
	local controls_symbol="__bb_embedded_ui_controls_controls"
	local interactive_symbol="__bb_embedded_ui_interactive_interactive"

	reject_symbol "$passive_map" "$controls_symbol" "control module"
	reject_symbol "$passive_map" "$interactive_symbol" "touch adapter"
	require_symbol "$controls_map" "$controls_symbol" "control module"
	reject_symbol "$controls_map" "$interactive_symbol" "touch adapter"
	require_symbol "$interactive_map" "$controls_symbol" "control module"
	require_symbol "$interactive_map" "$interactive_symbol" "touch adapter"

	local passive_size controls_size interactive_size
	passive_size="$(file_size "$output_dir/embedded_ui_display_only.bin")"
	controls_size="$(file_size "$output_dir/embedded_ui_controls_only.bin")"
	interactive_size="$(file_size "$output_dir/embedded_ui_interactive_adapter.bin")"
	check_maximum "$passive_size" "$passive_max" "$platform passive firmware"
	check_maximum "$controls_size" "$controls_max" "$platform controls-only firmware"
	check_maximum "$interactive_size" "$interactive_max" "$platform interactive firmware"

	local controls_delta=$((controls_size - passive_size))
	local interactive_delta=$((interactive_size - controls_size))
	check_range "$controls_delta" "${UI_TEST_CONTROL_DELTA_MIN:-30000}" \
		"${UI_TEST_CONTROL_DELTA_MAX:-70000}" "$platform control tier overhead"
	check_range "$interactive_delta" "${UI_TEST_INTERACTIVE_DELTA_MIN:-4000}" \
		"${UI_TEST_INTERACTIVE_DELTA_MAX:-25000}" "$platform touch tier overhead"

	printf '%-6s %-24s %8d bytes\n' "$platform" passive "$passive_size"
	printf '%-6s %-24s %8d bytes (+%d)\n' "$platform" controls-only "$controls_size" "$controls_delta"
	printf '%-6s %-24s %8d bytes (+%d)\n' "$platform" interactive "$interactive_size" "$interactive_delta"
	printf '%s UI tier matrix passed for board %s\n' "$platform" "$board"
}

if [[ "$requested_target" == "pico" || "$requested_target" == "all" ]]; then
	run_target pico "${UI_TEST_PICO_BOARD:-pico2_w}"
fi
if [[ "$requested_target" == "esp32" || "$requested_target" == "all" ]]; then
	run_target esp32 "${UI_TEST_ESP32_BOARD:-esp32_s31_korvo_1}"
fi
