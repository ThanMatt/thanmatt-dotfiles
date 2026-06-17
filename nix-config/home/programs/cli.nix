{ ... }:

{
  # :: bat — gruvbox to match the terminal themes.
  programs.bat = {
    enable = true;
    config = {
      theme = "gruvbox-dark";
    };
  };

  # :: fzf — replaces the inline FZF_DEFAULT_COMMAND setup that used to live in
  # :: fish interactiveShellInit. enableFishIntegration wires up the keybindings.
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultCommand = "rg --files --hidden --follow --no-ignore-vcs";
  };

  # :: zoxide — smarter cd, fish integration.
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # :: fastfetch — native HM (was a raw config.jsonc symlink). Used by fish_greeting.
  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      display.separator = " : ";
      modules = [
        "title"
        "separator"
        "os"
        "cpu"
        "kernel"
        "shell"
        "memory"
        "disk"
        "separator"
        "colors"
      ];
    };
  };
}
