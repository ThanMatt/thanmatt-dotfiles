{ pkgs, lib, config, hmTarget, ... }:

{
  # :: Fish — single cross-platform source of truth.
  # :: Replaces the old base.nix programs.fish AND the raw fish/config.fish
  # :: (which is no longer symlinked). Linux/machine-specific bits live in
  # :: home/linux.nix as gated interactiveShellInit additions.
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
      Timestamp = "date -u +\"%Y%m%d%H%M%S\"";

      dps = "docker ps --format 'table {{.ID | printf \"%.12s\"}}\\t{{.Names | printf \"%.30s\"}}\\t{{.Status | printf \"%.20s\"}}\\t{{.Ports | printf \"%.30s\"}}\\t{{.Image | printf \"%.20s\"}}'";

      # :: Cross-platform flake ops — standalone HM applies the same way everywhere.
      update     = "nix flake update ~/thanmatt-dotfiles/nix-config";
      update-all = "home-manager switch --flake ~/thanmatt-dotfiles/nix-config#${hmTarget}";

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

    # :: FZF default command + zoxide init are handled by programs.fzf /
    # :: programs.zoxide (see cli.nix) — not duplicated here.
    interactiveShellInit = ''
      set -U fish_color_autosuggestion 5a7f70

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
}
