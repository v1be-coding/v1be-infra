#!/usr/bin/env bash
# ci/test-functions.sh
# Tests each CloudFront Function's DEVELOPMENT stage with TestFunction, then
# publishes it to LIVE only if every test passed. Terraform writes DEVELOPMENT
# only (publish = false), so a function that fails here never serves traffic.
# A Node test isn't enough: for-of passed one, then 503'd every page under
# runtime 2.0 (#42, #45).
# Usage: test-functions.sh [--no-publish]. Runs in every account the edge stack
# writes functions to, through the AWS profiles deploy.yml sets up.
set -euo pipefail

publish=1
[ "${1:-}" = --no-publish ] && publish=0
export AWS_REGION=us-east-1 # CloudFront is global, but the CLI wants a region.
profiles=(portfolio cafe) # stacks/edge/main.tf has one module per account.
functions=(v1be-origin-check v1be-origin-check-pages v1be-pages)
failed=0

event() { # uri, querystring JSON
  jq -nc --arg uri "$1" --argjson qs "$2" '{
    version: "1.0",
    context: {eventType: "viewer-request"},
    viewer: {ip: "198.51.100.1"},
    request: {method: "GET", uri: $uri, querystring: $qs, headers: {}, cookies: {}}
  }'
}

# check function etag label uri querystring jq-filter: runs one event and needs
# the filter to print true against the function's output.
check() {
  local name=$1 etag=$2 label="$AWS_PROFILE, $1, $3" file result error output
  file=$(mktemp)
  event "$4" "$5" > "$file"
  if ! result=$(aws cloudfront test-function --name "$name" --if-match "$etag" \
    --stage DEVELOPMENT --event-object "fileb://$file" --output json); then
    echo "::error::$label: TestFunction failed"
    failed=1; return
  fi
  error=$(jq -r '.TestResult.FunctionErrorMessage // empty' <<< "$result")
  output=$(jq -r '.TestResult.FunctionOutput // empty' <<< "$result")
  if [ -n "$error" ]; then
    echo "::error::$label: $error"
    failed=1
  elif ! jq -e "$6" <<< "$output" > /dev/null 2>&1; then
    echo "::error::$label: unexpected output: $output"
    failed=1
  else
    echo "ok  $label"
  fi
}

etag_of() {
  aws cloudfront describe-function --name "$1" --stage DEVELOPMENT --query ETag --output text
}

none='{}'
multi='{"a":{"value":"1"},"b":{"value":"2","multiValue":[{"value":"2"},{"value":"3"}]}}'
# for-in doesn't keep the query's order, so compare the parameters sorted.
# shellcheck disable=SC2016 # $path and $query are jq variables.
redirect='.response.statusCode == 301
  and (.response.headers.location.value | split("?")) as [$path, $query]
  | $path == "/about" and ($query | split("&") | sort) == ["a=1", "b=2", "b=3"]'

for AWS_PROFILE in "${profiles[@]}"; do
  export AWS_PROFILE

  # No origin header, as from outside Cloudflare. The handler still reads the
  # store, so this runs every line before the check.
  for name in v1be-origin-check v1be-origin-check-pages; do
    etag=$(etag_of "$name")
    check "$name" "$etag" "no origin header gets 403" / "$none" '.response.statusCode == 403'
  done

  # The clean-URL rewrite, the same as origin-check-pages's after the check.
  name=v1be-pages
  etag=$(etag_of "$name")
  check "$name" "$etag" "trailing slash redirects, query kept" /about/ "$multi" "$redirect"
  check "$name" "$etag" "folder reads its index.html" /about "$none" '.request.uri == "/about/index.html"'
  check "$name" "$etag" "file with a dot is unchanged" /app.js "$none" '.request.uri == "/app.js"'
  check "$name" "$etag" "root is unchanged" / "$none" '.request.uri == "/"'
done

if [ "$failed" = 1 ]; then
  echo "::error::A CloudFront Function failed its test. LIVE still runs the last published code."
  exit 1
fi
[ "$publish" = 1 ] || exit 0

for AWS_PROFILE in "${profiles[@]}"; do
  export AWS_PROFILE
  for name in "${functions[@]}"; do
    aws cloudfront publish-function --name "$name" --if-match "$(etag_of "$name")" \
      --query FunctionSummary.Status --output text > /dev/null
    echo "published $AWS_PROFILE, $name"
  done
done
