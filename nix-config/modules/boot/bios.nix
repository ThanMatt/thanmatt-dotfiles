{ lib, ... }:

{
  # :: Legacy BIOS bootloader — GRUB.
  # ::
  # :: Imported when isUEFI = false (e.g. VirtualBox VMs created without
  # :: "Enable EFI" ticked, or older bare-metal hardware).
  # ::
  # :: Disk device defaults to /dev/sda. Override per-host if your install
  # :: lives elsewhere (e.g. /dev/nvme0n1) by adding to configuration.nix:
  # ::   boot.loader.grub.device = "/dev/nvme0n1";
  boot.loader.grub = {
    enable = true;
    device = lib.mkDefault "/dev/sda";
    useOSProber = false;
  };
}
