#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_TOKEN:?PROJECT_TOKEN secret is missing}"
: "${REPO_TOKEN:?REPO_TOKEN is missing}"
: "${PROJECT_OWNER:=jan-lozano-dev}"
: "${PROJECT_TITLE:=Q5 Optimal}"
: "${GITHUB_REPOSITORY:=jan-lozano-dev/Q5-Optimal}"

export GH_TOKEN="$PROJECT_TOKEN"

log() { printf '\n==> %s\n' "$*"; }

# ---------- Project discovery ----------
log "Finding project '$PROJECT_TITLE' for $PROJECT_OWNER"
projects_json=$(gh api graphql \
  -f query='query($login:String!){user(login:$login){projectsV2(first:100){nodes{id title number}}}}' \
  -f login="$PROJECT_OWNER")

project_id=$(jq -r --arg t "$PROJECT_TITLE" '
  .data.user.projectsV2.nodes[] |
  select((.title|ascii_downcase)==($t|ascii_downcase)) |
  .id' <<<"$projects_json" | head -n1)

if [[ -z "${project_id:-}" || "$project_id" == "null" ]]; then
  echo "Project '$PROJECT_TITLE' not found. Available projects:" >&2
  jq -r '.data.user.projectsV2.nodes[] | "- \(.title) (#\(.number))"' <<<"$projects_json" >&2
  exit 2
fi

echo "Project node: $project_id"

# ---------- Helpers ----------
query_fields() {
  gh api graphql \
    -f query='query($id:ID!){node(id:$id){... on ProjectV2{fields(first:100){nodes{__typename ... on ProjectV2Field{id name dataType} ... on ProjectV2SingleSelectField{id name dataType options{id name}} ... on ProjectV2IterationField{id name dataType}}}}}}' \
    -f id="$project_id"
}

create_single_select() {
  local name="$1" options="$2"
  local field_id
  field_id=$(jq -r --arg n "$name" '.data.node.fields.nodes[] | select(.name==$n) | .id' <<<"$fields_json" | head -n1)
  [[ -n "${field_id:-}" && "$field_id" != "null" ]] && return 0

  log "Creating project field: $name"
  case "$name" in
    Subject)
      gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Subject",dataType:SINGLE_SELECT,singleSelectOptions:[{name:"PROP",color:BLUE,description:"Projecte de Programació"},{name:"INTERNET",color:PURPLE,description:"Internet"},{name:"SODX",color:ORANGE,description:"Sistemes Operatius Distribuïts i en Xarxa"},{name:"ESIN",color:YELLOW,description:"Estructura de la Informació"},{name:"PACO",color:GREEN,description:"Paral·lelisme i Concurrència"},{name:"ADSO",color:GRAY,description:"Administració de Sistemes Operatius"},{name:"French",color:PINK,description:"French B1"},{name:"Econometrics",color:RED,description:"Advanced Econometrics & Deep Learning"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f p="$project_id" >/dev/null
      ;;
    Priority)
      gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Priority",dataType:SINGLE_SELECT,singleSelectOptions:[{name:"P0",color:RED,description:"Critical/highest ROI"},{name:"P1",color:ORANGE,description:"High"},{name:"P2",color:YELLOW,description:"Normal"},{name:"P3",color:GRAY,description:"Low/maintenance"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f p="$project_id" >/dev/null
      ;;
    Type)
      gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Type",dataType:SINGLE_SELECT,singleSelectOptions:[{name:"Concept",color:BLUE,description:"Conceptual mastery"},{name:"Coding",color:GREEN,description:"Executable implementation"},{name:"Problems",color:YELLOW,description:"Problem solving"},{name:"Lab",color:PURPLE,description:"Laboratory work"},{name:"Exam",color:RED,description:"Exam preparation/simulation"},{name:"Admin",color:GRAY,description:"Administrative task"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f p="$project_id" >/dev/null
      ;;
    Sprint)
      gh api graphql -f query='mutation($p:ID!){createProjectV2Field(input:{projectId:$p,name:"Sprint",dataType:SINGLE_SELECT,singleSelectOptions:[{name:"Sprint 1",color:BLUE,description:"Week 1"},{name:"Sprint 2",color:GREEN,description:"Week 2"},{name:"Sprint 3",color:YELLOW,description:"Week 3"},{name:"Sprint 4",color:ORANGE,description:"Week 4"},{name:"Sprint 5",color:PURPLE,description:"Week 5"},{name:"Sprint 6",color:PINK,description:"Week 6"},{name:"Sprint 7",color:BLUE,description:"Week 7"},{name:"Sprint 8",color:GREEN,description:"Week 8"},{name:"Sprint 9",color:YELLOW,description:"Week 9"},{name:"Sprint 10",color:ORANGE,description:"Week 10"},{name:"Sprint 11",color:PURPLE,description:"Week 11"},{name:"Sprint 12",color:PINK,description:"Week 12"},{name:"Sprint 13",color:BLUE,description:"Week 13"},{name:"Sprint 14",color:GREEN,description:"Week 14"},{name:"Sprint 15",color:YELLOW,description:"Week 15"},{name:"Sprint 16",color:GRAY,description:"Week 16"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f p="$project_id" >/dev/null
      ;;
  esac
}

