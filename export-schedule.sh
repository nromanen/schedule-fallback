#!/usr/bin/env bash
# Exports schedule JSON for the static fallback page and pushes it to the backup repo.
#
# Writes into $REPO:
#   semesters.json    - the semester list
#   full-<id>.json    - full schedule of every enabled semester that has not ended yet
# A file is replaced only by a valid export, so if the app is down or a schedule
# is unpublished (the API then answers 200 with a status instead of a schedule),
# the previous good copy stays in place.
#
# Requires: curl, jq, git (with push access to the backup repo).
set -euo pipefail

API="${API:-http://localhost:8080}"            # the app itself, on mathserver
REPO="${REPO:-$HOME/schedule-fallback}"        # git clone of the backup site (index.html lives there)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. semester list
curl -fsS --max-time 30 "$API/public/semesters" -o "$TMP/semesters.json"
jq -e 'type == "array" and length > 0' "$TMP/semesters.json" >/dev/null
cp "$TMP/semesters.json" "$REPO/semesters.json"

# 2. every enabled semester whose endDay (dd/MM/yyyy) is today or later
today="$(date +%F)"
ids="$(jq -r --arg today "$today" '
  .[] | select(.disable == false)
      | select((.endDay | split("/") | "\(.[2])-\(.[1])-\(.[0])") >= $today)
      | .id' "$TMP/semesters.json")"

for id in $ids; do
  out="$TMP/full-$id.json"
  # week format: {semester, schedule[]}; date format (scheduledByDate): {semester, dates[], items[]}
  if curl -fsS --max-time 60 "$API/schedules/full/semester?semesterId=$id" -o "$out" \
     && jq -e '.semester.id and ((.schedule | type) == "array" or (.items | type) == "array")' "$out" >/dev/null; then
    cp "$out" "$REPO/full-$id.json"
  else
    echo "$(date '+%F %T') semester $id: export failed, keeping the previous file" >&2
  fi
done

# 3. publish only when something changed
cd "$REPO"
git add semesters.json full-*.json
if ! git diff --cached --quiet; then
  git commit -qm "Schedule snapshot $(date '+%F %H:%M')"
  git push -q
fi
