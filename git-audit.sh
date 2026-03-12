#!/bin/bash
#
# git-audit.sh — Comprehensive Git activity audit for contractor verification
#
# Analyzes all branches of a repository to trace day-by-day activity of a
# specific author, using both AuthorDate (when code was originally written)
# and CommitDate (when the commit was recorded/rebased/amended).
#
# Usage: ./git-audit.sh "Author" YYYY-MM-DD YYYY-MM-DD
#
set -euo pipefail

###############################################################################
# Arguments & validation
###############################################################################
AUTHOR="${1:-}"
SINCE="${2:-}"
UNTIL="${3:-}"

if [[ -z "$AUTHOR" || -z "$SINCE" || -z "$UNTIL" ]]; then
  cat <<'USAGE'
Usage: git-audit.sh "Author" YYYY-MM-DD YYYY-MM-DD

Generates a comprehensive git audit report for a given author,
covering all branches, including:
  - Day-by-day activity breakdown (AuthorDate & CommitDate)
  - Rebase/amend detection (AuthorDate ≠ CommitDate)
  - Hourly activity heatmap
  - Weekend & off-hours analysis
  - Merge commit details
  - Branch activity
  - Files modified ranking
  - Gaps and inactive days
  - Full detailed commit log

Arguments:
  Author    Name or email (partial match, same as git log --author)
  SINCE     Start date (inclusive), format YYYY-MM-DD
  UNTIL     End date (inclusive), format YYYY-MM-DD

Examples:
  git-audit.sh "john@company.com" 2026-01-01 2026-03-01
  git-audit.sh "John Doe"         2026-01-01 2026-03-01
USAGE
  exit 1
fi

for dt in "$SINCE" "$UNTIL"; do
  if ! date -d "$dt" +%Y-%m-%d >/dev/null 2>&1; then
    echo "Error: invalid date '$dt' (expected YYYY-MM-DD)" >&2
    exit 1
  fi
done

SINCE=$(date -d "$SINCE" +%Y-%m-%d)
UNTIL=$(date -d "$UNTIL" +%Y-%m-%d)

if [[ "$SINCE" > "$UNTIL" ]]; then
  echo "Error: start date ($SINCE) is after end date ($UNTIL)" >&2
  exit 1
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Error: not inside a git repository" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")

###############################################################################
# Scratch space
###############################################################################
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

###############################################################################
# Formatting helpers
###############################################################################
SEP="════════════════════════════════════════════════════════════════════════"
SUB="────────────────────────────────────────────────────────────────────────"

section() {
  printf "\n%s\n  %s\n" "$SEP" "$1"
  if [[ -n "${AUTHOR_LABEL:-}" ]]; then
    printf "  Author: %s  |  %s → %s  |  %s\n" "$AUTHOR_LABEL" "$SINCE" "$UNTIL" "$REPO_NAME"
  fi
  printf "%s\n" "$SEP"
}
subsection() { printf "\n%s\n  %s\n%s\n" "$SUB" "$1" "$SUB"; }

###############################################################################
# Header
###############################################################################
echo "$SEP"
echo "  GIT AUDIT REPORT"
echo "$SEP"
printf "  %-30s %s\n" "Search filter:"    "$AUTHOR"
printf "  %-30s %s\n" "Period:"           "$SINCE  →  $UNTIL"
printf "  %-30s %s\n" "Repository:"       "$REPO_NAME"
printf "  %-30s %s\n" "Repository path:"  "$REPO_ROOT"
printf "  %-30s %s\n" "Total branches:"   "$(git branch -a 2>/dev/null | wc -l | tr -d ' ')"
printf "  %-30s %s\n" "Report generated:" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "$SEP"

###############################################################################
# Data collection
###############################################################################
# git --since/--until filter on CommitDate. We use a 90-day buffer so we also
# capture commits *authored* inside the audit window but committed outside
# (rebase, cherry-pick, amend) and vice-versa.
BUF_S=$(date -d "$SINCE - 90 days" +%Y-%m-%d)
BUF_U=$(date -d "$UNTIL + 90 days" +%Y-%m-%d)

echo
echo "Collecting commit data (all branches)…"

