#!/usr/bin/env bash
set -euo pipefail

# Lock after 5 minutes, turn screen off after 10 minutes
exec hypridle --lock 5m --off 10m
