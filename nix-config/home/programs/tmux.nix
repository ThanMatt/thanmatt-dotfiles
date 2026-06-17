{ pkgs, lib, config, ... }:

let
  # :: Clipboard bridge differs per platform: wl-copy on Wayland, pbcopy on macOS.
  copyCmd = if pkgs.stdenv.isDarwin then "pbcopy" else "wl-copy";
in
{
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
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${copyCmd}"
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "${copyCmd}"

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

      # Set the foreground/background color for the active window
      setw -g window-active-style fg=colour15,bg=colour235

      # Set the foreground/background color for all other windows
      setw -g window-style fg=colour245,bg=colour236
    '';
  };
}
