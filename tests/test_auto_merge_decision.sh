#!/usr/bin/env bash
set -euo pipefail
source scripts/auto_merge_decision.sh
for value in failure cancelled skipped neutral none error in_progress ''; do
  if is_ci_green "$value"; then echo "Unexpected green: $value" >&2; exit 1; fi
done
is_ci_green success
[[ "$(ci_conclusion_from_json '')" == error ]]
[[ "$(ci_conclusion_from_json '{broken')" == error ]]
[[ "$(ci_conclusion_from_json '{"workflow_runs":[]}')" == none ]]
[[ "$(ci_conclusion_from_json '{"workflow_runs":[{"conclusion":"success"}]}')" == success ]]
[[ "$(ci_conclusion_from_json '{"workflow_runs":[{"conclusion":"failure"},{"conclusion":"success"}]}')" == failure ]]
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
git -C "$fixture" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm base --allow-empty
base=$(git -C "$fixture" rev-parse HEAD)
git -C "$fixture" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm next --allow-empty
tip=$(git -C "$fixture" rev-parse HEAD)
(
  cd "$fixture"
  is_ancestor_of "$base" "$tip"
  if is_ancestor_of "$tip" "$base"; then echo 'Advanced tip treated as merged' >&2; exit 1; fi
  if is_ancestor_of missing-ref "$tip" 2>/dev/null; then echo 'Missing ref treated as merged' >&2; exit 1; fi
)
echo 'Merge-decision fixtures passed'
