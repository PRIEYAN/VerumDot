#!/usr/bin/env bash
# Diagnose the NVIDIA suspend/resume services. Run by hand after a resume
# failure; nothing calls it automatically.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard core/log os/proc

readonly -a SERVICES=(
  nvidia-suspend.service
  nvidia-hibernate.service
  nvidia-resume.service
)

guard::has systemctl || log::die 'systemctl is unavailable'

printf 'NVIDIA power-management services\n\n'
for service in "${SERVICES[@]}"; do
  printf '  %-28s %s\n' "$service" "$(proc::capture_or 'not installed' systemctl is-enabled "$service")"
done

printf '\nKernel module parameters\n\n'
for parameter in PreserveVideoMemoryAllocations TemporaryFilePath; do
  printf '  %-32s %s\n' "$parameter" \
    "$(proc::capture_or '(unset)' cat "/sys/module/nvidia/parameters/${parameter}")"
done

printf '\nPreserveVideoMemoryAllocations=1 is what lets the card restore VRAM\n'
printf 'across a suspend. If it is 0, add it to the nvidia modprobe options\n'
printf 'and rebuild the initramfs.\n'
