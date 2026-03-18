{ pkgs, ... }:

{
  fonts = {
    enableDefaultPackages = true;

    packages = with pkgs; [
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
    ];

    fontconfig.defaultFonts = {
      monospace = [ "FiraCode Nerd Font" ];
    };
  };
}
