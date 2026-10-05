{
  lib,
  runCommand,
  postgresql,
}:

let
  # The libpq utilities that talk to a server over the wire. Everything else in
  # that bin directory administers a local cluster - postgres, initdb, pg_ctl,
  # pg_upgrade, the WAL tools - and has no business on a workstation.
  clients = [
    "clusterdb"
    "createdb"
    "createuser"
    "dropdb"
    "dropuser"
    "pg_dump"
    "pg_dumpall"
    "pg_isready"
    "pg_restore"
    "pgbench"
    "psql"
    "reindexdb"
    "vacuumdb"
  ];
in

# nixpkgs ships no client-only postgresql, and libpq carries no binaries, so
# psql can only come from the full derivation. Nothing is thereby started: a
# server runs only where services.postgresql.enable is set. This keeps the
# server tooling off PATH so `postgres` or `initdb` cannot be reached for a
# cluster this machine is not supposed to have.
runCommand "postgresql-client-${postgresql.version}"
  {
    meta = {
      description = "psql and the other libpq client tools, without the server binaries";
      inherit (postgresql.meta) license homepage;
      platforms = lib.platforms.all;
      mainProgram = "psql";
    };
    passthru = { inherit postgresql; };
  }
  ''
    mkdir -p $out/bin $out/share/man/man1
    for tool in ${lib.escapeShellArgs clients}; do
      ln -s ${postgresql}/bin/$tool $out/bin/$tool
      if [ -e ${postgresql.man}/share/man/man1/$tool.1.gz ]; then
        ln -s ${postgresql.man}/share/man/man1/$tool.1.gz $out/share/man/man1/
      fi
    done
  ''