create_date_field() {
  local name="$1"
  local field_id
  field_id=$(jq -r --arg n "$name" '.data.node.fields.nodes[] | select(.name==$n) | .id' <<<"$fields_json" | head -n1)
  [[ -n "${field_id:-}" && "$field_id" != "null" ]] && return 0
  log "Creating project field: $name"
  gh api graphql -f query='mutation($p:ID!,$n:String!){createProjectV2Field(input:{projectId:$p,name:$n,dataType:DATE}){projectV2Field{... on ProjectV2Field{id}}}}' -f p="$project_id" -f n="$name" >/dev/null
}

set_single() {
  local item_id="$1" field_name="$2" option_name="$3"
  local field_id option_id
  field_id=$(jq -r --arg f "$field_name" '.data.node.fields.nodes[] | select(.name==$f) | .id' <<<"$fields_json" | head -n1)
  option_id=$(jq -r --arg f "$field_name" --arg o "$option_name" '.data.node.fields.nodes[] | select(.name==$f) | .options[]? | select(.name==$o) | .id' <<<"$fields_json" | head -n1)
  if [[ -z "${field_id:-}" || -z "${option_id:-}" || "$field_id" == "null" || "$option_id" == "null" ]]; then
    echo "Skipping missing field/option: $field_name=$option_name" >&2
    return 0
  fi
  gh api graphql -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}' \
    -f p="$project_id" -f i="$item_id" -f f="$field_id" -f o="$option_id" >/dev/null
}

ensure_label() {
  local name="$1" color="$2" description="$3"
  GH_TOKEN="$REPO_TOKEN" gh api -X POST "repos/$GITHUB_REPOSITORY/labels" \
    -f name="$name" -f color="$color" -f description="$description" >/dev/null 2>&1 || true
}

add_label_if_missing() {
  local issue="$1" label="$2"
  local encoded
  encoded=$(jq -rn --arg x "$label" '$x|@uri')
  if ! GH_TOKEN="$REPO_TOKEN" gh api "repos/$GITHUB_REPOSITORY/issues/$issue/labels" --jq '.[].name' | grep -Fxq "$label"; then
    GH_TOKEN="$REPO_TOKEN" gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$issue/labels" --input - >/dev/null <<JSON
{"labels":["$label"]}
JSON
  fi
}

# ---------- Configure Status ----------
fields_json=$(query_fields)
status_field_id=$(jq -r '.data.node.fields.nodes[] | select(.name=="Status") | .id' <<<"$fields_json" | head -n1)
if [[ -z "${status_field_id:-}" || "$status_field_id" == "null" ]]; then
  echo "Status field not found in project" >&2
  exit 3
fi

log "Configuring mastery workflow statuses"
gh api graphql -f query='mutation($f:ID!){updateProjectV2Field(input:{fieldId:$f,singleSelectOptions:[{name:"Backlog",color:GRAY,description:"Not selected for the current sprint"},{name:"This Sprint",color:BLUE,description:"Committed outcome for the current sprint"},{name:"Learning",color:YELLOW,description:"Building the mental model"},{name:"Practice",color:ORANGE,description:"Applying with exercises or code"},{name:"Retrieval",color:PURPLE,description:"Delayed closed-book retrieval"},{name:"Exam Ready",color:GREEN,description:"Passed the mastery gate under exam-like conditions"},{name:"Done",color:PINK,description:"Assessed or no longer needs maintenance"}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f f="$status_field_id" >/dev/null

# ---------- Configure custom fields ----------
fields_json=$(query_fields)
create_single_select Subject ignored
fields_json=$(query_fields)
create_single_select Priority ignored
fields_json=$(query_fields)
create_single_select Type ignored
fields_json=$(query_fields)
create_single_select Sprint ignored
fields_json=$(query_fields)
create_date_field "Next Review"
fields_json=$(query_fields)

# ---------- Create control labels ----------
log "Ensuring control labels"
ensure_label "stage:backlog" "6e7781" "Move project item to Backlog"
ensure_label "stage:this-sprint" "1f6feb" "Move project item to This Sprint"
ensure_label "stage:learning" "d4c5f9" "Move project item to Learning"
ensure_label "stage:practice" "fb8500" "Move project item to Practice"
ensure_label "stage:retrieval" "8250df" "Move project item to Retrieval"
ensure_label "stage:exam-ready" "2da44e" "Move project item to Exam Ready"
ensure_label "stage:done" "bf8700" "Move project item to Done"