# ── 1. Raw commit data (tab-separated) ────────────────────────────────
# Fields: 1=AuthorDateISO 2=CommitDateISO 3=ShortHash 4=FullHash
#         5=ParentHashes  6=AuthorName    7=AuthorEmail 8=Subject
#         9=CommitterName 10=CommitterEmail
git log --all \
  --author="$AUTHOR" \
  --since="$BUF_S" --until="$BUF_U" \
  --pretty=format:"%aI%x09%cI%x09%h%x09%H%x09%P%x09%aN%x09%aE%x09%s%x09%cN%x09%cE" \
  > "$WORK/raw.tsv" 2>/dev/null || true

# ── 2. Per-commit numstat ─────────────────────────────────────────────
git log --all \
  --author="$AUTHOR" \
  --since="$BUF_S" --until="$BUF_U" \
  --pretty=format:"__COMMIT__%x09%H" \
  --numstat \
  > "$WORK/numstat_raw.txt" 2>/dev/null || true

# Parse into: FullHash <TAB> files <TAB> insertions <TAB> deletions
awk -F'\t' '
  /^__COMMIT__\t/ {
    if (h != "") printf "%s\t%d\t%d\t%d\n", h, f, i, d
    h=$2; f=0; i=0; d=0; next
  }
  NF>=3 && $1!="" {
    if ($1 ~ /^[0-9]+$/) { i+=$1; d+=$2 }
    f++
  }
  END { if (h!="") printf "%s\t%d\t%d\t%d\n", h, f, i, d }
' "$WORK/numstat_raw.txt" > "$WORK/stats.tsv"

# ── 3. Date filters ──────────────────────────────────────────────────
# AD = AuthorDate in [SINCE, UNTIL]
awk -F'\t' -v s="$SINCE" -v u="$UNTIL" \
  'substr($1,1,10)>=s && substr($1,1,10)<=u' \
  "$WORK/raw.tsv" > "$WORK/ad.tsv"

# CD = CommitDate in [SINCE, UNTIL]
awk -F'\t' -v s="$SINCE" -v u="$UNTIL" \
  'substr($2,1,10)>=s && substr($2,1,10)<=u' \
  "$WORK/raw.tsv" > "$WORK/cd.tsv"

# UNION = either date in range
awk -F'\t' -v s="$SINCE" -v u="$UNTIL" \
  'substr($1,1,10)>=s && substr($1,1,10)<=u ||
   substr($2,1,10)>=s && substr($2,1,10)<=u' \
  "$WORK/raw.tsv" > "$WORK/union.tsv"

# ── 4. Enrich: join commits with their stats ─────────────────────────
# Appends 3 fields → total 13 fields:  …|files|insertions|deletions
for src in ad cd union; do
  awk -F'\t' '
    NR==FNR { s[$1]=$2"\t"$3"\t"$4; next }
    { h=$4; print $0 "\t" (h in s ? s[h] : "0\t0\t0") }
  ' "$WORK/stats.tsv" "$WORK/${src}.tsv" > "$WORK/${src}_e.tsv"
done

# ── 5. Branch sources (lightweight via --source) ─────────────────────
git log --all --source \
  --author="$AUTHOR" \
  --since="$BUF_S" --until="$BUF_U" \
  --pretty=format:"%H%x09%S" \
  > "$WORK/sources.tsv" 2>/dev/null || true

echo "Data collection complete."

