{ pkgs, lib, config, ... }:

{
  # :: Native path management
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.config/emacs/bin"
    "$HOME/.local/share/pnpm"
    "$HOME/develop/flutter/bin"
    "$HOME/Android/Sdk/cmdline-tools/latest/bin"
    "$HOME/Android/Sdk/platform-tools"
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
    ANDROID_HOME = "$HOME/Android/Sdk";
    DOOMDIR = "$HOME/thanmatt-dotfiles/doom";
  };

  # :: zoxide — smarter cd, integrates with fish via init below
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };


  # :: SSH
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."github.com" = {
      hostname = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_ed25519";
      identitiesOnly = true;
    };
  };

  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/lazyvim";

  xdg.configFile."fastfetch".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/fastfetch";

  programs.emacs = {
    enable = true;
    package = pkgs.emacs;
  };

  home.activation.installDoom = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.config/emacs" ]; then
      echo "Installing Doom Emacs..."
      ${pkgs.git}/bin/git clone --depth 1 https://github.com/doomemacs/doomemacs "$HOME/.config/emacs" \
        || { echo "ERROR: Doom clone failed"; exit 1; }
    fi
    if [ ! -f "$HOME/.config/emacs/.installed" ]; then
      echo "Running doom install..."
      DOOMDIR="${config.home.homeDirectory}/thanmatt-dotfiles/doom" \
        "$HOME/.config/emacs/bin/doom" install --no-config --no-env --no-fonts --force \
        && touch "$HOME/.config/emacs/.installed" \
        || echo "WARNING: doom install failed — run 'doom install' manually"
    fi
  '';

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
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-save-interval '15'
          set -g @continuum-restore 'on'
        '';
      }
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

  # :: Kitty — binary via Nix, config symlinked from dotfiles
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
          sha256 = "sha256-mtFGrv79G55/6NnaOP1jkcEDOtNEYAJg8hRv2jlbFuE=";
        };
      }
    ];

    shellAliases = {
      l   = "ls -aslh";
      pls = "sudo";
      pip = "pip3";
      vi  = "nvim";
      vim = "nvim";

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

      update     = "nix flake update ~/thanmatt-dotfiles/nix-config";
      update-all = "sudo nixos-rebuild switch --flake ~/thanmatt-dotfiles/nix-config#nixos-dev";

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
      fish_greeting      = "fastfetch --logo-type small";
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
      history = "builtin history --show-time='%F %T ' $argv";

      vat = ''
        set selected (fd --type f | fzf --preview="bat --color=always --style=numbers {}")
        and vi $selected
      '';

      vig = ''
        set selected (rg --color=always --line-number --no-heading --smart-case "" | \
            fzf --ansi \
                --delimiter : \
                --preview 'bat --color=always {1} --highlight-line {2}' \
                --preview-window 'up,60%,border-bottom,+{2}+3/3,~3')

        and begin
            set file (echo $selected | cut -d: -f1)
            set line (echo $selected | cut -d: -f2)
            vi +$line $file
        end
      '';

      tmux-resurrect-fix = ''
        set resurrect_dir ~/.local/share/tmux/resurrect

        if not test -d $resurrect_dir
            echo "Error: Resurrect directory not found at $resurrect_dir"
            return 1
        end

        cd $resurrect_dir

        if not test -L last
            echo "Error: 'last' symlink not found"
            return 1
        end

        if test -s last
            echo "✓ Resurrect file is healthy (not empty)"
            return 0
        end

        echo "⚠ Found empty resurrect file, fixing..."

        set target_file (readlink last)
        rm -f $target_file
        rm -f last

        set latest_file (ls -t tmux_resurrect_*.txt 2>/dev/null | while read file
            if test -s $file
                echo $file
                break
            end
        end)

        if test -z "$latest_file"
            echo "Error: No valid resurrect files found"
            return 1
        end

        ln -s $latest_file last
        echo "✓ Fixed: 'last' now points to $latest_file"
      '';

      build-analyzer = {
        description = "Analyze build directory sizes with breakdown";
        body = ''
          set target_dir (test (count $argv) -gt 0; and echo $argv[1]; or echo ".")

          if not test -d $target_dir
              echo "❌ Directory '$target_dir' does not exist"
              return 1
          end

          echo "📊 Build Analysis for: $target_dir"
          echo "=" | string repeat 50

          set total_size (du -sh $target_dir | cut -f1)
          set total_bytes (du -sb $target_dir | cut -f1)

          echo "🗂️  Total Size: $total_size"
          echo ""

          set js_files (find $target_dir -name "*.js" -type f 2>/dev/null)
          if test (count $js_files) -gt 0
              set js_size_bytes (du -cb $js_files | tail -1 | cut -f1)
              set js_size_human (echo $js_size_bytes | numfmt --to=iec-i --suffix=B)
              set js_percent (math "round($js_size_bytes * 100 / $total_bytes)")
              echo "🟨 JavaScript: $js_size_human ($js_percent%)"
          else
              echo "🟨 JavaScript: 0B (0%)"
              set js_size_bytes 0
          end

          set css_files (find $target_dir -name "*.css" -type f 2>/dev/null)
          if test (count $css_files) -gt 0
              set css_size_bytes (du -cb $css_files | tail -1 | cut -f1)
              set css_size_human (echo $css_size_bytes | numfmt --to=iec-i --suffix=B)
              set css_percent (math "round($css_size_bytes * 100 / $total_bytes)")
              echo "🎨 CSS: $css_size_human ($css_percent%)"
          else
              echo "🎨 CSS: 0B (0%)"
              set css_size_bytes 0
          end

          set image_files (find $target_dir \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" -o -name "*.avif" \) -type f 2>/dev/null)
          if test (count $image_files) -gt 0
              set img_size_bytes (du -cb $image_files | tail -1 | cut -f1)
              set img_size_human (echo $img_size_bytes | numfmt --to=iec-i --suffix=B)
              set img_percent (math "round($img_size_bytes * 100 / $total_bytes)")
              echo "🖼️  Images: $img_size_human ($img_percent%)"

              echo "   📸 Largest images:"
              find $target_dir \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" -o -name "*.avif" \) -type f -exec du -h {} \; | sort -hr | head -3 | while read size file
                  set filename (basename $file)
                  echo "      • $filename: $size"
              end
          else
              echo "🖼️  Images: 0B (0%)"
              set img_size_bytes 0
          end

          set other_bytes (math "$total_bytes - $js_size_bytes - $css_size_bytes - $img_size_bytes")
          set other_human (echo $other_bytes | numfmt --to=iec-i --suffix=B)
          set other_percent (math "round($other_bytes * 100 / $total_bytes)")
          echo "📦 Other: $other_human ($other_percent%)"

          echo ""
          echo "🔍 File count breakdown:"
          echo "   JS files: "(count $js_files)
          echo "   CSS files: "(count $css_files)
          echo "   Images: "(count $image_files)
          echo "   Total files: "(find $target_dir -type f | wc -l)
        '';
      };
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
    neovim
    kitty
    btop
    asdf-vm
    lazygit
    ripgrep
    fd
    fzf
    fastfetch
    bat
    wl-clipboard
    firefox
    chromium
    proton-vpn-cli
  ];
}
