#!/usr/bin/env bash
# ci/check-wizard-pathconv.sh
# Git Bash rewrites an argument that starts with / into a Windows path before
# aws.exe sees it, unless MSYS_NO_PATHCONV=1 is set for that command. #58 left it
# off two `aws ssm` calls, so their checks asked for names that don't exist
# (fixed in #60). The wizard skill wants it per command, never script-wide.
# Reads files as text. Never runs a wizard.
# Usage: check-wizard-pathconv.sh <wizards folder>
#
# An error: an aws call with no MSYS_NO_PATHCONV=1 on it that is an `aws ssm`
# call (parameter names start with /) or has an argument starting with /
# (other than /dev/null). Calls after a script-wide export are covered at run
# time, so they pass, but the export itself is a warning. A line that must keep
# such a call says why with `# pathconv-ok: <reason>` on it or the line above.
set -u
fail=0
for file in "$1"/*.sh; do
  [ -e "$file" ] || continue
  out=$(awk '
    function report(kind, line, msg) { printf "::%s file=%s,line=%d::%s\n", kind, FILENAME, line, msg }
    {
      raw = $0
      # Join backslash-continued lines, so a call split over lines is read whole.
      if (cmd == "") { start = FNR; before = prev }
      if (raw ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, " ", raw); cmd = cmd raw; prev = $0; next }
      cmd = cmd raw
      code = cmd
      sub(/(^|[[:space:]])#.*$/, "", code)
      if (code ~ /^[[:space:]]*export[[:space:]]+MSYS_NO_PATHCONV=/) {
        exported = 1
        report("warning", start, "MSYS_NO_PATHCONV is exported script-wide. The wizard skill wants it per command: script-wide it misroutes Windows curl -o /tmp/...")
      } else if (code ~ /(^|[^[:alnum:]_-])aws[[:space:]]/ && code !~ /aws[[:space:]]+configure[[:space:]]/ \
          && code !~ /MSYS_NO_PATHCONV=1[[:space:]]+aws[[:space:]]/ && !exported \
          && cmd !~ /pathconv-ok:/ && before !~ /^[[:space:]]*#[[:space:]]*pathconv-ok:/) {
        args = code
        gsub(/\/dev\/null/, "", args)
        if (code ~ /aws[[:space:]]+ssm[[:space:]]/)
          report("error", start, "aws ssm call with no MSYS_NO_PATHCONV=1 on it, so Git Bash rewrites its /-led parameter names")
        else if (args ~ /[[:space:]=]["\047]?\/[[:alnum:]_.$-]/)
          report("error", start, "aws call with a /-led argument and no MSYS_NO_PATHCONV=1 on it, so Git Bash rewrites the argument")
      }
      cmd = ""; prev = $0
    }
  ' "$file")
  if [ -n "$out" ]; then
    echo "$out"
    grep -q '^::error' <<<"$out" && fail=1
  fi
done
[ "$fail" = 0 ] && echo "No wizard aws call is open to Git Bash path rewriting."
exit "$fail"
