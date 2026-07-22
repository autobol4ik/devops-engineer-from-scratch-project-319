#!/bin/sh

set -eu

input_file="$(mktemp)"
output_file="$(mktemp)"
trap 'rm -f "$input_file" "$output_file"' EXIT HUP INT TERM

cat >"$input_file"

prometheus_count="$(awk '$0 == "kind: Prometheus" { count++ } END { print count + 0 }' "$input_file")"
sentinel_count="$(awk '$0 == "  - bearerToken: __HEXLET_5_POST_RENDERER_TOKEN__" { count++ } END { print count + 0 }' "$input_file")"
bearer_token_count="$(awk '/^[[:space:]]*-[[:space:]]+bearerToken:/ { count++ } END { print count + 0 }' "$input_file")"

if [ "$prometheus_count" -ne 1 ]; then
  echo "post-renderer: expected exactly one Prometheus resource, found $prometheus_count" >&2
  exit 1
fi

if [ "$sentinel_count" -ne 2 ] || [ "$bearer_token_count" -ne 2 ]; then
  echo "post-renderer: expected exactly two sentinel bearerToken fields and no other bearerToken fields" >&2
  exit 1
fi

awk '
  $0 == "  - bearerToken: __HEXLET_5_POST_RENDERER_TOKEN__" {
    sentinel_index++
    print "  - authorization:"
    print "      credentials:"
    print "        name: hexlet-5-monitoring-credentials"
    print "        key: api-key"
    if (sentinel_index == 2) {
      print "    writeRelabelConfigs:"
      print "      - action: labeldrop"
      print "        regex: ^(id|image|uid|container_id|image_id)$"
    }
    next
  }
  { print }
' "$input_file" >"$output_file"

remaining_tokens="$(awk '/bearerToken:|__HEXLET_5_POST_RENDERER_TOKEN__/ { count++ } END { print count + 0 }' "$output_file")"
secret_names="$(awk '$0 == "        name: hexlet-5-monitoring-credentials" { count++ } END { print count + 0 }' "$output_file")"
secret_keys="$(awk '$0 == "        key: api-key" { count++ } END { print count + 0 }' "$output_file")"
write_relabel_configs="$(awk '$0 == "    writeRelabelConfigs:" { count++ } END { print count + 0 }' "$output_file")"
write_relabel_keeps="$(awk '
  $0 == "    writeRelabelConfigs:" { in_block = 1; next }
  in_block && ($0 ~ /^    [^ ]/ || $0 == "---") { in_block = 0 }
  in_block && $0 == "      - action: keep" { count++ }
  END { print count + 0 }
' "$output_file")"
write_relabel_labeldrops="$(awk '
  $0 == "    writeRelabelConfigs:" { in_block = 1; next }
  in_block && ($0 ~ /^    [^ ]/ || $0 == "---") { in_block = 0 }
  in_block && $0 == "      - action: labeldrop" { count++ }
  END { print count + 0 }
' "$output_file")"

if [ "$remaining_tokens" -ne 0 ] || [ "$secret_names" -ne 2 ] || [ "$secret_keys" -ne 2 ] || [ "$write_relabel_configs" -ne 1 ] || [ "$write_relabel_keeps" -ne 0 ] || [ "$write_relabel_labeldrops" -ne 1 ]; then
  echo "post-renderer: unsafe or incomplete Prometheus authentication patch" >&2
  exit 1
fi

cat "$output_file"
