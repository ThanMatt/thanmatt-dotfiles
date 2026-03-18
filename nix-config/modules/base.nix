{ pkgs, config, ... }:

{
  # :: Native path management
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.config/emacs/bin"
    "$HOME/.local/share/pnpm"
  ];

  # :: Native environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    GTK_IM_MODULE = "xim";
    MONITOR = "DP-0";
    DOCKER_BUILDKIT = "1";
    COMPOSE_DOCKER_CLI_BUILD = "1";
    PNPM_HOME = "$HOME/.local/share/pnpm";
    COLORTERM = "truecolor";
  };

  # :: Neovim — binary via Nix, config symlinked from dotfiles
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # :: SSH
  programs.ssh = {
      enable = true;
      extraConfig = ''
        Host github.com
          HostName github.com
          User git
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
      '';
    }

  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/lazyvim";

  programs.emacs = {
    enable = true;
    package = pkgs.emacs;
  };

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    terminal = "tmux-256color";
    mouse = true;
    historyLimit = 5000;
    escapeTime = 10;
    focusEvents = true;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      sidebar
      battery
      resurrect
      continuum
      vim-tmux-navigator
    ];
    extraConfig = ''
      set -g terminal-overrides ',xterm-256color:RGB'
      set -s set-clipboard on
      set-option -g default-shell ${pkgs.fish}/bin/fish

      set -g set-titles on
      set -g set-titles-string "#W #{command} #T #{session_path}"
      set -g monitor-activity on
      set -g visual-activity on

      set -g prefix2 C-a
      bind C-a send-prefix -2

      bind c new-window -c "#{pane_current_path}"
      bind '"' split-window -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"

      bind -T copy-mode-vi v send -X begin-selection
      bind P paste-buffer
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "wl-copy"

      set-option -g update-environment "DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE SWAYSOCK I3SOCK"

      set-option -g status-position bottom
      set-option -g status on
      set-option -g status-interval 1
      set-option -g automatic-rename on
      set-option -g automatic-rename-format '#{?#{m:fish,#{pane_current_command}},#{b:pane_current_path},#{pane_current_command} #{b:pane_current_path}}'

      bind -n M-h resize-pane -L 10
      bind -n M-j resize-pane -D 5
      bind -n M-k resize-pane -U 5
      bind -n M-l resize-pane -R 10

      set -g display-panes-time 10000

      set -g @continuum-save-interval '15'
      set -g @continuum-boot 'on'
      set -g @continuum-restore 'on'

      # :: Tmuxline statusbar theme
      source ${config.home.homeDirectory}/thanmatt-dotfiles/tmux/tmuxline
    '';
  };

  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        normal = { family = "FiraCode Nerd Font"; style = "Regular"; };
        size = 9;
      };
      colors = {
        primary    = { background = "#282828"; foreground = "#d4be98"; };
        normal     = { black = "#282828"; red = "#ea6962"; green = "#a9b665"; yellow = "#d8a657"; blue = "#7daea3"; magenta = "#d3869b"; cyan = "#89b482"; white = "#d4be98"; };
        bright     = { black = "#928374"; red = "#f2594b"; green = "#b8bb26"; yellow = "#fabd2f"; blue = "#83a598"; magenta = "#d3869b"; cyan = "#8ec07c"; white = "#ebdbb2"; };
        selection  = { text = "CellBackground"; background = "#504945"; };
      };
      keyboard.bindings = [
        { key = "Return"; mods = "Alt"; action = "ToggleFullscreen"; }
      ];
      mouse.bindings = [
        { mouse = "Middle"; action = "PasteSelection"; }
      ];
    };
  };

  programs.kitty.enable = true;

  # :: Symlink kitty config from dotfiles (includes current-theme.conf)
  xdg.configFile."kitty".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/kitty";

  programs.fish = {
    enable = true;

    plugins = [
      {
        name = "fish-theme-r20";
        src = pkgs.fetchFromGitHub {
          owner = "rstacruz";
          repo  = "fish-theme-r20";
          rev   = "master";
          sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };
      }
    ];

    shellAliases = {
      l   = "ls -aslh";
      pls = "sudo";
      pip = "pip3";
      vi  = "nvim";

      Fish      = "vi ~/.config/fish/config.fish";
      "Fish!"   = "source ~/.config/fish/config.fish";
      Vim       = "cd ~/.config/nvim";
      Tmux      = "vi ~/.tmux.conf";
      "Tmux!"   = "tmux source ~/.tmux.conf";
      Alacritty = "vi ~/.config/alacritty/alacritty.toml";
      Ghostty   = "vi ~/.config/ghostty/config";
      Kitty     = "vi ~/.config/kitty/kitty.conf";
      Nginx     = "cd /etc/nginx";
      Logid     = "code /etc/logid.cfg";
      "Doom!"   = "doom sync";
      Niri      = "vi ~/.config/niri/config.kdl";
      Hypr      = "vi ~/.config/hypr/";

      dps = "docker ps --format 'table {{.ID | printf \"%.12s\"}}\\t{{.Names | printf \"%.30s\"}}\\t{{.Status | printf \"%.20s\"}}\\t{{.Ports | printf \"%.30s\"}}\\t{{.Image | printf \"%.20s\"}}'";

      update     = "nix flake update ~/nix-config";
      update-all = "sudo nixos-rebuild switch --flake ~/nix-config#nixos-dev";

      wd               = "waydroid";
      wdstart          = "waydroid show-full-ui";
      "wdstart-detach" = "waydroid show-full-ui &> /dev/null & disown";
      wdstop           = "waydroid session stop";
      wdrestart        = "waydroid session stop && waydroid show-full-ui";
      wdstatus         = "waydroid status";
      wdshell          = "waydroid shell";
      wdconnect        = "adb connect 192.168.240.112";
      wddevices        = "adb devices";
      wdphone          = "waydroid session stop && waydroid prop set persist.waydroid.width 506 && waydroid prop set persist.waydroid.height 2400 && waydroid show-full-ui";
      wdclean          = "waydroid session stop && sudo systemctl stop waydroid-container && sudo rm -rf /var/lib/waydroid /home/.waydroid ~/waydroid ~/.share/waydroid ~/.local/share/waydroid";

      vpn-killswitch  = "sudo ~/.local/bin/vpn-killswitch.sh";
      test-killswitch = "~/.local/bin/test-killswitch";

      g                      = "git";
      gst                    = "git status";
      gd                     = "git diff";
      gdc                    = "git diff --cached";
      gl                     = "git pull";
      gup                    = "git pull --rebase";
      gp                     = "git push";
      gundo                  = "git reset --soft HEAD^";
      gc                     = "git commit -v";
      "gc!"                  = "git commit -v --amend";
      gca                    = "git commit -v -a";
      "gca!"                 = "git commit -v -a --amend";
      gcmsg                  = "git commit -m";
      gco                    = "git checkout";
      gcm                    = "git checkout master";
      gr                     = "git remote";
      grv                    = "git remote -v";
      grmv                   = "git remote rename";
      grrm                   = "git remote remove";
      grset                  = "git remote set-url";
      grup                   = "git remote update";
      grbi                   = "git rebase -i";
      grbc                   = "git rebase --continue";
      grba                   = "git rebase --abort";
      gb                     = "git branch";
      gba                    = "git branch -a";
      gcount                 = "git shortlog -sn";
      gcl                    = "git config --list";
      gcp                    = "git cherry-pick";
      glg                    = "git log --stat --max-count=10";
      glgg                   = "git log --graph --max-count=10";
      glgga                  = "git log --graph --decorate --all";
      glo                    = "git log --oneline";
      gss                    = "git status -s";
      ga                     = "git add";
      gm                     = "git merge";
      grh                    = "git reset HEAD";
      grhh                   = "git reset HEAD --hard";
      gclean                 = "git reset --hard; and git clean -dfx";
      gwc                    = "git whatchanged -p --abbrev-commit --pretty=medium";
      gpoat                  = "git push origin --all; and git push origin --tags";
      gmt                    = "git mergetool --no-prompt";
      gg                     = "git gui citool";
      gga                    = "git gui citool --amend";
      gk                     = "gitk --all --branches";
      gsts                   = "git stash show --text";
      gsta                   = "git stash";
      gstp                   = "git stash pop";
      gstd                   = "git stash drop";
      grt                    = "cd (git rev-parse --show-toplevel or echo \".\")";
      "git-svn-dcommit-push" = "git svn dcommit; and git push github master:svntrunk";
      gsr                    = "git svn rebase";
      gsd                    = "git svn Dcommit";
      ggpull                 = "git pull origin (current_branch)";
      ggpur                  = "git pull --rebase origin (current_branch)";
      ggpush                 = "git push origin (current_branch)";
      ggpnp                  = "git pull origin (current_branch); and git push origin (current_branch)";
      gfetch                 = "git fetch origin && git pull --rebase origin (current_branch)";
      glog                   = "git log -p";
      glp                    = "_git_log_prettily";
    };

    functions = {
      fish_greeting      = "fastfetch -s title:separator:os:cpu:kernel:uptime:shell:display:theme:memory:disk:separator:colors";
      gdv                = "git diff -w $argv | view -";
      mock_merge         = "git merge --no-commit --no-ff $argv";
      current_branch     = "git rev-parse --abbrev-ref HEAD";
      current_repository = ''
        set ref (git symbolic-ref HEAD 2> /dev/null); or set ref (git rev-parse --short HEAD 2> /dev/null); or return
        echo (git remote -v | cut -d':' -f 2)
      '';
      _git_log_prettily  = ''
        if ! [ -z $1 ]
            git log --pretty=$1
        end
      '';
      work_in_progress   = ''
        if git log -n 1 | grep -q -c wip
            echo "WIP!!"
        end
      '';
      nvm = "bass source ~/.nvm/nvm.sh --no-use ';' nvm $argv";
    };

    interactiveShellInit = ''
      set -U fish_color_autosuggestion 5a7f70

      if type ag &>/dev/null
          set --export FZF_DEFAULT_COMMAND 'ag -p ~/.gitignore -g ""'
      else if type rg &>/dev/null
          set --export FZF_DEFAULT_COMMAND 'rg --files --hidden --follow --no-ignore-vcs'
      end

      if test -z $ASDF_DATA_DIR
          set _asdf_shims "$HOME/.asdf/shims"
      else
          set _asdf_shims "$ASDF_DATA_DIR/shims"
      end
      if not contains $_asdf_shims $PATH
          set -gx --prepend PATH $_asdf_shims
      end
      set --erase _asdf_shims

      if set -q TMUX
          if tmux show-environment -g WAYLAND_DISPLAY 2>/dev/null | grep -q "^WAYLAND_DISPLAY="
              set -gx WAYLAND_DISPLAY (tmux show-environment -g WAYLAND_DISPLAY | cut -d= -f2)
          end
          if tmux show-environment -g DISPLAY 2>/dev/null | grep -q "^DISPLAY="
              set -gx DISPLAY (tmux show-environment -g DISPLAY | cut -d= -f2)
          end
      end
    '';
  };

  home.packages = with pkgs; [
    lazygit
    ripgrep
    fd
    fzf
    fastfetch
    bat
    wl-clipboard
  ];
}
