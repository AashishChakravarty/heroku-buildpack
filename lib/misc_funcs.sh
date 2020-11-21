# Outputs log line
#
# Usage:
#
#     output_line "Cloning repository"
#
function output_line() {
  local spacing="      "
  echo "${spacing} $1"
}

# Outputs section heading
#
# Usage:
#
#     output_section "Application tasks"
#
function output_section() {
  local indentation="----->"
  echo "${indentation} $1"
}


function load_config() {
  output_section "Checking Erlang and Elixir versions"

  local custom_config_file="${build_path}/elixir_buildpack.config"

  # Source for default versions file from buildpack first
  source "${build_pack_path}/elixir_buildpack.config"

  if [ -f $custom_config_file ];
  then
    source $custom_config_file
  else
    output_line "WARNING: elixir_buildpack.config wasn't found in the app"
    output_line "Using default config from Elixir buildpack"
  fi

  fix_erlang_version
  fix_elixir_version

  output_line "Will use the following versions:"
  output_line "* Stack ${STACK}"
  output_line "* Erlang ${erlang_version}"
  output_line "* Elixir ${elixir_version[0]} ${elixir_version[1]}"
}


function export_env_vars() {
  whitelist_regex=${2:-''}
  blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH)$'}
  if [ -d "$env_path" ]; then
    output_section "Will export the following config vars:"
    for e in $(ls $env_path); do
      echo "$e" | grep -E "$whitelist_regex" | grep -vE "$blacklist_regex" &&
      export "$e=$(cat $env_path/$e)"
      :
    done
  fi
}

function export_mix_env() {
  if [ -z "$MIX_ENV" ]; then
    if [ -d $env_path ] && [ -f $env_path/MIX_ENV ]; then
      export MIX_ENV=$(cat $env_path/MIX_ENV)
    else
      export MIX_ENV=${1:-prod}
    fi
  fi

  output_line "* MIX_ENV=${MIX_ENV}"
}

function check_stack() {
  if [ "${STACK}" = "heroku-16" ] || [ "${STACK}" = "cedar" ]; then
    echo "ERROR: the current stack is not supported, upgrade to heroku-18"
    exit 1
  fi

  if [ ! -f "${cache_path}/stack" ] || [ $(cat "${cache_path}/stack") != "${STACK}" ]; then
    output_section "Stack changed, will rebuild"
    $(clear_cached_files)
  fi

  echo "${STACK}" > "${cache_path}/stack"
}

function clean_cache() {
  if [ $always_rebuild = true ]; then
    output_section "Cleaning all cache to force rebuilds"
    $(clear_cached_files)
  fi
}

function clear_cached_files() {
  rm -rf \
    $(erlang_build_path) \
    $(deps_backup_path) \
    $(build_backup_path) \
    $(mix_backup_path) \
    $(hex_backup_path)
}

function fix_erlang_version() {
  erlang_version=$(echo "$erlang_version" | sed 's/[^0-9.]*//g')
}

function fix_elixir_version() {
  # TODO: this breaks if there is an carriage return behind elixir_version=(branch master)^M
  if [ ${#elixir_version[@]} -eq 2 ] && [ ${elixir_version[0]} = "branch" ]; then
    force_fetch=true
    elixir_version=${elixir_version[1]}

  elif [ ${#elixir_version[@]} -eq 1 ]; then
    force_fetch=false

    # If we detect a version string (e.g. 1.14 or 1.14.0) we prefix it with "v"
    if [[ ${elixir_version} =~ ^[0-9]+\.[0-9]+ ]]; then
      # strip out any non-digit non-dot characters
      elixir_version=$(echo "$elixir_version" | sed 's/[^0-9.]*//g')
      elixir_version=v${elixir_version}
    fi

  else
    output_line "Invalid Elixir version specified"
    output_line "See the README for allowed formats at:"
    output_line "https://github.com/heroku-elixir/buildpack"
    exit 1
  fi
}
