{ ... }:

{
  # :: UEFI bootloader — systemd-boot.
  # ::
  # :: Imported when isUEFI = true (default for most modern hardware).
  # :: Assumes the EFI System Partition is mounted at /boot.
  # :: If your ESP is at /boot/efi, override in the host's configuration.nix:
  # ::   boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