for s in PROP INTERNET SODX ESIN PACO ADSO French Econometrics; do
  ensure_label "subject:$s" "0969da" "Subject metadata"
done
for p in P0 P1 P2 P3; do
  ensure_label "priority:$p" "b60205" "Priority metadata"
done
for t in Concept Coding Problems Lab Exam Admin; do
  ensure_label "type:$t" "5319e7" "Task type metadata"
done

# ---------- Initial metadata (only fills absent metadata) ----------
initialize_issue_metadata() {
  local n="$1" subject="$2" priority="$3" type="$4" stage="$5"
  local existing
  existing=$(GH_TOKEN="$REPO_TOKEN" gh api "repos/$GITHUB_REPOSITORY/issues/$n/labels" --jq '.[].name' 2>/dev/null || true)
  [[ -z "$existing" || ! "$existing" =~ subject: ]] && add_label_if_missing "$n" "subject:$subject"
  [[ -z "$existing" || ! "$existing" =~ priority: ]] && add_label_if_missing "$n" "priority:$priority"
  [[ -z "$existing" || ! "$existing" =~ type: ]] && add_label_if_missing "$n" "type:$type"
  [[ -z "$existing" || ! "$existing" =~ stage: ]] && add_label_if_missing "$n" "stage:$stage"
}

for n in 1 2 3 4 5; do
  if GH_TOKEN="$REPO_TOKEN" gh api "repos/$GITHUB_REPOSITORY/issues/$n" >/dev/null 2>&1; then
    case "$n" in
      1) initialize_issue_metadata 1 PROP P0 Coding learning ;;
      2) initialize_issue_metadata 2 INTERNET P0 Problems this-sprint ;;
      3) initialize_issue_metadata 3 SODX P0 Exam this-sprint ;;
      4) initialize_issue_metadata 4 ESIN P1 Coding this-sprint ;;
      5) initialize_issue_metadata 5 PACO P1 Lab this-sprint ;;
    esac
  fi
done

# ---------- Sync issues to project ----------
log "Syncing repository issues into project"
issue_numbers=$(GH_TOKEN="$REPO_TOKEN" gh api --paginate "repos/$GITHUB_REPOSITORY/issues?state=all&per_page=100" --jq '.[] | select(.pull_request == null) | .number')

for n in $issue_numbers; do
  issue_json=$(GH_TOKEN="$REPO_TOKEN" gh api "repos/$GITHUB_REPOSITORY/issues/$n")
  content_id=$(jq -r '.node_id' <<<"$issue_json")
  state=$(jq -r '.state' <<<"$issue_json")
  labels=$(jq -r '.labels[].name' <<<"$issue_json" 2>/dev/null || true)

  items_json=$(gh api graphql -f query='query($p:ID!){node(id:$p){... on ProjectV2{items(first:100){nodes{id content{... on Issue{id}}}}}}}' -f p="$project_id")
  item_id=$(jq -r --arg c "$content_id" '.data.node.items.nodes[] | select(.content.id==$c) | .id' <<<"$items_json" | head -n1)

  if [[ -z "${item_id:-}" || "$item_id" == "null" ]]; then
    item_id=$(gh api graphql -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' -f p="$project_id" -f c="$content_id" --jq '.data.addProjectV2ItemById.item.id')
    echo "Added issue #$n to project"
  fi

  # Status: closed always wins; otherwise stage label controls it.
  status="Backlog"
  if [[ "$state" == "closed" ]]; then
    status="Done"
  elif grep -Fxq "stage:exam-ready" <<<"$labels"; then status="Exam Ready"
  elif grep -Fxq "stage:retrieval" <<<"$labels"; then status="Retrieval"
  elif grep -Fxq "stage:practice" <<<"$labels"; then status="Practice"
  elif grep -Fxq "stage:learning" <<<"$labels"; then status="Learning"
  elif grep -Fxq "stage:this-sprint" <<<"$labels"; then status="This Sprint"
  elif grep -Fxq "stage:done" <<<"$labels"; then status="Done"
  elif grep -Fxq "stage:backlog" <<<"$labels"; then status="Backlog"
  fi
  set_single "$item_id" Status "$status"

  subject=$(sed -n 's/^subject://p' <<<"$labels" | head -n1 || true)
  priority=$(sed -n 's/^priority://p' <<<"$labels" | head -n1 || true)
  type=$(sed -n 's/^type://p' <<<"$labels" | head -n1 || true)

  [[ -n "$subject" ]] && set_single "$item_id" Subject "$subject"
  [[ -n "$priority" ]] && set_single "$item_id" Priority "$priority"
  [[ -n "$type" ]] && set_single "$item_id" Type "$type"
  set_single "$item_id" Sprint "Sprint 1"

done

log "Q5 Optimal project sync complete"
