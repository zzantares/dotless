{ profile, ... }:

{
  programs.jujutsu = {
    enable = true;

    # TODO add change signing support
    settings = {
      user.name = profile.name;
      user.email = profile.email;

      ui.paginate = "auto";
      ui.pager = "less -XFRS";
    };
  };

}
