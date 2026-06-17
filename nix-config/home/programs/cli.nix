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
}