# ── 6. Resolve author identity ────────────────────────────────────────
# Extract all unique author identities (name <email>) from raw data
AUTHOR_IDENTITIES=$(awk -F'\t' '{printf "%s <%s>\n",$6,$7}' "$WORK/raw.tsv" | sort | uniq -c | sort -rn)
AUTHOR_FULL_NAME=$(echo "$AUTHOR_IDENTITIES" | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' | sed 's/ <.*$//')
AUTHOR_EMAIL=$(echo "$AUTHOR_IDENTITIES" | head -1 | sed 's/^.*<//' | sed 's/>$//')

# Extract committer identities (may differ from author after rebase etc.)
COMMITTER_IDENTITIES=$(awk -F'\t' '{printf "%s <%s>\n",$9,$10}' "$WORK/raw.tsv" | sort | uniq -c | sort -rn)

# Build a display label for use in section headers
AUTHOR_LABEL="$AUTHOR_FULL_NAME <$AUTHOR_EMAIL>"

# ── Check for empty results ──────────────────────────────────────────
N_AD=$(wc -l < "$WORK/ad.tsv")
N_CD=$(wc -l < "$WORK/cd.tsv")
N_UNION=$(wc -l < "$WORK/union.tsv")

if [[ $N_UNION -eq 0 ]]; then
  echo
  echo "⚠  No commits found for '$AUTHOR' in $SINCE → $UNTIL."
  echo "   Checked all branches. Verify the author name/email."
  echo
  echo "   Known authors in this repository:"
  git log --all --pretty=format:"     %aN <%aE>" | sort -u | head -20
  exit 0
fi

###############################################################################
# 1. SUMMARY
###############################################################################
section "1. SUMMARY"

TOTAL_DAYS=$(( ($(date -d "$UNTIL" +%s) - $(date -d "$SINCE" +%s)) / 86400 + 1 ))

# Count working days (Mon-Fri)
WORK_DAYS=0
cur="$SINCE"
while [[ ! "$cur" > "$UNTIL" ]]; do
  if [[ $(date -d "$cur" +%u) -le 5 ]]; then WORK_DAYS=$((WORK_DAYS+1)); fi
  cur=$(date -d "$cur + 1 day" +%Y-%m-%d)
done

ACTIVE_AD=$(awk -F'\t' '{print substr($1,1,10)}' "$WORK/ad.tsv" | sort -u | wc -l)
ACTIVE_CD=$(awk -F'\t' '{print substr($2,1,10)}' "$WORK/cd.tsv" | sort -u | wc -l)

MERGES=$(awk -F'\t' '$5 ~ / /' "$WORK/union.tsv" | wc -l)
NON_MERGES=$((N_UNION - MERGES))

read -r TOT_F TOT_I TOT_D < <(
  awk -F'\t' '{f+=$11; i+=$12; d+=$13} END{printf "%d %d %d\n",f,i,d}' "$WORK/ad_e.tsv"
) || true

COVERAGE=$(awk "BEGIN{if($WORK_DAYS>0) printf \"%.1f%%\",$ACTIVE_AD/$WORK_DAYS*100; else print \"N/A\"}")
AVG_CPD=$(awk "BEGIN{if($ACTIVE_AD>0) printf \"%.1f\",$N_AD/$ACTIVE_AD; else print \"0\"}")

echo
printf "  %-44s %s\n" "Calendar days in range:"          "$TOTAL_DAYS"
printf "  %-44s %s\n" "Working days (Mon-Fri):"           "$WORK_DAYS"
printf "  %-44s %s\n" "Days with activity (AuthorDate):"  "$ACTIVE_AD"
printf "  %-44s %s\n" "Days with activity (CommitDate):"  "$ACTIVE_CD"
printf "  %-44s %s\n" "Coverage (active / working days):" "$COVERAGE"
echo
printf "  %-44s %s\n" "Commits by AuthorDate in range:"   "$N_AD"
printf "  %-44s %s\n" "Commits by CommitDate in range:"   "$N_CD"
printf "  %-44s %s\n" "    Merge commits:"                "$MERGES"
printf "  %-44s %s\n" "    Non-merge commits:"            "$NON_MERGES"
printf "  %-44s %s\n" "Avg commits / active day:"         "$AVG_CPD"
echo
printf "  %-44s %s\n" "Insertions / deletions:"           "+$TOT_I / -$TOT_D"
printf "  %-44s %s\n" "Net lines changed:"                "$((TOT_I - TOT_D))"
printf "  %-44s %s\n" "Total file modifications:"         "$TOT_F"

subsection "Author identity"
echo
printf "  %-30s %s\n" "Full name:"     "$AUTHOR_FULL_NAME"
printf "  %-30s %s\n" "Email:"         "$AUTHOR_EMAIL"
echo
echo "  All author identities found in commits:"
echo "$AUTHOR_IDENTITIES" | while read -r cnt ident; do
  printf "    %4s commits as  %s\n" "$cnt" "$ident"
done
echo
echo "  Committer identities (may differ after rebase/merge):"
echo "$COMMITTER_IDENTITIES" | while read -r cnt ident; do
  printf "    %4s commits as  %s\n" "$cnt" "$ident"
done

###############################################################################
# 2. DAY-BY-DAY ACTIVITY (AuthorDate)
###############################################################################
section "2. DAY-BY-DAY ACTIVITY (by AuthorDate)"

echo
echo "  AuthorDate = when the code was originally written."
echo "  This is the primary view for verifying contractor work days."
echo
echo "  ✅ active working day    ❌ inactive working day"
echo "  ⚠️  weekend activity      ·  weekend (no activity)"
echo

# Build per-day summary (from AuthorDate-enriched data)
awk -F'\t' '{
  day = substr($1,1,10)
  time = substr($1,12,5)
  n[day]++
  ins[day]+=$12; del[day]+=$13; files[day]+=$11
  if (!(day in tmin) || time < tmin[day]) tmin[day]=time
  if (!(day in tmax) || time > tmax[day]) tmax[day]=time
} END {
  for (d in n) {
    tr = (tmin[d]==tmax[d]) ? tmin[d] : tmin[d] "–" tmax[d]
    printf "%s\t%d\t%d\t%d\t%d\t%s\n", d, n[d], ins[d], del[d], files[d], tr
  }
}' "$WORK/ad_e.tsv" | sort > "$WORK/daily_ad.tsv"

