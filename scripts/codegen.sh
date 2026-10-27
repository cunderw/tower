#!/usr/bin/env bash
# Regenerate TowerAPI from graphql/schema.graphqls + graphql/operations/.
# Does NOT download the schema. The committed graphql/schema.graphqls is
# updated by hand from a server's introspection result.
#
# Note: Apollo iOS 2.3.0's `generate` subcommand always regenerates/overwrites
# schema types and operations in place — no `-f`/`--force` flag is needed (or
# exists) for that. The CLI's `-f`/`--fetch-schema` flag means something
# different: fetch the schema over the network *before* generating, which
# requires a `schemaDownload` block in apollo-codegen-config.json. We don't
# have one (the schema is updated by hand, see above), so that flag is
# intentionally omitted here — passing it fails with "Missing schema download
# configuration."
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -x "./TowerKit/apollo-ios-cli" ]]; then
  echo "error: TowerKit/apollo-ios-cli not found." >&2
  echo "Install it first with:" >&2
  echo "  cd TowerKit && swift package --allow-writing-to-package-directory --allow-network-connections all apollo-cli-install && cd .." >&2
  exit 1
fi

./TowerKit/apollo-ios-cli generate -p apollo-codegen-config.json
echo "regenerated TowerAPI"
