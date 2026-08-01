{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,
}:

buildGoModule (finalAttrs: {
  pname = "tea-dash";
  version = "0.3.3";

  src = fetchFromGitHub {
    owner = "gbarany";
    repo = "tea-dash";
    tag = "v${finalAttrs.version}";
    hash = "sha256-JvSzIj40EfXRbdGaH+8PdX5hVvuPIVQW+3doFZhD8Ec=";
  };

  vendorHash = "sha256-+SoJ6ZejDQTIoetpfFu73UYskxkD9gJkr5Zixy2ii4s=";

  nativeCheckInputs = [ git ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/gbarany/tea-dash/internal/build.Version=v${finalAttrs.version}"
  ];

  meta = {
    description = "gh-dash-style terminal dashboard for Gitea and Forgejo — PRs, issues, notifications, Actions runs, and branches";
    homepage = "https://github.com/gbarany/tea-dash";
    license = lib.licenses.mit;
    mainProgram = "tea-dash";
  };
})