cur="$SINCE"
while [[ ! "$cur" > "$UNTIL" ]]; do
  dow=$(date -d "$cur" +%u)
  dow_name=$(date -d "$cur" +%a)
  is_we=$( [[ $dow -ge 6 ]] && echo 1 || echo 0 )

  line=$(grep "^${cur}	" "$WORK/daily_ad.tsv" 2>/dev/null || true)

  if [[ -n "$line" ]]; then
    IFS=$'\t' read -r _ nc ni nd nf tr <<< "$line"
    icon=$( [[ $is_we -eq 1 ]] && echo "⚠️ " || echo "✅" )
    printf "  %s (%s)  %s  %2d commits  |  +%-6d -%-6d  |  %3d files  |  %s\n" \
      "$cur" "$dow_name" "$icon" "$nc" "$ni" "$nd" "$nf" "$tr"
  else
    if [[ $is_we -eq 1 ]]; then
      printf "  %s (%s)   ·\n" "$cur" "$dow_name"
    else
      printf "  %s (%s)  ❌  no activity\n" "$cur" "$dow_name"
    fi
  fi

  cur=$(date -d "$cur + 1 day" +%Y-%m-%d)
done

###############################################################################
# 3. DAY-BY-DAY ACTIVITY (CommitDate)
###############################################################################
section "3. DAY-BY-DAY ACTIVITY (by CommitDate)"

echo
echo "  CommitDate = when the commit was recorded in git."
echo "  Differs from AuthorDate after rebase, amend, cherry-pick, etc."
echo "  Compare with section 2 to detect history rewriting."
echo

awk -F'\t' '{
  day = substr($2,1,10)
  time = substr($2,12,5)
  n[day]++
  ins[day]+=$12; del[day]+=$13; files[day]+=$11
  if (!(day in tmin) || time < tmin[day]) tmin[day]=time
  if (!(day in tmax) || time > tmax[day]) tmax[day]=time
} END {
  for (d in n) {
    tr = (tmin[d]==tmax[d]) ? tmin[d] : tmin[d] "–" tmax[d]
    printf "%s\t%d\t%d\t%d\t%d\t%s\n", d, n[d], ins[d], del[d], files[d], tr
  }
}' "$WORK/cd_e.tsv" | sort > "$WORK/daily_cd.tsv"

cur="$SINCE"
while [[ ! "$cur" > "$UNTIL" ]]; do
  dow=$(date -d "$cur" +%u)
  dow_name=$(date -d "$cur" +%a)
  is_we=$( [[ $dow -ge 6 ]] && echo 1 || echo 0 )

  line=$(grep "^${cur}	" "$WORK/daily_cd.tsv" 2>/dev/null || true)

  if [[ -n "$line" ]]; then
    IFS=$'\t' read -r _ nc ni nd nf tr <<< "$line"
    icon=$( [[ $is_we -eq 1 ]] && echo "⚠️ " || echo "✅" )
    printf "  %s (%s)  %s  %2d commits  |  +%-6d -%-6d  |  %3d files  |  %s\n" \
      "$cur" "$dow_name" "$icon" "$nc" "$ni" "$nd" "$nf" "$tr"
  else
    if [[ $is_we -eq 1 ]]; then
      printf "  %s (%s)   ·\n" "$cur" "$dow_name"
    else
      printf "  %s (%s)  ❌  no activity\n" "$cur" "$dow_name"
    fi
  fi

  cur=$(date -d "$cur + 1 day" +%Y-%m-%d)
