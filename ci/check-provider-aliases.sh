#!/usr/bin/env bash
# ci/check-provider-aliases.sh
# In a stack whose every aws provider has an alias, an aws_* block with no
# provider = falls back to an empty default provider. validate passes; plan fails
# (v1be-infra #27, fixed in #28). Reads files as text. Never runs terraform.
# Usage: check-provider-aliases.sh <stacks folder>
set -u
fail=0
for stack in "$1"/*/; do
  files=("$stack"*.tf)
  [ -e "${files[0]}" ] || continue
  # Skip a stack with a default (unaliased) aws provider.
  awk '/^provider "aws"/{p=1; a=0; next} p&&/^[[:space:]]*alias[[:space:]]*=/{a=1} p&&/^}/{if(!a) d=1; p=0} END{exit d?0:1}' "${files[@]}" && continue
  grep -q '^provider "aws"' "${files[@]}" || continue
  out=$(awk '
    function flush() { if (want != "" && !found) printf "::error file=%s,line=%d::%s has no %s = in a stack whose aws providers all have an alias\n", fname, start, name, want }
    FNR == 1 { want = "" }
    want == "" && /^(resource|data) "aws_/ { want = "provider"; found = 0; depth = 0; start = FNR; fname = FILENAME; name = $1 " " $2 " " $3 }
    want == "" && /^module "/ { want = "providers"; found = 0; depth = 0; start = FNR; fname = FILENAME; name = $1 " " $2 }
    want != "" {
      if (depth == 1 && $0 ~ "^[[:space:]]*" want "[[:space:]]*=") found = 1
      line = $0; o = gsub(/\{/, "", line); line = $0; c = gsub(/\}/, "", line); depth += o - c
      if (depth <= 0) { flush(); want = "" }
    }
  ' "${files[@]}")
  if [ -n "$out" ]; then echo "$out"; fail=1; fi
done
[ "$fail" = 0 ] && echo "Every aws block names its provider."
exit "$fail"
