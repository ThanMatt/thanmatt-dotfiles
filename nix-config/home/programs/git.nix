{ ... }:

{
  # :: Git — native HM (no git user config existed in nix before this).
  programs.git = {
    enable = true;
    userName = "Aethan Matthew";
    userEmail = "actives_forceps_0g@icloud.com";

    # :: delta as the diff pager (also pulls the delta binary into the env,
    # :: which lazygit reuses below).
    delta = {
      enable = true;
      options = {
        dark = true;
        line-numbers = true;
        navigate = true;
      };
    };

    aliases = {
      co = "checkout";
      br = "branch";
      st = "status";
      ci = "commit";
      lg = "log --graph --decorate --oneline";
    };

    extraConfig = {
      init.defaultBranch = "master";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # :: Lazygit — mirrors the old lazygit/config.yml (delta paging).
  programs.lazygit = {
    enable = true;
    settings = {
      git = {
        paging = {
          colorArg = "always";
          pager = "delta --dark --paging=never --line-numbers";
        };
        merging = {
          manualCommit = false;
          args = "";
        };
      };
    };
  };
}