done

###############################################################################
# 4. COMBINED DAY-BY-DAY ACTIVITY (AuthorDate + CommitDate)
###############################################################################
section "4. COMBINED DAY-BY-DAY ACTIVITY (AuthorDate + CommitDate)"

echo
echo "  A day is marked active if ANY commit has its AuthorDate OR CommitDate"
echo "  on that day. This gives the broadest (most favorable) view of activity."
echo
echo "  Source legend:  AD = AuthorDate only  CD = CommitDate only  AD+CD = both"
echo
echo "  ✅ active working day    ❌ inactive working day"
echo "  ⚠️  weekend activity      ·  weekend (no activity)"
echo

# Build per-day summary from AuthorDate
awk -F'\t' '{
  day = substr($1,1,10)
  n[day]++; ins[day]+=$12; del[day]+=$13; files[day]+=$11
}' "$WORK/ad_e.tsv"

# Build per-day summary from CommitDate
awk -F'\t' '{
  day = substr($2,1,10)
  n[day]++; ins[day]+=$12; del[day]+=$13; files[day]+=$11
}' "$WORK/cd_e.tsv"

# Build combined per-day data using awk on both files
awk -F'\t' -v s="$SINCE" -v u="$UNTIL" '
  FILENAME==ARGV[1] {
    day = substr($1,1,10)
    if (day>=s && day<=u) { ad_n[day]++; ad_ins[day]+=$12; ad_del[day]+=$13; ad_f[day]+=$11 }
  }
  FILENAME==ARGV[2] {
    day = substr($2,1,10)
    if (day>=s && day<=u) { cd_n[day]++; cd_ins[day]+=$12; cd_del[day]+=$13; cd_f[day]+=$11 }
  }
  END {
    for (d in ad_n) days[d]=1
    for (d in cd_n) days[d]=1
    for (d in days) {
      an = ad_n[d]+0; cn = cd_n[d]+0
      if (an>0 && cn>0) src = "AD+CD"
      else if (an>0)    src = "AD"
      else              src = "CD"
      # Use max of AD/CD for stats (avoid double-counting)
      ti = (ad_ins[d]+0 > cd_ins[d]+0) ? ad_ins[d]+0 : cd_ins[d]+0
      td = (ad_del[d]+0 > cd_del[d]+0) ? ad_del[d]+0 : cd_del[d]+0
      tf = (ad_f[d]+0 > cd_f[d]+0) ? ad_f[d]+0 : cd_f[d]+0
      tn = (an > cn) ? an : cn
      printf "%s\t%d\t%d\t%d\t%d\t%s\n", d, tn, ti, td, tf, src
    }
  }
' "$WORK/ad_e.tsv" "$WORK/cd_e.tsv" | sort > "$WORK/daily_combined.tsv"

ACTIVE_COMBINED=$(wc -l < "$WORK/daily_combined.tsv")
COVERAGE_COMBINED=$(awk "BEGIN{if($WORK_DAYS>0) printf \"%.1f%%\",$ACTIVE_COMBINED/$WORK_DAYS*100; else print \"N/A\"}")

echo "  Combined active days: $ACTIVE_COMBINED / $WORK_DAYS working days ($COVERAGE_COMBINED)"
echo "  (vs AuthorDate only: $ACTIVE_AD days, CommitDate only: $ACTIVE_CD days)"
echo

