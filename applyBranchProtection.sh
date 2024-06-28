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

OWNER=Your_Org_Name   # Set your org name here
LIMIT=250                # Set this to some number higher than the number of repos you have
BRANCH_PATTERN_LIST=${1:-"dev,stg,main,master"}; shift  # Either pass in a comma-delimited list of branches to protect or use the defaults
FILTER=${1:""}; shift    # Pass a filter to select some of the repos. To be used as a regex: 'REPO[0-9]+|LIB-(a|b)'
LISTONLY=$1; shift       # Set to anything as a 3rd parameter to list the repos only. "" '<filter>' --list

if [ -n "$LISTONLY" ];then
   gh repo list "$OWNER" --no-archived --json name,id --limit $LIMIT |jq -r '.[].name | select( .? | match ("'"${FILTER}"'"))';# Change this gh query if so desired
   exit 0;
fi

IFS=',' read -ra BRANCH_PATTERNS <<< "$BRANCH_PATTERN_LIST"
for BRANCH_PATTERN in "${BRANCH_PATTERNS[@]}"; do
  while read -r REPO; do
    echo ""
    echo "Working with ${REPO}..."
    REPO_ID=$(echo "$REPO" | jq -r .id)
    REPO_NAME=$(echo "$REPO" | jq -r .name)
    # Get the existing rule id, if any
    RULE_ID=$(gh api graphql -f query='
    query ($owner: String!, $repo: String!) {
      repository(name: $repo, owner: $owner) {
        branchProtectionRules (first: 100) {
          edges {
            node {
              id
              pattern
            }
          }
        }
      }
    }' -f owner="$OWNER" -f repo="$REPO_NAME" | jq '.data.repository.branchProtectionRules.edges.[] | select( .node.pattern == "'"${BRANCH_PATTERN}"'") | .node.id ');

    echo "RULE_ID: ${RULE_ID}";
    if [[ "$RULE_ID" == "null" ]]; then
      # If a rule does not exist, create one. Make sure to set the rules you want from https://docs.github.com/en/graphql/reference/objects#branchprotectionrule
      gh api graphql -f query='
        mutation($repositoryId:ID!, $branchPattern:String!) {
          createBranchProtectionRule(input: {
            repositoryId: $repositoryId
            pattern: $branchPattern
            allowsForcePushes: false
            dismissesStaleReviews: true
            isAdminEnforced: false
            requireLastPushApproval: true
            requiresApprovingReviews: true
            requiredApprovingReviewCount: 1
            requiresConversationResolution: true
            requiresLinearHistory: true
            requiresStatusChecks: true
          }) { clientMutationId }
        }' -f repositoryId="$REPO_ID" -f branchPattern="$BRANCH_PATTERN";
    else
      # If a rule already exists, update it. Make sure to set the rules you want from https://docs.github.com/en/graphql/reference/objects#branchprotectionrule
      gh api graphql -f query='
        mutation($ruleId:ID!) {
          updateBranchProtectionRule(input: {
            branchProtectionRuleId: $ruleId
            allowsForcePushes: false
            dismissesStaleReviews: true
            isAdminEnforced: false
            requireLastPushApproval: true
            requiresApprovingReviews: true
            requiredApprovingReviewCount: 1
            requiresConversationResolution: true
            requiresLinearHistory: true
            requiresStatusChecks: true
          }) { clientMutationId }
        }' -f ruleId="$RULE_ID";
    fi
  done <<< "$(gh repo list "$OWNER" --no-archived --json name,id --limit $LIMIT |jq -c '.[] | select( .name? | match ("'"${FILTER}"'"))')"; # Change this gh query if so desired
done
