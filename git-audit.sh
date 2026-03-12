#!/bin/bash

AUTHOR="$1"
SINCE="$2"
UNTIL="$3"

if [ -z "$AUTHOR" ]; then
  echo "Usage: ./git_audit.sh \"Author Name or Email\" [since] [until]"
  echo "Example: ./git_audit.sh \"john@company.com\" 2026-01-01 2026-03-01"
  exit 1
fi

echo "========================================="
echo "GIT AUDIT REPORT"
echo "Author : $AUTHOR"
echo "Since  : ${SINCE:-beginning}"
echo "Until  : ${UNTIL:-now}"
echo "Repo   : $(basename $(git rev-parse --show-toplevel))"
echo "========================================="
echo

echo "📅 Activity by day (commits)"
git log --all \
  --author="$AUTHOR" \
  ${SINCE:+--since="$SINCE"} \
  ${UNTIL:+--until="$UNTIL"} \
  --date=short \
  --pretty="%ad" \
| sort | uniq -c | sort -k2

echo
echo "-----------------------------------------"
echo "🔀 Merge commits"
git log --all \
  --author="$AUTHOR" \
  --merges \
  ${SINCE:+--since="$SINCE"} \
  ${UNTIL:+--until="$UNTIL"} \
  --pretty=format:"%h %ad %s" \
  --date=short

echo
echo "-----------------------------------------"
echo "📦 Commit summary"
git log --all \
  --author="$AUTHOR" \
  ${SINCE:+--since="$SINCE"} \
  ${UNTIL:+--until="$UNTIL"} \
  --pretty=format:"%h %ad %s" \
  --date=short

echo
echo "-----------------------------------------"
echo "📊 Total lines added / removed"
git log --all \
  --author="$AUTHOR" \
  ${SINCE:+--since="$SINCE"} \
  ${UNTIL:+--until="$UNTIL"} \
  --shortstat \
| awk '
/files? changed/ {
  added += $4
  removed += $6
}
END {
  printf "Lines added: %d\n", added
  printf "Lines removed: %d\n", removed
}
'

echo
echo "-----------------------------------------"
echo "📁 Files touched"
git log --all \
  --author="$AUTHOR" \
  ${SINCE:+--since="$SINCE"} \
  ${UNTIL:+--until="$UNTIL"} \
  --name-only \
  --pretty="" \
| sort | uniq -c | sort -nr | head -20

echo
echo "-----------------------------------------"
echo "🏁 End of report"
