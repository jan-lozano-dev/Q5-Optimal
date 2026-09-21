#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_TOKEN:?PROJECT_TOKEN secret is missing}"
: "${REPO_TOKEN:?REPO_TOKEN is missing}"
: "${PROJECT_OWNER:=jan-lozano-dev}"
: "${PROJECT_NUMBER:=2}"
: "${GITHUB_REPOSITORY:=jan-lozano-dev/Q5-Optimal}"
TARGET_ISSUE="${TARGET_ISSUE:-}"

export GH_TOKEN="$PROJECT_TOKEN"

log() { printf '\n==> %s\n' "$*"; }

log "Opening Project #$PROJECT_NUMBER for $PROJECT_OWNER"
project_json=$(gh api graphql \
  -f query='query($login:String!,$number:Int!){user(login:$login){projectV2(number:$number){id title number}}}' \
  -f login="$PROJECT_OWNER" -F number="$PROJECT_NUMBER")
project_id=$(jq -r '.data.user.projectV2.id // empty' <<<"$project_json")
project_title=$(jq -r '.data.user.projectV2.title // empty' <<<"$project_json")
if [[ -z "$project_id" ]]; then
  echo "Project #$PROJECT_NUMBER not found" >&2
  exit 2
fi
echo "Project: $project_title ($project_id)"

query_fields() {
  gh api graphql \
    -f query='query($id:ID!){node(id:$id){... on ProjectV2{fields(first:100){nodes{__typename ... on ProjectV2Field{id name dataType} ... on ProjectV2SingleSelectField{id name dataType options{id name}} ... on ProjectV2IterationField{id name dataType configuration{iterations{id title startDate duration}}}}}}}}' \
    -f id="$project_id"
}

field_exists() {
  local name="$1"
  jq -e --arg n "$name" '.data.node.fields.nodes[] | select(.name==$n)' <<<"$fields_json" >/dev/null 2>&1
}

create_subject_field() {
  field_exists "Subject" && return 0
  log "Creating Subject field"
  gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Subject",dataType:SINGLE_SELECT,singleSelectOptions:[{name:"PROP",color:BLUE,description:"Projecte de Programació"},{name:"INTERNET",color:PURPLE,description:"Internet"},{name:"SODX",color:ORANGE,description:"Sistemes Operatius Distribuïts i en Xarxa"},{name:"ESIN",color:YELLOW,description:"Estructura de la Informació"},{name:"PACO",color:GREEN,description:"Paral·lelisme i Concurrència"},{name:"ADSO",color:GRAY,description:"Administració de Sistemes Operatius"},{name:"French",color:PINK,description:"French B1"},{name:"Econometrics",color:RED,description:"Advanced Econometrics & Deep Learning"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f p="$project_id" >/dev/null
}

create_priority_field() {
  field_exists "Priority" && return 0
  log "Creating Priority field"
  gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Priority",dataType:SINGLE_SELECT,singleSelectOptions:[{name:"P0",color:RED,description:"Critical / highest ROI"},{name:"P1",color:ORANGE,description:"High"},{name:"P2",color:YELLOW,description:"Normal"},{name:"P3",color:GRAY,description:"Maintenance"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f p="$project_id" >/dev/null
}

create_sprint_field() {
  field_exists "Sprint" && return 0
  log "Creating Sprint field"
  gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Sprint",dataType:SINGLE_SELECT,singleSelectOptions:[{name:"Sprint 1",color:BLUE,description:"Semester week 1"},{name:"Sprint 2",color:GREEN,description:"Semester week 2"},{name:"Sprint 3",color:YELLOW,description:"Semester week 3"},{name:"Sprint 4",color:ORANGE,description:"Semester week 4"},{name:"Sprint 5",color:PURPLE,description:"Semester week 5"},{name:"Sprint 6",color:PINK,description:"Semester week 6"},{name:"Sprint 7",color:BLUE,description:"Semester week 7"},{name:"Sprint 8",color:GREEN,description:"Semester week 8"},{name:"Sprint 9",color:YELLOW,description:"Semester week 9"},{name:"Sprint 10",color:ORANGE,description:"Semester week 10"},{name:"Sprint 11",color:PURPLE,description:"Semester week 11"},{name:"Sprint 12",color:PINK,description:"Semester week 12"},{name:"Sprint 13",color:BLUE,description:"Semester week 13"},{name:"Sprint 14",color:GREEN,description:"Semester week 14"},{name:"Sprint 15",color:YELLOW,description:"Semester week 15"},{name:"Sprint 16",color:GRAY,description:"Semester week 16"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f p="$project_id" >/dev/null
}

create_next_review_field() {
  field_exists "Next Review" && return 0
  log "Creating Next Review field"
  gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Next Review",dataType:DATE}){projectV2Field{... on ProjectV2Field{id}}}}' -f p="$project_id" >/dev/null
}

set_single() {
  local item_id="$1" field_name="$2" option_name="$3"
  local field_id option_id
  field_id=$(jq -r --arg f "$field_name" '.data.node.fields.nodes[] | select(.name==$f) | .id' <<<"$fields_json" | head -n1)
  option_id=$(jq -r --arg f "$field_name" --arg o "$option_name" '.data.node.fields.nodes[] | select(.name==$f) | .options[]? | select(.name==$o) | .id' <<<"$fields_json" | head -n1)
  if [[ -z "$field_id" || -z "$option_id" || "$field_id" == "null" || "$option_id" == "null" ]]; then
    echo "Missing project field option: $field_name=$option_name" >&2
    return 0
  fi
  gh api graphql \
    -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}' \
    -f p="$project_id" -f i="$item_id" -f f="$field_id" -f o="$option_id" >/dev/null
}

