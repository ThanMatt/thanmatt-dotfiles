function fish_greeting
  fortune | cowsay
end


alias l="ls -aslh"
alias pls="sudo"
alias pip="pip3"
alias vi="nvim"
# :: Windows config
# alias adb="adb.exe"
alias Fish="code ~/.config/fish/config.fish"
alias Fish!="source ~/.config/fish/config.fish"
alias Vim="nvim ~/.config/nvim/init.vim"
alias Vim!="source ~/.config/nvim/init.vim"
alias Tmux="code ~/.tmux.conf"
alias Tmux!="source ~/.tmux.conf"
alias Alacritty="code ~/.config/alacritty/alacritty.yml"
alias Nginx="cd /etc/nginx"
alias tmux="tmux attach -t base"
alias Logid="code /etc/logid.cfg"

# migrating from https://github.com/robbyrussell/oh-my-zsh/blob/master/plugins/git/git.plugin.zsh

# Aliases
alias g='git'
#compdef g=git
alias gst='git status'
#compdef _git gst=git-status
alias gd='git diff'
#compdef _git gd=git-diff
alias gdc='git diff --cached'
#compdef _git gdc=git-diff
alias gl='git pull'
#compdef _git gl=git-pull
alias gup='git pull --rebase'
#compdef _git gup=git-fetch
alias gp='git push'
#compdef _git gp=git-push
alias gd='git diff'


function gdv
  git diff -w $argv | view -
end

#compdef _git gdv=git-diff
alias gc='git commit -v'
#compdef _git gc=git-commit
alias gc!='git commit -v --amend'
#compdef _git gc!=git-commit
alias gca='git commit -v -a'
#compdef _git gc=git-commit
alias gca!='git commit -v -a --amend'
#compdef _git gca!=git-commit
alias gcmsg='git commit -m'
#compdef _git gcmsg=git-commit
alias gco='git checkout'
#compdef _git gco=git-checkout
alias gcm='git checkout master'
alias gr='git remote'
#compdef _git gr=git-remote
alias grv='git remote -v'
#compdef _git grv=git-remote
alias grmv='git remote rename'
#compdef _git grmv=git-remote
alias grrm='git remote remove'
#compdef _git grrm=git-remote
alias grset='git remote set-url'
#compdef _git grset=git-remote
alias grup='git remote update'
#compdef _git grset=git-remote
alias grbi='git rebase -i'
#compdef _git grbi=git-rebase
alias grbc='git rebase --continue'
#compdef _git grbc=git-rebase
alias grba='git rebase --abort'
#compdef _git grba=git-rebase
alias gb='git branch'
#compdef _git gb=git-branch
alias gba='git branch -a'
#compdef _git gba=git-branch
alias gcount='git shortlog -sn'
#compdef gcount=git
alias gcl='git config --list'
alias gcp='git cherry-pick'
#compdef _git gcp=git-cherry-pick
alias glg='git log --stat --max-count=10'
#compdef _git glg=git-log
alias glgg='git log --graph --max-count=10'
#compdef _git glgg=git-log
alias glgga='git log --graph --decorate --all'
#compdef _git glgga=git-log
alias glo='git log --oneline'
#compdef _git glo=git-log
alias gss='git status -s'
#compdef _git gss=git-status
alias ga='git add'
#compdef _git ga=git-add
alias gm='git merge'
#compdef _git gm=git-merge
alias grh='git reset HEAD'
alias grhh='git reset HEAD --hard'
alias gclean='git reset --hard; and git clean -dfx'
alias gwc='git whatchanged -p --abbrev-commit --pretty=medium'

#remove the gf alias
#alias gf='git ls-files | grep'

alias gpoat='git push origin --all; and git push origin --tags'
alias gmt='git mergetool --no-prompt'
#compdef _git gm=git-mergetool

alias gg='git gui citool'
alias gga='git gui citool --amend'
alias gk='gitk --all --branches'

alias gsts='git stash show --text'
alias gsta='git stash'
alias gstp='git stash pop'
alias gstd='git stash drop'

# Will cd into the top of the current repository
# or submodule.
alias grt='cd (git rev-parse --show-toplevel or echo ".")'

# Git and svn mix
alias git-svn-dcommit-push='git svn dcommit; and git push github master:svntrunk'
#compdef git-svn-dcommit-push=git

