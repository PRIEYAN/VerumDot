# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
# export ZSH="$HOME/.oh-my-zsh"

# Launch sway once logged in TTY
ps aux > tmpps
VAR=$(cat tmpps | grep sway)

if [ -z "$VAR" ] && [ "$(tty)" = "/dev/tty1" ]; then
	exec sway
fi
rm tmpps

# Aliases
alias install="sudo pacman -Sy"
alias isntall="sudo pacman -Sy"
alias up="sudo pacman -Syyu"
alias purge="sudo pacman -Rnds"
alias autoremove="sudo pacman -Rcns \`pacman -Qdtq\`"

alias lv="lvim"
alias c="code . && exit"
alias as="QT_QPA_PLATFORM=xcb _JAVA_AWT_WM_NONREPARENTING=1 android-studio"

alias gcl="git clone"
alias gpl="git pull"
alias gp="git pull && git push"
alias gc="git commit -m"
alias ga="git add"
alias gs="git status"
alias glog="git log --graph"

alias mkea="make"
alias maek="make"
alias mkae="make"
alias amke="make"
alias amek="make"

alias btw="sudo"
alias please="sudo"
alias plz="sudo"
alias suod="sudo"

alias bashrc="sudo vim /etc/bash.bashrc && source /etc/bash.bashrc"
alias zshrc="sudo lvim ~/.zshrc && source ~/.zshrc"

alias debian="sudo docker run -it --rm -v $PWD:/tmp/workspace -w /tmp/workspace debian /bin/bash"

# ENV VARS
export CONFIG="$HOME/.config"
export ADB_MDNS_OPENSCREEN=1

export PATH="$HOME/.local/bin:$PATH"
export PS1="%F{red}%1~ >%f "

# Theme
# ZSH_THEME="agnoster"

# plugins=(git zsh-autosuggestions sudo)

# source $ZSH/oh-my-zsh.sh
export RPROMPT=%B%(?."%F{green}%?%f :)"."%F{red}%?%f :(")%b
# prompt_context() {}

# ─── Autocorrection ────────────────────────────────────
setopt CORRECT          # correct mistyped commands
setopt CORRECT_ALL      # also correct arguments / filenames
SPROMPT="correct '%R' to '%r'? [Yes/No/Abort/Edit] "

# ─── History (powers autosuggestions) ─────────────────
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# ─── Plugins (install via pacman, see below) ──────────
# pacman -S zsh-autosuggestions zsh-syntax-highlighting zsh-completions
[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fpath=(/usr/share/zsh/site-functions $fpath)

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6272a4"

# tab-completion menu
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'l:|=* r:|=*'

alias ls="ls --color=auto"
alias l="ls -la --color=auto"

# thefuck (corrects the previous command) – optional
command -v thefuck >/dev/null && eval "$(thefuck --alias fk)"

# Run fastfetch on startup
# fastfetchexport ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
