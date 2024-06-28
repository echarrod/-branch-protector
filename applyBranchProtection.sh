#!/usr/bin/env bash

##   Fixes rules with pattern match name on github, such as release-*
##Parameters:
##    branch_pattern_list (csv in quotes):  "main,dev,release-*"
##    repo name filter - regex to apply to the repo names: "lib-.*|that repo|attempt[0-9]"
##   list only - if script should generate list of filtered repos and exit:   --filter
##  examples:
##     $0 '' '' --list;   #Gets a list of all repos in the org.
##     $0 '' 'lib-.*' --list |xargs |tr ' ' '|';     #Creates a filter with all repos that match 'lib-.*'
##     $0 'main';  #Updates all main branch rules in the org
##     $0 'main' 'lib-' ;#Updates all main branch rules on the repos matching 'lib-'

OWNER=luno   # Set your org name here
LIMIT=250                # Set this to some number higher than the number of repos you have
BRANCH_PATTERN_LIST=${1:-"main,master"}; shift  # Either pass in a comma-delimited list of branches to protect or use the defaults
FILTER=${1:""}; shift    # Pass a filter to select some of the repos. To be used as a regex: 'REPO[0-9]+|LIB-(a|b)'
LIST_ONLY=$1; shift       # Set to anything as a 3rd parameter to list the repos only. "" '<filter>' --list

if [ -n "$LIST_ONLY" ];then
   gh repo list "$OWNER" --no-archived --json name,id --limit $LIMIT |jq -r '.[].name | select( .? | match ("'"${FILTER}"'"))';# Change this gh query if so desired
   exit 0;
fi

IFS=',' read -ra BRANCH_PATTERNS <<< "$BRANCH_PATTERN_LIST"
for BRANCH_PATTERN in "${BRANCH_PATTERNS[@]}"; do
while read -r REPO; do
  echo ""
  echo "Working with ${REPO}..."
  REPO_ID=$(echo "$REPO" | jq -r .node_id)     # Use .node_id for repo ID
  REPO_NAME=$(echo "$REPO" | jq -r .name)

  # Get the existing rule id, if any
  RULE_ID=$(gh api graphql -f query="
  query ($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      branchProtectionRules(first: 100) {
        nodes { # Access the nodes array directly
          id
          pattern
        }
      }
    }
  }" -f owner="$OWNER" -f repo="$REPO_NAME" | jq -r '.data.repository.branchProtectionRules.nodes[] | select( .pattern == "'"$BRANCH_PATTERN"'" ) | .id') # Use .nodes instead of .edges

  if [[ -z "$RULE_ID" ]]; then
    echo "No existing rule found for pattern '$BRANCH_PATTERN'. Creating a new one..."

    # Create a new rule since none exists
    gh api graphql -f query="
      mutation($repositoryId:ID!, $branchPattern:String!) {
        createBranchProtectionRule(input: {
          repositoryId: $repositoryId
          pattern: $branchPattern
          allowsForcePushes: false
          dismissesStaleReviews: false
          isAdminEnforced: false
          requireLastPushApproval: true
          requiresApprovingReviews: true
          requiredApprovingReviewCount: 1
          requiresConversationResolution: true
          requiresLinearHistory: true
          requiresStatusChecks: true
        }) {
          branchProtectionRule {
            id # Retrieve the ID of the created rule
          }
        }
      }" -f repositoryId="$REPO_ID" -f branchPattern="$BRANCH_PATTERN"

  else
    echo "Updating existing rule with ID '$RULE_ID'..."

    # Update the existing rule
    gh api graphql -f query="
      mutation($branchProtectionRuleId:ID!) {
        updateBranchProtectionRule(input: {
          branchProtectionRuleId: $branchProtectionRuleId
          allowsForcePushes: false
          dismissesStaleReviews: false
          isAdminEnforced: false
          requireLastPushApproval: true
          requiresApprovingReviews: true
          requiredApprovingReviewCount: 1
          requiresConversationResolution: true
          requiresLinearHistory: true
          requiresStatusChecks: true
        }) {
          branchProtectionRule {
            id
          }
        }
      }" -f branchProtectionRuleId="$RULE_ID"
  fi

done <<< "$(gh repo list "$OWNER" --no-archived --json name,node_id --limit $LIMIT | jq -c '.[] | select( .name? | match ("'"${FILTER}"'"))')" # Use .node_id instead of .id
done