ensure_label() {
  local name="$1" color="$2" description="$3"
  GH_TOKEN="$REPO_TOKEN" gh api -X POST "repos/$GITHUB_REPOSITORY/labels" \
    -f name="$name" -f color="$color" -f description="$description" >/dev/null 2>&1 || true
}

# Full setup only for manual/push runs. Issue events skip this expensive setup.
fields_json=$(query_fields)
if [[ -z "$TARGET_ISSUE" ]]; then
  status_field_id=$(jq -r '.data.node.fields.nodes[] | select(.name=="Status") | .id' <<<"$fields_json" | head -n1)
  if [[ -z "$status_field_id" || "$status_field_id" == "null" ]]; then
    echo "Status field not found" >&2
    exit 3
  fi

  log "Configuring mastery statuses"
  gh api graphql -f query='mutation($f:ID!){updateProjectV2Field(input:{fieldId:$f,singleSelectOptions:[{name:"Backlog",color:GRAY,description:"Not selected for current sprint"},{name:"This Sprint",color:BLUE,description:"Committed outcome for current sprint"},{name:"Learning",color:YELLOW,description:"Building the mental model"},{name:"Practice",color:ORANGE,description:"Applying with exercises or code"},{name:"Retrieval",color:PURPLE,description:"Delayed closed-book retrieval"},{name:"Exam Ready",color:GREEN,description:"Passed the mastery gate under exam-like conditions"},{name:"Done",color:PINK,description:"Assessed or no longer needs maintenance"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f f="$status_field_id" >/dev/null

  fields_json=$(query_fields)
  create_subject_field
  fields_json=$(query_fields)
  create_priority_field
  fields_json=$(query_fields)
  create_sprint_field
  fields_json=$(query_fields)
  create_next_review_field
  fields_json=$(query_fields)

  log "Ensuring control labels"
  ensure_label "stage:backlog" "6e7781" "Move project item to Backlog"
  ensure_label "stage:this-sprint" "1f6feb" "Move project item to This Sprint"
  ensure_label "stage:learning" "d4c5f9" "Move project item to Learning"
  ensure_label "stage:practice" "fb8500" "Move project item to Practice"
  ensure_label "stage:retrieval" "8250df" "Move project item to Retrieval"
  ensure_label "stage:exam-ready" "2da44e" "Move project item to Exam Ready"
  ensure_label "stage:done" "bf8700" "Move project item to Done"
  for s in PROP INTERNET SODX ESIN PACO ADSO French Econometrics; do ensure_label "subject:$s" "0969da" "Subject metadata"; done
  for p in P0 P1 P2 P3; do ensure_label "priority:$p" "b60205" "Priority metadata"; done
  for t in Concept Coding Problems Lab Exam Admin; do ensure_label "type:$t" "5319e7" "Task type metadata"; done
  for s in $(seq 1 16); do ensure_label "sprint:$s" "c5def5" "Semester week / target sprint $s"; done
fi

# Issue event: sync only that issue. Push/manual run: reconcile all issues.
if [[ -n "$TARGET_ISSUE" ]]; then
  issue_numbers="$TARGET_ISSUE"
  log "Syncing changed issue #$TARGET_ISSUE"
else
  issue_numbers=$(GH_TOKEN="$REPO_TOKEN" gh api --paginate "repos/$GITHUB_REPOSITORY/issues?state=all&per_page=100" --jq '.[] | select(.pull_request == null) | .number')
  log "Reconciling all repo issues"
fi

for n in $issue_numbers; do
  issue_json=$(GH_TOKEN="$REPO_TOKEN" gh api "repos/$GITHUB_REPOSITORY/issues/$n")
  content_id=$(jq -r '.node_id' <<<"$issue_json")
  state=$(jq -r '.state' <<<"$issue_json")
  labels=$(jq -r '.labels[].name' <<<"$issue_json" 2>/dev/null || true)

  items_json=$(gh api graphql -f query='query($p:ID!){node(id:$p){... on ProjectV2{items(first:100){nodes{id content{... on Issue{id}}}}}}}' -f p="$project_id")
  item_id=$(jq -r --arg c "$content_id" '.data.node.items.nodes[] | select(.content.id==$c) | .id' <<<"$items_json" | head -n1)
  if [[ -z "$item_id" || "$item_id" == "null" ]]; then
    item_id=$(gh api graphql -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' -f p="$project_id" -f c="$content_id" --jq '.data.addProjectV2ItemById.item.id')
    echo "Added issue #$n"
  fi

  status="Backlog"
  if [[ "$state" == "closed" ]]; then status="Done"
  elif grep -Fxq "stage:exam-ready" <<<"$labels"; then status="Exam Ready"
  elif grep -Fxq "stage:retrieval" <<<"$labels"; then status="Retrieval"
  elif grep -Fxq "stage:practice" <<<"$labels"; then status="Practice"
  elif grep -Fxq "stage:learning" <<<"$labels"; then status="Learning"
  elif grep -Fxq "stage:this-sprint" <<<"$labels"; then status="This Sprint"
  elif grep -Fxq "stage:done" <<<"$labels"; then status="Done"
  fi
  set_single "$item_id" Status "$status"

  subject=$(sed -n 's/^subject://p' <<<"$labels" | head -n1 || true)
  priority=$(sed -n 's/^priority://p' <<<"$labels" | head -n1 || true)
  sprint=$(sed -n 's/^sprint://p' <<<"$labels" | head -n1 || true)

  [[ -n "$subject" ]] && set_single "$item_id" Subject "$subject"
  [[ -n "$priority" ]] && set_single "$item_id" Priority "$priority"
  if [[ "$sprint" =~ ^([1-9]|1[0-6])$ ]]; then
    set_single "$item_id" Sprint "Sprint $sprint"
  fi
done

log "Q5 Project sync complete"
