check_param() {
  local name=$1
  local value=$(eval echo '$'$name)
  if [ "$value" == 'replace-me' ]; then
    echo "environment variable $name must be set"
    exit 1
  fi
}

print_git_state() {
  local git_project=$1
  pushd $git_project
  echo "--> last commit for ${git_project}..."
  TERM=xterm-256color git log -1
  echo "---"
  echo "--> local changes for ${git_project} (e.g., from 'fly execute')..."
  TERM=xterm-256color git status -vv
  echo "---"
  popd
}
