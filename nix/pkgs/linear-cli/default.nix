{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "linear-cli";
  version = "1.11.1";

  # Fetch the repository
  src = fetchFromGitHub {
    owner = "schpet";
    repo = "linear-cli";
    rev = "v${version}";
    sha256 = "sha256-os/p8P1ZFqdMFuqci0XtbDpJQP31PDfCtYSX9xFv8D4=";
  };

  # # Optional: override build phase if needed
  # buildPhase = ''
  #   # Usually you just need 'npm install' and 'npm run build'
  #   npm install
  #   npm run build
  # '';

  # Optional: specify what to install globally
  # installPhase = ''
  #   mkdir -p $out/bin
  #   cp -r . $out
  # '';

  # Node.js runtime dependency
  # propagatedBuildInputs = [ nodejs ];

  meta = with lib; {
    description = "linear without leaving the command line: list, start, and create PRs for linear issues. agent friendly.";
    license = licenses.isc;
    # maintainers = with maintainers; [ yourNameHere ];
  };
}