cur="$SINCE"
while [[ ! "$cur" > "$UNTIL" ]]; do
  dow=$(date -d "$cur" +%u)
  dow_name=$(date -d "$cur" +%a)
  is_we=$( [[ $dow -ge 6 ]] && echo 1 || echo 0 )

  line=$(grep "^${cur}	" "$WORK/daily_combined.tsv" 2>/dev/null || true)

  if [[ -n "$line" ]]; then
    IFS=$'\t' read -r _ nc ni nd nf src <<< "$line"
    icon=$( [[ $is_we -eq 1 ]] && echo "⚠️ " || echo "✅" )
    printf "  %s (%s)  %s  %2d commits  |  +%-6d -%-6d  |  %3d files  |  %-5s\n" \
      "$cur" "$dow_name" "$icon" "$nc" "$ni" "$nd" "$nf" "$src"
  else
    if [[ $is_we -eq 1 ]]; then
      printf "  %s (%s)   ·\n" "$cur" "$dow_name"
    else
      printf "  %s (%s)  ❌  no activity\n" "$cur" "$dow_name"
    fi
  fi

  cur=$(date -d "$cur + 1 day" +%Y-%m-%d)
done

###############################################################################
# 5. AUTHORDATE vs COMMITDATE DISCREPANCY
###############################################################################
section "5. AUTHORDATE vs COMMITDATE DISCREPANCY"

echo
echo "  Commits where AuthorDate ≠ CommitDate indicate history rewriting:"
echo "    • interactive rebase (git rebase -i)"
echo "    • commit amend (git commit --amend)"
echo "    • cherry-pick (git cherry-pick)"
echo "    • format-patch / am"
echo
echo "  A large delta or date on a different day is a red flag."
echo

awk -F'\t' '
function iso_epoch(s,  y,m,d,h,mi,se,sgn,tzh,tzm,jdn) {
  y=substr(s,1,4)+0; m=substr(s,6,2)+0; d=substr(s,9,2)+0
  h=substr(s,12,2)+0; mi=substr(s,15,2)+0; se=substr(s,18,2)+0
  sgn=substr(s,20,1); tzh=substr(s,21,2)+0; tzm=substr(s,24,2)+0
  if (m<=2) { y--; m+=12 }
  jdn = int(365.25*(y+4716)) + int(30.6001*(m+1)) + d - 1524
  epoch = (jdn-2440588)*86400 + h*3600 + mi*60 + se
  if (sgn=="-") epoch += tzh*3600+tzm*60; else epoch -= tzh*3600+tzm*60
  return epoch
}
{
  ae = iso_epoch($1); ce = iso_epoch($2)
  delta = ce - ae; if (delta<0) delta = -delta
  if (delta > 60) {
    dd = int(delta/86400)
    hh = int((delta%86400)/3600)
    mm = int((delta%3600)/60)
    if (dd>0) ds = dd "d " hh "h"
    else if (hh>0) ds = hh "h " mm "m"
    else ds = mm "m"
    # Flag if AuthorDate and CommitDate are on different calendar days
    ad_day = substr($1,1,10); cd_day = substr($2,1,10)
    flag = (ad_day != cd_day) ? " ⚠️" : ""
    printf "  %s  AD: %s %s  CD: %s %s  Δ %-10s %s%s\n", \
      $3, ad_day, substr($1,12,5), cd_day, substr($2,12,5), ds, $8, flag
    count++
  }
}
END {
  if (count+0 == 0)
    print "  ✅ No discrepancies found — all AuthorDate ≈ CommitDate."
  else
    printf "\n  Total: %d commits with AuthorDate ≠ CommitDate\n", count
}' "$WORK/union_e.tsv"

###############################################################################
# 6. CROSS-RANGE COMMITS
###############################################################################
section "6. CROSS-RANGE COMMITS"

echo
echo "  Commits where only one date (AuthorDate or CommitDate) falls within"
echo "  the audit period. These reveal code flow across the period boundary."
echo

# A) AuthorDate IN range, CommitDate OUTSIDE → written during period, committed later
subsection "6a. Authored in range, committed OUTSIDE range"
echo "  (Code written during the audit period but rebased/amended/committed later)"
echo
awk -F'\t' -v s="$SINCE" -v u="$UNTIL" '
  substr($1,1,10)>=s && substr($1,1,10)<=u &&
  !(substr($2,1,10)>=s && substr($2,1,10)<=u) {
    printf "  %s  AD: %s %s  CD: %s %s  %s\n", \
      $3, substr($1,1,10), substr($1,12,5), substr($2,1,10), substr($2,12,5), $8
    count++
  }
  END {
    if (count+0==0) print "  None."
    else printf "\n  Total: %d commits\n", count
  }
