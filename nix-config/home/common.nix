{ pkgs, lib, config, ... }:

{
  # :: Cross-platform home-manager core. Imported by both home/linux.nix and
  # :: home/darwin.nix. Everything here must evaluate on Linux AND macOS —
  # :: platform-specific bits live in the importing module.
  imports = [
    ./programs/shell.nix
    ./programs/tmux.nix
    ./programs/git.nix
    ./programs/cli.nix
    ./programs/terminals.nix
    ./programs/editors.nix
  ];

  # :: Standalone HM: let it manage itself so `home-manager` is on PATH everywhere.
  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    DOCKER_BUILDKIT = "1";
    COMPOSE_DOCKER_CLI_BUILD = "1";
    PNPM_HOME = "$HOME/.local/share/pnpm";
    COLORTERM = "truecolor";
    DOOMDIR = "${config.home.homeDirectory}/thanmatt-dotfiles/doom";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.config/emacs/bin"
    "$HOME/.local/share/pnpm"
  ];

  programs.ssh = {
    enable = true;
    # :: Keep HM's old default-host block off — avoids the deprecated
    # :: settings."*" defaults and their separate warning.
    enableDefaultConfig = false;
    # :: New freeform schema (replaces the deprecated camelCase matchBlocks):
    # :: attr name → `Host github.com`, OpenSSH directive names used verbatim.
    settings."github.com" = {
      HostName = "github.com";
      User = "git";
      IdentityFile = "~/.ssh/id_ed25519";
      IdentitiesOnly = true;
    };
  };

  # :: Cross-platform CLI toolbelt. Tools enabled via programs.* (git, lazygit,
  # :: bat, fzf, zoxide, tmux, alacritty, ghostty, kitty, fastfetch, emacs) bring
  # :: their own binaries.
  home.packages = with pkgs; [
    neovim
    btop
    asdf-vm
    ripgrep
    fd
    curl
    wget
  ];
}
