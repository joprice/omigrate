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
          ocamlPackages = super.ocaml-ng.ocamlPackages_5_1;
        })
      ];
      inherit (pkgs) ocamlPackages;
    in
    with ocamlPackages;
    rec {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          caqti-driver-postgresql
          caqti-lwt
          cmdliner
          fmt
          logs
          lwt
          lwt_ppx
          ocaml_sqlite3
          result
          uri
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
