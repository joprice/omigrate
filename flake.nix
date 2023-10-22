{
  description = "omigrate";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs = {
      url = "github:nix-ocaml/nix-overlays";
      inputs.flake-utils.follows = "flake-utils";
    };
  };
  outputs =
    { self
    , nixpkgs
    , flake-utils
    }:
    (flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages."${system}".appendOverlays [
        (self: super: {
          ocamlPackages = super.ocaml-ng.ocamlPackages_5_1.overrideScope'
            (oself: osuper:
              with oself;
              {
                pgx = buildDunePackage {
                  pname = "pgx";
                  version = "0.0.0";
                  propagatedBuildInputs = [
                    camlp-streams
                    hex
                    ipaddr
                    logs
                    ppx_compare
                    ppx_custom_printf
                    re
                    uuidm
                  ];
                  src = self.fetchFromGitHub {
                    owner = "arenadotio";
                    repo = "pgx";
                    rev = "2bdd5182142d79710d53bf7c4da2a1f066f71590";
                    sha256 = "sha256-5HyErEM6/tnkh+hb8tNCmpVx+B5OlFEJpCQ1fNch7RA=";
                  };
                };
                pgx_value_core = buildDunePackage {
                  pname = "pgx_value_core";
                  version = "0.0.0";
                  propagatedBuildInputs = [
                    core_kernel
                    pgx
                  ];
                  inherit (pgx) src;
                };
                pgx_async = buildDunePackage {
                  pname = "pgx_async";
                  version = "0.0.0";
                  propagatedBuildInputs = [
                    conduit-async
                    core_kernel
                    pgx_value_core
                    pgx
                  ];
                  inherit (pgx) src;
                };
              }
            );
        })
      ];
      inherit (pkgs) ocamlPackages;
    in
    with ocamlPackages;
    rec {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          caqti-eio
          caqti-lwt
          caqti-driver-postgresql
          cmdliner
          fmt
          logs
          lwt
          lwt_ppx
          ocaml_sqlite3
          result
          uri
          pgx
          pgx_async
          ppx_rapper
          ppx_rapper_eio
        ];
        nativeBuildInputs = [
          dune_3
          findlib
          ocaml
          ocaml-lsp
          ocamlformat
        ];
        OCAMLRUNPARAM = "b";
      };
    }));
}