' "$WORK/union_e.tsv"

# B) CommitDate IN range, AuthorDate OUTSIDE → written outside period, committed during it
subsection "6b. Committed in range, authored OUTSIDE range"
echo "  (Code NOT written during the audit period, but recorded via rebase/"
echo "   cherry-pick/amend as if it were — potential red flag)"
echo
awk -F'\t' -v s="$SINCE" -v u="$UNTIL" '
  !(substr($1,1,10)>=s && substr($1,1,10)<=u) &&
  substr($2,1,10)>=s && substr($2,1,10)<=u {
    printf "  %s  AD: %s %s  CD: %s %s  %s\n", \
      $3, substr($1,1,10), substr($1,12,5), substr($2,1,10), substr($2,12,5), $8
    count++
  }
  END {
    if (count+0==0) print "  None."
    else printf "\n  Total: %d commits\n", count
  }
' "$WORK/union_e.tsv"

###############################################################################
# 7. HOURLY ACTIVITY HEATMAP (AuthorDate)
###############################################################################
section "7. HOURLY ACTIVITY HEATMAP (AuthorDate)"

echo
echo "  Distribution of commits by hour of day (author's local time)."
echo

MAX_H=$(awk -F'\t' '
  { h=substr($1,12,2)+0; c[h]++ }
  END { m=0; for(h in c) if(c[h]>m) m=c[h]; print m }
' "$WORK/ad.tsv")

awk -F'\t' -v maxc="$MAX_H" '
  { h=substr($1,12,2)+0; c[h]++ }
  END {
    bw = 40
    for (h=0; h<24; h++) {
      n = c[h]+0
      len = (maxc>0) ? int(n*bw/maxc + 0.5) : 0
      bar = ""
      for (i=0; i<len; i++) bar = bar "█"
      printf "  %02d:00  %4d  %s\n", h, n, bar
    }
  }
' "$WORK/ad.tsv"

###############################################################################
# 8. WEEKEND & OFF-HOURS ACTIVITY
###############################################################################
section "8. WEEKEND & OFF-HOURS ACTIVITY"

echo
echo "  Commits outside typical working hours (before 08:00 or after 20:00)"
echo "  or on weekends (Saturday / Sunday)."
echo

# Pre-compute day-of-week for each active date
awk -F'\t' '{print substr($1,1,10)}' "$WORK/ad.tsv" | sort -u > "$WORK/dates.txt"

while IFS= read -r dt; do
  printf "%s\t%s\n" "$dt" "$(date -d "$dt" +%u)"
done < "$WORK/dates.txt" > "$WORK/dow.tsv"

awk -F'\t' '
  NR==FNR { dow[$1]=$2; next }
  {
    d = substr($1,1,10)
    h = substr($1,12,2)+0
    is_we = (dow[d] >= 6)
    is_off = (h < 8 || h >= 20)
    if (is_we || is_off) {
      tag = ""
      if (is_we)  tag = "WEEKEND"
      if (is_off) { if (tag!="") tag = tag "+"; tag = tag "OFF-HOURS" }
      printf "  %s %s  %s  [%-20s]  %s\n", d, substr($1,12,5), $3, tag, $8
      count++
    }
  }
  END {
    if (count+0 == 0) print "  ✅ No commits outside normal working hours."
    else printf "\n  Total: %d commits outside normal hours\n", count
  }
' "$WORK/dow.tsv" "$WORK/ad.tsv"

###############################################################################
# 9. MERGE COMMITS
###############################################################################
section "9. MERGE COMMITS"

echo
if [[ $MERGES -eq 0 ]]; then
  echo "  No merge commits in the audit period."
else
  printf "  %-10s  %-12s %-7s  %-12s %-7s  %s\n" \
    "Hash" "AuthorDate" "" "CommitDate" "" "Subject"
  echo "  $SUB"
  awk -F'\t' '$5 ~ / / {
    printf "  %-10s  %s %s  %s %s  %s\n", \
      $3, substr($1,1,10), substr($1,12,5), \
      substr($2,1,10), substr($2,12,5), $8
  }' "$WORK/union_e.tsv"
  echo
  printf "  Total: %d merge commits\n" "$MERGES"
