{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.chromium = {
    enable = lib.mkDefault true;

    package = config.lib.nixGL.wrap pkgs.google-chrome;
    # commandLineArgs = []; # strings get it from ps -o cmd

    dictionaries = with pkgs.hunspellDictsChromium; [
      en_US
    ];

    # NOTE The module can't install extensions for google-chrome and trying to do so now results in an error
    #   however I keep the list of extension IDs here because soon we should be able to switch to ungoogled-chromium
    #   which does support declarative browser extensions via Home Manager
    # Get the ID from the URL in the Chrome Store
    # extensions = [
    #   "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
    #   "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
    #   "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
    #   "edibdbjcniadpccecjdfdjjppcpchdlm" # I still don't care about cookies
    #   "oldceeleldhonbafppcapldpdifcinji" # Languagetool
    #   "pkehgijcmpdhfbdbbnkijodmdjhbjlgp" # Privacy Badger
    #   "dffbjiomnajbmlhjelpipfldgkijdemn" # URL Cleaner
    #   "kfhbhjigpkcbpmknfomdobahejfajado" # Offline QR Code Generator
    #   "iplffkdpngmdjhlpjmppncnlhomiipha" # Unpaywall
    #   "bnjglocicdkmhmoohhfkfkbbkejdhdgc" # FlowCrypt
    # ];
  };
}
