{ ... }:

{
  # :: Git — native HM. Uses the new `programs.git.settings` freeform schema
  # :: (the old userName/userEmail/aliases/extraConfig options were deprecated
  # :: when HM restructured the module).
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Aethan Matthew";
        email = "me@thanmatt.me";
      };

      alias = {
        co = "checkout";
        br = "branch";
        st = "status";
        ci = "commit";
        lg = "log --graph --decorate --oneline";
      };

      init.defaultBranch = "master";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # :: delta — now its own top-level module (was programs.git.delta). Wires
  # :: itself into git via enableGitIntegration; also pulls the delta binary
  # :: into the env, which lazygit reuses below.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      dark = true;
      line-numbers = true;
      navigate = true;
    };
  };

  # :: Lazygit — mirrors the old lazygit/config.yml (delta paging). Note the
  # :: original config.yml used the invalid `git.pagers` (a list) key, so delta
  # :: never actually applied there; `git.paging` (singular) is the correct
  # :: lazygit schema, so delta now takes effect in lazygit too.
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
