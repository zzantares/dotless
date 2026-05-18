{
  config,
  lib,
  pkgs,
  profile,
  ...
}:

# See:
# - https://usher.dev/posts/my-email-setup/
# - https://beb.ninja/post/email/
# - https://sbr.pm/configurations/mails.html

let
  enable = false;
in
{
  programs.msmtp.enable = enable;
  programs.mbsync.enable = enable;

  services.mbsync = {
    enable = enable;
    frequency = "9/6:00:00"; # See: systemd-analyze --iterations=4 calendar '9/6:00:00'
    preExec = "${config.xdg.configHome}/mbsync/preExec";
    postExec = "${config.xdg.configHome}/mbsync/postExec";
    # TODO Make it so that config is stored under $XDG_CONFIG_HOME (enabling this isn't enough)
    # configFile = "$HOME/.config/mbsync/config";
  };

  # TODO Put these scripts in *.sh files and template it via Nix, it might be possible?
  xdg.configFile = {
    "mbsync/preExec" = {
      executable = true;
      text = ''
        #!${pkgs.stdenv.shell}

        echo "removing emails deleted from inbox that shouldn't be there anymore..."
        ${pkgs.notmuch}/bin/notmuch new --no-hooks
        ${pkgs.notmuch}/bin/notmuch search --output=files --format=text folder:/Inbox/ -tag:inbox | ${pkgs.ripgrep}/bin/rg Inbox | xargs --no-run-if-empty rm
        ${pkgs.notmuch}/bin/notmuch new --no-hooks
      '';
    };

    "mbsync/postExec" = {
      executable = true;
      text = ''
        #!${pkgs.stdenv.shell}

        echo "remove all messages tagged as deleted..."
        ${pkgs.notmuch}/bin/notmuch search --exclude=false --output=files --format=text0 tag:deleted | xargs --no-run-if-empty -0 rm

        echo "indexing new email (and update index after deleted messages)..."
        ${pkgs.notmuch}/bin/notmuch new

        echo "running afew rules on new messages..."
        ${pkgs.afew}/bin/afew ${
          if (config.home.sessionVariables ? NOTMUCH_CONFIG) then
            "-C ${config.home.sessionVariables.NOTMUCH_CONFIG}"
          else
            ""
        } --tag --new
      '';
    };
  };

  programs.notmuch = {
    enable = enable;
    new.tags = [ "new" ]; # New mail indexed will be tagged as 'new'
  };

  programs.afew = {
    enable = enable;
    extraConfig = ''
      [SpamFilter]
      [KillThreadsFilter]
      [ListMailsFilter]
      [ArchiveSentMailsFilter]
      ${profile.emailAfewRules or ""}
      [InboxFilter]
    '';
  };

  accounts.email.maildirBasePath = "Mail";

  accounts.email.accounts."${profile.email}" = {
    address = profile.email;
    flavor = "gmail.com"; # TODO should extract this from `profile.email`

    passwordCommand = "${pkgs.pass}/bin/pass email/${
      config.accounts.email.accounts."${profile.email}".address
    }";

    gpg = {
      key = profile.gpgKey or "";
      signByDefault = true;
    };

    mbsync = {
      enable = enable;
      create = "maildir";
      expunge = "both";
    };

    notmuch.enable = enable;

    msmtp = {
      enable = enable;
      # To get fingerprint use: msmtp --serverinfo --tls --tls-certcheck=off
      tls.fingerprint = profile.smtpTlsFingerprint or "";
    };

    primary = true;

    realName = profile.name;

    signature = {
      showSignature = "append";
      text = ''
        Best regards,
        ${profile.name}
        @${profile.user}:matrix.org
      '';
    };

    smtp = {
      host = "smtp.gmail.com";
      port = lib.mkForce 587;
      tls.enable = enable;
    };

    userName = config.accounts.email.accounts."${profile.email}".address;
  };
}
