#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

# Globals

if [[ "$#" -ne 3 ]]; then
  echo "Usage: create-gca-branch.sh <branch1> <branch2> <new-branch-name>"
  echo ""
  echo "Creates a new branch of the gca between branch1 and branch2. "
  echo ""
  exit 0
fi

BRANCH1=$1
BRANCH2=$2
NEW_BRANCH=$3
gca_commit=$(git show $(git rev-list ${BRANCH1} ^${BRANCH2} --first-parent --topo-order | tail -1)^ | head -1 | awk '{print $2}')
echo "Checking out branch at ${gca_commit}"
git log ${gca_commit}
git checkout -b ${NEW_BRANCH} ${gca_commit}