alias gsr='git svn rebase'
alias gsd='git svn Dcommit'
#
# Will return the current branch name
# Usage example: git pull origin $(current_branch)
#
function current_branch
  git rev-parse --abbrev-ref HEAD
  # set ref (git symbolic-ref HEAD 2> /dev/null); or \
  # set ref (git rev-parse --short HEAD 2> /dev/null); or return
  # echo ref | sed s-refs/heads--
end

function current_repository
  set ref (git symbolic-ref HEAD 2> /dev/null); or \
  set ref (git rev-parse --short HEAD 2> /dev/null); or return
  echo (git remote -v | cut -d':' -f 2)
end

# these aliases take advantage of the previous function
alias ggpull='git pull origin (current_branch)'
#compdef ggpull=git
alias ggpur='git pull --rebase origin (current_branch)'
#compdef ggpur=git
alias ggpush='git push origin (current_branch)'
#compdef ggpush=git
alias ggpnp='git pull origin (current_branch); and git push origin (current_branch)'
#compdef ggpnp=git
alias gfetch='git fetch origin && git pull --rebase origin (current_branch)'

# Pretty log messages
function _git_log_prettily
  if ! [ -z $1 ]; then
    git log --pretty=$1
  end
end

alias glp="_git_log_prettily"
#compdef _git glp=git-log

# Work In Progress (wip)
# These features allow to pause a branch development and switch to another one (wip)
# When you want to go back to work, just unwip it
#
# This function return a warning if the current branch is a wip
function work_in_progress
  if git log -n 1 | grep -q -c wip; then
    echo "WIP!!"
  end
end

function nvm
    bass source ~/.nvm/nvm.sh --no-use ';' nvm $argv
end

# :: Windows Config
# set --export ANDROID /mnt/c/Users/belph/AppData/Local/Android;
# set --export ANDROID_HOME $ANDROID/Sdk;
# set --export JAVA_HOME /usr/lib/jvm/java-1.8.0-openjdk-amd64;
# set -gx PATH $ANDROID_HOME/tools $PATH;
# set -gx PATH $ANDROID_HOME/tools/bin $PATH;
# set -gx PATH $ANDROID_HOME/platform-tools $PATH;
# set -gx PATH $ANDROID_HOME/emulator $PATH;

set -gx PATH /home/thanmatt/.asdf/installs/nodejs/16.3.0/.npm/bin $PATH;

# # Flutter
# set -gx PATH $HOME/Applications/flutter/bin $PATH;
# set -gx PATH $HOME/Applications/android/cmdline-tools/6.0/bin $PATH;
# set -gx PATH $HOME/Applications/android/emulator $PATH;
# set -gx PATH $HOME/Applications/android/platform-tools $PATH;
# set -gx PATH $HOME/.cargo/bin $PATH;
# set -gx PATH $HOME/

# :: Windows Config
# set --export WSL_HOST (tail -1 /etc/resolv.conf | cut -d' ' -f2)
# set --export ADB_SERVER_SOCKET tcp:$WSL_HOST:5037


set --export FZF_DEFAULT_COMMAND 'rg --files --follow --no-ignore-vcs --hidden -g !{"node_modules/*,.git/*}"''}'
set --export EDITOR vim
set --export GTK_IM_MODULE "xim"


# Ubuntu
set -gx PATH $HOME/android-studio/bin $PATH;
set --export ANDROID $HOME/Android;
set --export ANDROID_HOME $ANDROID/Sdk;
set --export ANDROID_SDK_ROOT $ANDROID/Sdk/platform-tools;
set -gx PATH $ANDROID/Sdk/platform-tools $PATH;

set -x DOCKER_BUILDKIT 1
set -x COMPOSE_DOCKER_CLI_BUILD 1
# eval keychain --eval --agents ssh id_ed25519
# fish_ssh_agent
source ~/.asdf/asdf.fish
# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/thanmatt/google-cloud-sdk/path.fish.inc' ]; . '/home/thanmatt/google-cloud-sdk/path.fish.inc'; end

test -s /home/thanmatt/.nvm-fish/nvm.fish; and source /home/thanmatt/.nvm-fish/nvm.fish

    # Commands to run in interactive sessions can go here
