# 🔍 git-audit

[![Bash](https://img.shields.io/badge/language-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Linux-blue?logo=linux&logoColor=white)]()
[![Git](https://img.shields.io/badge/requires-Git-F05032?logo=git&logoColor=white)](https://git-scm.com/)
[![ShellCheck](https://img.shields.io/badge/linted%20with-ShellCheck-brightgreen)](https://www.shellcheck.net/)

**A comprehensive Git activity audit tool for contractor and team member verification.**

Generates a detailed day-by-day report of a contributor's activity across all branches of a repository, using both `AuthorDate` and `CommitDate` to provide the most complete picture — including detection of rebases, amends, cherry-picks, and other history rewrites.

---

## Why?

When working with external contractors or distributed teams, you often need to verify that work was actually performed on specific days. Git history is the source of truth, but raw `git log` doesn't give you easy-to-read daily coverage reports.

**git-audit** does the heavy lifting: it analyzes every branch, cross-references AuthorDate and CommitDate, and produces a structured report you can screenshot, share, or archive.

---

## Features

| Section | What it shows |
|---|---|
| **Summary** | Total commits, active days, coverage ratio, lines added/removed, author identities |
| **Day-by-day (AuthorDate)** | Calendar view of when code was *written*, with commit counts, line stats, time ranges |
| **Day-by-day (CommitDate)** | Calendar view of when code was *recorded in git* (post-rebase/amend) |
| **Combined day-by-day** | Union of both dates — the most favorable coverage view |
| **AuthorDate vs CommitDate discrepancy** | Detects history rewriting (rebase, amend, cherry-pick) with time deltas |
| **Cross-range commits** | Commits where only one date falls within the audit period |
| **Hourly heatmap** | Visual bar chart of commit distribution by hour of day |
| **Weekend & off-hours** | Flags commits outside 08:00–20:00 or on weekends |
| **Merge commits** | Lists all merge commits with both dates |
| **Branch activity** | Which branches the author contributed to |
| **Top files modified** | Top 30 most frequently changed files |
| **Detailed commit log** | Full commit list with both dates, insertions, deletions |
| **Inactive working days** | Lists every Mon–Fri with zero activity (combined AD+CD) |

### Key design choices

- **All branches scanned** — not just `main` or `HEAD`
- **AuthorDate vs CommitDate distinction** — critical for audit accuracy
- **90-day buffer** on git queries to catch commits authored inside the period but committed outside (and vice-versa)
- **Author identity resolution** — resolves the actual name/email from commits, displays in every section header for screenshot-friendliness
- **Committer identity tracking** — shows who actually pushed/merged the commits (may differ from author)

---

## Requirements

- **Bash** 4.0+
- **Git** 2.x+
- **GNU coreutils** (`date -d`, `awk`, `sort`, `uniq`, `wc`, `grep`, `mktemp`)
- **Linux** (uses GNU `date` syntax — not compatible with macOS `date` out of the box)

---

## Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/git-audit.git

# Make the script executable
chmod +x git-audit/git-audit.sh

# Optionally, add to your PATH
sudo ln -s "$(pwd)/git-audit/git-audit.sh" /usr/local/bin/git-audit
```

---

## Usage

```bash
# Run from inside any git repository
cd /path/to/your/repo
git-audit.sh "Author Name or Email" YYYY-MM-DD YYYY-MM-DD
```

### Examples

```bash
# Audit by email
./git-audit.sh "john.doe@company.com" 2025-01-01 2025-03-31

# Audit by name (partial match)
./git-audit.sh "John Doe" 2025-01-01 2025-03-31

# Save report to file
./git-audit.sh "john@company.com" 2025-01-01 2025-06-30 > audit-report.txt
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `Author` | ✅ | Name or email (partial match, same as `git log --author`) |
| `SINCE` | ✅ | Start date (inclusive), format `YYYY-MM-DD` |
| `UNTIL` | ✅ | End date (inclusive), format `YYYY-MM-DD` |

---

## Sample Output

```
════════════════════════════════════════════════════════════════════════
  GIT AUDIT REPORT
════════════════════════════════════════════════════════════════════════
  Search filter:                 john.doe@company.com
  Period:                        2025-11-04  →  2026-01-01
  Repository:                    my-project
  Report generated:              2026-03-12 11:50:58 CET
════════════════════════════════════════════════════════════════════════

════════════════════════════════════════════════════════════════════════
  1. SUMMARY
  Author: John Doe <john.doe@company.com>  |  2025-11-04 → 2026-01-01  |  my-project
════════════════════════════════════════════════════════════════════════

  Calendar days in range:                      59
  Working days (Mon–Fri):                      43
  Days with activity (AuthorDate):             13
  Days with activity (CommitDate):             15
  Coverage (active / working days):            30.2%

  Commits by AuthorDate in range:              19
  Commits by CommitDate in range:              20
    ├─ Merge commits:                          0
    └─ Non-merge commits:                      20
  Avg commits / active day:                    1.5

════════════════════════════════════════════════════════════════════════
  2. DAY-BY-DAY ACTIVITY (by AuthorDate)
  Author: John Doe <john.doe@company.com>  |  2025-11-04 → 2026-01-01  |  my-project
════════════════════════════════════════════════════════════════════════

  2025-11-12 (Wed)  ✅   3 commits  |  +1217   -342     |   57 files  |  09:14–16:12
  2025-11-13 (Thu)  ❌  no activity
  2025-11-14 (Fri)  ❌  no activity
  2025-11-15 (Sat)   ·
  2025-11-16 (Sun)   ·
  2025-11-17 (Mon)  ✅   1 commits  |  +61     -14      |    7 files  |  11:06
```

Every section header includes the **author name, email, date range, and repository** — so any screenshot is self-contained.

---

## Understanding AuthorDate vs CommitDate

| Concept | Meaning | Changes when... |
|---------|---------|-----------------|
| **AuthorDate** | When the code was originally written | Never (unless `--date` is used) |
| **CommitDate** | When the commit was recorded in git | `git rebase`, `git commit --amend`, `git cherry-pick`, `git format-patch` / `git am` |

The audit report highlights discrepancies between the two dates, which is essential for detecting:
- Code claimed to be written on a specific day but actually rebased later
- Bulk commits pushed on a different day than when work was done
- Cherry-picks from other branches or repositories

---

## Tips

- **Redirect to a file** for archival: `./git-audit.sh "..." 2025-01-01 2025-12-31 > report.txt`
- **Compare AuthorDate vs CommitDate views** (sections 2 & 3) to detect potential timeline manipulation
- **Check section 5** (discrepancy) for commits where the delta is suspiciously large
- **Section 4** (combined) gives the most favorable view — best starting point for contractor evaluation
- **Section 13** lists inactive working days using the combined view — whatever remains truly has no activity

---

## License

[MIT](LICENSE)

---

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

---

*Built for teams that need transparency and accountability in their development process.*
