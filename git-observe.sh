#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

fail() {
    echo -e "${RED}$1${NC}" >&2
    exit 1
}

require_tools() {
    git rev-parse --git-dir >/dev/null 2>&1 || fail "Not inside a git repository"
    command -v fzf >/dev/null || fail "fzf is required: brew install fzf"
}

base_branch() {
    local candidate ahead best="" fewest=""
    for candidate in origin/staging origin/main origin/master; do
        git show-ref --verify --quiet "refs/remotes/$candidate" || continue
        ahead=$(git rev-list --count "$candidate..$BRANCH")
        if [[ -z "$fewest" || "$ahead" -lt "$fewest" ]]; then
            best="$candidate" fewest="$ahead"
        fi
    done
    [[ -n "$best" ]] || fail "Could not find staging, main or master on origin"
    echo "$best"
}

github_url() {
    git remote get-url origin |
        sed -E 's#^(git@|ssh://git@|https://)([^:/]+)[:/]#https://\2/#; s#\.git$##'
}

checkout_remote_branch() {
    local name="$1"
    echo -e "${DIM}Fetching ${name} from origin...${NC}"
    git fetch --quiet origin "$name" || fail "Branch '$name' not found on origin"
    if git show-ref --verify --quiet "refs/heads/$name"; then
        git checkout --quiet "$name"
        git merge --quiet --ff-only "origin/$name"
    else
        git checkout --quiet --track "origin/$name"
    fi
}

pick_local_branch() {
    git for-each-ref refs/heads --sort=-committerdate \
        --format='%(refname:short)%09%(color:dim)%(worktreepath)%(color:reset)' --color=always |
        fzf --ansi --delimiter='\t' --reverse --border=rounded --nth=1 \
            --header='Pick a branch or worktree' |
        cut -f1
}

choose_branch() {
    local current choice
    current=$(git branch --show-current)
    echo -e "${BOLD}git observe${NC}"
    echo -e "  ${CYAN}[c]${NC} current branch ${DIM}(${current})${NC}"
    echo -e "  ${CYAN}[l]${NC} local branch or worktree"
    echo -e "  ${CYAN}[n]${NC} new branch from origin"
    read -rn1 -p "> " choice
    echo
    case "$choice" in
        c|C|"") BRANCH="$current" ;;
        l|L)
            BRANCH=$(pick_local_branch)
            [[ -n "$BRANCH" ]] || fail "No branch selected"
            ;;
        n|N)
            read -rp "Branch name: " BRANCH
            [[ -n "$BRANCH" ]] || fail "No branch name given"
            checkout_remote_branch "$BRANCH"
            ;;
        *) fail "Unknown option '$choice'" ;;
    esac
}

branch_commits() {
    git log "$1..$2" --reverse --color=always --date=relative \
        --format='%C(yellow)%h%C(reset)  %s %C(dim)· %an, %ad%C(reset)'
}

browse_commits() {
    local base="$1" repo_url="$2" commits count
    commits=$(branch_commits "$base" "$BRANCH")
    [[ -n "$commits" ]] || fail "No commits on ${BRANCH} since ${base}"
    count=$(wc -l <<<"$commits" | tr -d ' ')

    fzf <<<"$commits" --ansi --no-sort --reverse --border=rounded \
        --header="${BRANCH}  ·  ${count} commits since ${base}  ·  enter: open on GitHub  ·  esc: quit" \
        --preview='git show --stat --color=always {1}' \
        --preview-window=right,55%,wrap \
        --bind="enter:execute-silent(open ${repo_url}/commit/{1})"
}

main() {
    require_tools
    choose_branch
    browse_commits "$(base_branch)" "$(github_url)"
}

main
