# Config file for Powerlevel10k with the style of robbyrussell theme from Oh My Zsh.
#
# Original: https://github.com/ohmyzsh/ohmyzsh/wiki/Themes#robbyrussell.
#
# Replication of robbyrussell theme is exact. The only observable difference is in
# performance. Powerlevel10k prompt is very fast everywhere, even in large Git repositories.
#
# Usage: Source this file either before or after loading Powerlevel10k.
#
#   source ~/powerlevel10k/config/p10k-robbyrussell.zsh
#   source ~/powerlevel10k/powerlevel10k.zsh-theme

# Temporarily change options.
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob

  # Unset all configuration options.
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

  # Zsh >= 5.1 is required.
  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  # Left prompt segments.
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    # =========================[ Line #1 ]=========================
    os_icon                   # OS icon
    # user                      # user
    context                   # user@host
    dir                       # current directory
    vcs                       # git status
    # =========================[ Line #2 ]=========================
    newline                   # \n
    prompt_char               # prompt symbol
  )
  # Right prompt segments.
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    # =========================[ Line #1 ]=========================
    command_execution_time    # previous command duration
    python_version            # Python version
    ruby_version              # Ruby version
    rust_version              # Rust version
    go_version                # Go version
    node_version              # Node.js version
    php_version               # PHP version
    laravel_version           # Laravel version
    # =========================[ Line #2 ]=========================
    newline                   # \n
    direnv
    per_directory_history
    background_jobs
  )

  # Don't show context unless running with privileges or in SSH.
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=

  # Basic style options that define the overall prompt look.
  typeset -g POWERLEVEL9K_BACKGROUND=                            # transparent background
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=  # no surrounding whitespace
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' '  # separate segments with a space
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=        # no end-of-line symbol
  typeset -g POWERLEVEL9K_VISUAL_IDENTIFIER_EXPANSION=           # no segment icons

  # Basic directory shortening strategy.
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_last
  # typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=1
  # typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=5
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=''

  # Prompt symbol: bold arrow, green on success / red on failure.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS}_FOREGROUND=2
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS}_FOREGROUND=1
  typeset -g POWERLEVEL9K_PROMPT_CHAR_CONTENT_EXPANSION='%B➜ '

  # OS icon: Apple logo, bright blue.
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=12
  typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION=$'\ue635'

  # Current directory: blue, bold, truncated to the repo root.
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=4
  # typeset -g POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER=last
  typeset -g POWERLEVEL9K_DIR_CONTENT_EXPANSION='%B${P9K_CONTENT}%b${SSH_CONNECTION:+ %3F\udb81\udfc0%f}'

  # Git segment: magenta branch icon.
  typeset -g POWERLEVEL9K_VCS_FOREGROUND=6
  typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_EXPANSION=$'\uf113'

  # Node segment: Only display Node inside projects containing package.json.
  typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND='#b7cc85'
  typeset -g POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_NODE_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\ued0d'
  typeset -g POWERLEVEL9K_NODE_VERSION_ICON_BEFORE_CONTENT=true

  # PHP segment: Only display PHP inside projects containing composer.json.
  typeset -g POWERLEVEL9K_PHP_VERSION_FOREGROUND='#a074c4'
  typeset -g POWERLEVEL9K_PHP_VERSION_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_PHP_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\ue608'
  typeset -g POWERLEVEL9K_PHP_VERSION_ICON_BEFORE_CONTENT=true

  # Laravel segment: Only display PHP inside projects containing composer.json.
  typeset -g POWERLEVEL9K_LARAVEL_VERSION_FOREGROUND='#f05340'
  typeset -g POWERLEVEL9K_LARAVEL_VERSION_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_LARAVEL_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\ue73f'
  typeset -g POWERLEVEL9K_LARAVEL_VERSION_ICON_BEFORE_CONTENT=true

  # Per-directory history segment: Only display per-directory history inside projects containing .git.
  typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_FOREGROUND='#808080'
  typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_LOCAL_CONTENT_EXPANSION=''
  typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_GLOBAL_CONTENT_EXPANSION=''

  # Git status formatter.
  function my_git_formatter() {
    emulate -L zsh

    if [[ -n $P9K_CONTENT ]]; then
      # Loading state or vcs_info fallback.
      typeset -g my_git_format=$P9K_CONTENT
      return
    fi

    # Nerd Font icons.
    local icon_staged='+'
    local icon_modified='-'
    local icon_untracked='?'
    local icon_conflicted='!'
    local icon_ahead='⇡'
    local icon_behind='⇣'
    local icon_stash='*'

    # Colors for fresh status.
    local meta='%244F'
    local staged='%70F'
    local modified='%178F'
    local untracked='%244F'
    local conflicted='%1F'
    local divergence='%141F'
    local stash='%214F'

    local res=''

    # Branch, tag or detached HEAD.
    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
      local branch=${(V)VCS_STATUS_LOCAL_BRANCH}
      branch=${branch//\%/%%}
      branch=${branch##*/}
      res+="${branch_color}${branch}"
    elif [[ -n $VCS_STATUS_TAG ]]; then
      local tag=${(V)VCS_STATUS_TAG}
      tag=${tag//\%/%%}
      res+="${branch_color}${icon_tag} ${tag}"
    else
      res+="${meta}${icon_commit} ${VCS_STATUS_COMMIT[1,8]}"
    fi

    # Detect a linked worktree without spawning another `git` process.
    #
    # A linked worktree's .git file points into:
    #   <main-repository>/.git/worktrees/<worktree>
    # local git_file="$VCS_STATUS_WORKDIR/.git"

    # if [[ -f $git_file ]]; then
    #   local gitdir
    #   gitdir=$(<"$git_file")
    #   gitdir=${gitdir#gitdir: }

    #   if [[ $gitdir == *'.git/worktrees/'* ]]; then
    #     res+=" ${worktree_color}${icon_worktree}"
    #   fi
    # fi

    # Remote divergence.
    (( VCS_STATUS_COMMITS_BEHIND )) &&
      res+=" ${divergence}${icon_behind}${VCS_STATUS_COMMITS_BEHIND}"

    (( VCS_STATUS_COMMITS_AHEAD )) &&
      res+=" ${divergence}${icon_ahead}${VCS_STATUS_COMMITS_AHEAD}"

    # Local file status.
    (( VCS_STATUS_NUM_CONFLICTED )) &&
      res+=" ${conflicted}${icon_conflicted}${VCS_STATUS_NUM_CONFLICTED}"

    (( VCS_STATUS_NUM_STAGED )) &&
      res+=" ${staged}${icon_staged}${VCS_STATUS_NUM_STAGED}"

    (( VCS_STATUS_NUM_UNSTAGED )) &&
      res+=" ${modified}${icon_modified}${VCS_STATUS_NUM_UNSTAGED}"

    (( VCS_STATUS_NUM_UNTRACKED )) &&
      res+=" ${untracked}${icon_untracked}${VCS_STATUS_NUM_UNTRACKED}"

    (( VCS_STATUS_STASHES )) &&
      res+=" ${stash}${icon_stash}${VCS_STATUS_STASHES}"

    typeset -g my_git_format=$res
  }

  functions -M my_git_formatter 2>/dev/null

  # Disable the default Git status formatting.
  typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
  # Install our own Git status formatter.
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((my_git_formatter(1)))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_LOADING_CONTENT_EXPANSION='${$((my_git_formatter()))+${my_git_format}}'
  # Grey Git status when loading.
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=246

  # Disable async loading indicator to make directories that aren't Git repositories
  # indistinguishable from large Git repositories without known state.
  typeset -g POWERLEVEL9K_VCS_LOADING_TEXT=

  # Don't wait for Git status even for a millisecond, so that prompt always updates
  # asynchronously when Git state changes.
  typeset -g POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS=0

  # Instant prompt mode.
  #
  #   - off:     Disable instant prompt. Choose this if you've tried instant prompt and found
  #              it incompatible with your zsh configuration files.
  #   - quiet:   Enable instant prompt and don't print warnings when detecting console output
  #              during zsh initialization. Choose this if you've read and understood
  #              https://github.com/romkatv/powerlevel10k#instant-prompt.
  #   - verbose: Enable instant prompt and print a warning when detecting console output during
  #              zsh initialization. Choose this if you've never tried instant prompt, haven't
  #              seen the warning, or if you are unsure what this all means.
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

  # Hot reload allows you to change POWERLEVEL9K options after Powerlevel10k has been initialized.
  # For example, you can type POWERLEVEL9K_BACKGROUND=red and see your prompt turn red. Hot reload
  # can slow down prompt by 1-2 milliseconds, so it's better to keep it turned off unless you
  # really need it.
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  # If p10k is already loaded, reload configuration.
  # This works even with POWERLEVEL9K_DISABLE_HOT_RELOAD=true.
  (( ! $+functions[p10k] )) || p10k reload
}

# Tell `p10k configure` which file it should overwrite.
typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
