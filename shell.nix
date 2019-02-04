########################################################################
# shell.nix -- development environment
#
# This provides all system and haskell dependencies required to build
# the cardano-sl haskell packages with stack and cabal.
#
# To get a repl for cardano-wallet with stack:
#
#     nix-shell
#     stack ghci cardano-wallet
#
# To get a repl for cardano-wallet with cabal:
#
#     nix-shell
#     cabal new-repl cardano-wallet
#
# To run stylish-haskell over your code:
#
#     nix-shell -A fixStylishHaskell
#
#########################################################################

args@
{ iohkPkgs ? import ./. (removeAttrs args ["iohkPkgs" "pkgs"])
, pkgs ? iohkPkgs.pkgs
, ...
}:

with pkgs;
with import ./lib.nix;

let
  # Filters a haskell package set and returns only the packages which
  # are (transitive) dependencies of the cardano-sl packages.
  getCardanoSLDeps = with lib; let
    notCardano = drv: !(isCardanoSL drv.name);
    isTopLevel = name: drv: isCardanoSL name && (drv ? "override");
    getTopLevelDrvs = ps: attrValues (filterAttrs isTopLevel ps);
    sorted = ps: attrValues (listToAttrs (map (drv: { name = drv.pname; value = drv; }) ps));
  in
    ps: sorted (filter notCardano (concatMap haskell.lib.getHaskellBuildInputs (getTopLevelDrvs ps)));

  ghc = iohkPkgs.haskellPackages.ghc.withPackages getCardanoSLDeps;

  # TODO: add cabal-install (2.0.0.1 won't work)
  devTools = [ hlint iohkPkgs.haskellPackages.stylish-haskell stack curl jq ];

  shell = mkShell {
    name = "cardano-sl-env";
    buildInputs = [ ghc ] ++ devTools;
    shellHook = lib.optionalString lib.inNixShell ''
      eval "$(egrep ^export ${ghc}/bin/ghc)"
    '';
    nobuildPhase = "mkdir $out";
  };

  fixStylishHaskell = stdenv.mkDerivation {
    name = "fix-stylish-haskell";
    buildInputs = [ iohkPkgs.haskellPackages.stylish-haskell git ];
    shellHook = ''
      git diff > pre-stylish.diff
      find . -type f -not -path '.git' -not -path '*.stack-work*' -name "*.hs" -not -name 'HLint.hs' -exec stylish-haskell -i {} \;
      git diff > post-stylish.diff
      diff pre-stylish.diff post-stylish.diff > /dev/null
      if [ $? != 0 ]
      then
        echo "Changes by stylish have been made. Please commit them."
      else
        echo "No stylish changes were made."
      fi
      rm pre-stylish.diff post-stylish.diff
      exit
    '';
  };

  # Writes out a cabal new-freeze file containing the exact same
  # dependency versions as are provided by this shell.
  cabalProjectFreeze = let
    contents = ''
      -- This file is automatically generated from stack.yaml.
      constraints: ${constraints}
    '';
    constraints = lib.concatMapStringsSep ",\n             "
      makeConstraint (getCardanoSLDeps iohkPkgs.haskellPackages);
    makeConstraint = dep: "${dep.pname} ==${dep.version}";
  in
    pkgs.writeText "cabal.project.freeze" contents;

  # Environments for each cardano-sl package with nix-built dependencies.
  # These are useful if using cabal (old-build) and only working on a single package.
  packageShells = mapAttrs (_: drv: drv.env)
    (filterAttrs (name: _: isCardanoSL name) iohkPkgs.haskellPackages);

in shell // packageShells // {
  inherit fixStylishHaskell cabalProjectFreeze;
}
