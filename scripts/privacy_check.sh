#!/usr/bin/env bash
# Scan the repository (working tree AND full git history) for things that must never be published.
#   - e-mail addresses other than the GitHub noreply address
#   - phone-number-like strings
#   - any word listed in config/privacy_terms.txt (one per line; this file is private and git-ignored:
#     put real staff names, street names, the agency name here, on your own computer only)
# Exit code 1 if anything is found.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
bad=0
SKIP=':!scripts/privacy_check.sh :!*.lock :!dbt/seeds/staff_aliases.csv'

echo "== e-mail addresses (working tree)"
if git grep -nIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -- . $SKIP 2>/dev/null \
   | grep -vE 'noreply@(github\.com|anthropic\.com)|@example\.(com|org)|users\.noreply\.github\.com'; then bad=1; fi

echo "== phone-like numbers (working tree)"
if git grep -nIE '(\+?61|0)4[0-9]{2}[ -]?[0-9]{3}[ -]?[0-9]{3}|\+?86[ -]?1[3-9][0-9]{9}' -- . $SKIP 2>/dev/null; then bad=1; fi

if [ -f config/privacy_terms.txt ]; then
  echo "== private terms (working tree and history)"
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    if git grep -nIiFw -- "$term" -- . $SKIP 2>/dev/null; then bad=1; fi
    if git log --all --oneline -i -G "(^|[^A-Za-z])${term}([^A-Za-z]|\$)" 2>/dev/null | head -1 | grep -q .; then echo "found in git history: $term"; bad=1; fi
  done < config/privacy_terms.txt
else
  echo "(no config/privacy_terms.txt: only the generic checks ran)"
fi

echo "== commit author e-mails"
git log --all --format='%ae %ce' 2>/dev/null | sort -u | grep -vE 'noreply' && bad=1

echo "== forbidden files"
if git ls-files | grep -E '\.(xlsx|xls|dump)$|raw_private/|(^|/)reports/'; then bad=1; fi

if [ "$bad" -eq 0 ]; then echo "privacy check passed"; else echo "PRIVACY CHECK FAILED"; fi
exit $bad