fi

###############################################################################
# 10. BRANCH ACTIVITY
###############################################################################
section "10. BRANCH ACTIVITY"

echo
echo "  Branches containing commits by this author in the audit period."
echo "  (Source ref = the branch/tag that led git log to discover the commit)"
echo

# Join source refs with hashes in range
awk -F'\t' '{print $4}' "$WORK/ad.tsv" | sort -u > "$WORK/hashes_ad.txt"

awk -F'\t' '
  NR==FNR { want[$1]=1; next }
  ($1 in want) { src[$2]++ }
  END {
    for (s in src) printf "  %-60s %4d commits\n", s, src[s]
  }
' "$WORK/hashes_ad.txt" "$WORK/sources.tsv" | sort -t$'\t' -k2 -rn

###############################################################################
# 11. TOP FILES MODIFIED
###############################################################################
section "11. TOP 30 FILES MODIFIED"

echo
git log --all \
  --author="$AUTHOR" \
  --since="$BUF_S" --until="$BUF_U" \
  --pretty=format:"__COMMIT__%x09%H" \
  --name-only 2>/dev/null \
| awk -F'\t' -v s="$SINCE" -v u="$UNTIL" '
  /^__COMMIT__\t/ { hash=$2; next }
  NF>=1 && $0!="" { files[hash][$0]=1 }
' > /dev/null 2>&1 || true

# Simpler approach: collect all file names from commits in range
{
  while IFS=$'\t' read -r _ _ _ fullhash _ _ _ _; do
    git diff-tree --no-commit-id --name-only -r "$fullhash" 2>/dev/null
  done < "$WORK/ad.tsv"
} | sort | uniq -c | sort -rn | head -30 | while read -r count fname; do
  printf "  %4d  %s\n" "$count" "$fname"
done

###############################################################################
# 12. DETAILED COMMIT LOG
###############################################################################
section "12. DETAILED COMMIT LOG (by AuthorDate)"

echo
printf "  %-10s  %-12s %-7s  %-12s %-7s  %6s  %6s  %s\n" \
  "Hash" "AuthorDate" "" "CommitDate" "" "+lines" "-lines" "Subject"
echo "  $SUB"

awk -F'\t' '{
  printf "  %-10s  %s %s  %s %s  %+6d  %+6d  %s\n", \
    $3, substr($1,1,10), substr($1,12,5), \
    substr($2,1,10), substr($2,12,5), \
    $12, $13, $8
}' "$WORK/ad_e.tsv"

###############################################################################
# 13. INACTIVE DAYS SUMMARY
###############################################################################
section "13. INACTIVE WORKING DAYS"

echo
echo "  Working days (Mon–Fri) with NO commits by AuthorDate AND no commits"
echo "  by CommitDate. This is the most favorable view (combined coverage)."
echo

# Combine active days from both AuthorDate and CommitDate
{
  awk -F'\t' '{print substr($1,1,10)}' "$WORK/ad.tsv"
  awk -F'\t' '{print substr($2,1,10)}' "$WORK/cd.tsv"
} | sort -u > "$WORK/active_combined.txt"

INACTIVE_COUNT=0
cur="$SINCE"
while [[ ! "$cur" > "$UNTIL" ]]; do
  dow=$(date -d "$cur" +%u)
  if [[ $dow -le 5 ]]; then
    if ! grep -qx "$cur" "$WORK/active_combined.txt" 2>/dev/null; then
      printf "  %s (%s)\n" "$cur" "$(date -d "$cur" +%a)"
      INACTIVE_COUNT=$((INACTIVE_COUNT+1))
    fi
  fi
  cur=$(date -d "$cur + 1 day" +%Y-%m-%d)
done

echo
if [[ $INACTIVE_COUNT -eq 0 ]]; then
  echo "  ✅ Activity on every working day in the range."
else
  printf "  Total: %d inactive working days out of %d\n" "$INACTIVE_COUNT" "$WORK_DAYS"
fi

###############################################################################
# Footer
###############################################################################
echo
echo "$SEP"
echo "  END OF AUDIT REPORT"
echo "$SEP"
