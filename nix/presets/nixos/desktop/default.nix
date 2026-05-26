{ ... }:

# A desktop is a bare-metal machine with a GUI session and wireless networking.

{
  imports = [ ./../bare-metal ];

  networking.networkmanager.enable = true;

  # Disables power management (improves wireless connection stability).
  networking.networkmanager.wifi.powersave = false;
}
