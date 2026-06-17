{ pkgs, lib, config, ... }:

{
  # :: Neovim config (LazyVim) symlinked from dotfiles — too large to express
  # :: natively, kept as an out-of-store symlink so it stays editable in-repo.
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/lazyvim";

  # :: Emacs + Doom. Doom config (DOOMDIR) lives in the dotfiles repo and is set
  # :: via home.sessionVariables in common.nix. Doom itself is cloned on first
  # :: activation (cross-platform; reads DOOMDIR).
  programs.emacs = {
    enable = true;
    package = pkgs.emacs;
  };

  home.activation.installDoom = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # :: `doom install` shells out to `emacs` (and uses git for package clones),
    # :: but neither is on PATH during HM activation — put them there explicitly,
    # :: otherwise the install silently fails ("failed to run Emacs with command
    # :: 'emacs'") and Doom is left cloned-but-uninstalled.
    export PATH="${config.programs.emacs.finalPackage}/bin:${pkgs.git}/bin:$PATH"
    if [ ! -d "$HOME/.config/emacs" ]; then
      echo "Installing Doom Emacs..."
      git clone --depth 1 https://github.com/doomemacs/doomemacs "$HOME/.config/emacs" \
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
}
