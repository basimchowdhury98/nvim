#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )) || [[ -z $1 || $1 =~ [[:space:]] ]]; then
  printf 'Usage: %s <label-with-no-spaces>\n' "${0##*/}" >&2
  exit 1
fi

label=$1
runs=100
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
results_file="$(dirname -- "${BASH_SOURCE[0]}")/results.txt"

for ((i = 1; i <= runs; i++)); do
  log="$tmp_dir/startup.log"
  : >"$log"

  if ! nvim --headless --startuptime "$log" +qa >/dev/null 2>&1; then
    printf 'Neovim startup failed on run %d\n' "$i" >&2
    exit 1
  fi

  awk '/NVIM STARTED/ { print $1 }' "$log" >>"$tmp_dir/times"
done

read -r average minimum maximum median < <(sort -n "$tmp_dir/times" | awk -v runs="$runs" '
  NR == 1 { min = $1 }
  { times[NR] = $1; sum += $1; max = $1 }
  END {
    median = (times[runs / 2] + times[runs / 2 + 1]) / 2
    printf "%.3f %.3f %.3f %.3f\n", sum / runs, min, max, median
  }
')

printf 'Runs:    %d\nAverage: %s ms\nMinimum: %s ms\nMaximum: %s ms\nMedian:  %s ms\n' \
  "$runs" "$average" "$minimum" "$maximum" "$median"
printf 'Average: %s ms | Minimum: %s ms | Maximum: %s ms | Median: %s ms (%s)\n' \
  "$average" "$minimum" "$maximum" "$median" "$label" >>"$results_file"
