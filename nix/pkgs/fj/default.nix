{
  lib,
  buildGoModule,
  fetchFromGitea,
}:

buildGoModule (finalAttrs: {
  pname = "fj";
  version = "0.4.0";

  src = fetchFromGitea {
    domain = "forgejo.zerova.net";
    owner = "public";
    repo = "fj";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ivwqq0jRfpAQocUTAKyZSI92m+9czZTVqxJoaz9B5rQ=";
  };

  vendorHash = "sha256-yUmGAsPt44A3/EwuzIr5v8W9rw8FJ7biVBTaue8EYN0=";

  meta = {
    description = "Forgejo/Gitea CLI in the spirit of gh, with agentic dev features for AI-assisted workflows";
    homepage = "https://forgejo.zerova.net/public/fj";
    license = lib.licenses.mit;
    mainProgram = "fj";
  };
})
