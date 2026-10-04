#!/usr/bin/env bash
# Volume state for the eww panel, as {volume, muted}.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use domain/audio

volume=$(audio::volume) || volume=0
audio::muted && muted=true || muted=false

jq -nc --argjson v "${volume:-0}" --argjson m "$muted" '{volume: $v, muted: $m}'
