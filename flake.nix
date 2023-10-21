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
          lwt
          lwt_ppx
          cmdliner
          result
          logs
          fmt
          sqlite3
        ];
        nativeBuildInputs = [
          findlib
          ocaml
          ocaml-lsp
          dune_3
          ocamlformat
        ];
        OCAMLRUNPARAM = "b";
      };
    }));
}
