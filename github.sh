#!/bin/bash
# This script is invoked from my GitHub-CI commands
# It bootstraps to grab the 'neil' tool and run 'neil test'
set -e # exit on errors
set -x # echo each line

retry(){
    ($@) && return
    sleep 15
    ($@) && return
    sleep 15
    $@
}
timer(){
    set +x
    local before=$(date +%s)
    set -x
    $@
    set +x
    local after=$(date +%s)
    echo Timing: $(expr $after - $before) spent doing $@
    set -x
}

# make sure we hlint check before running the tests, in case they generate non-compliant hlint
if [ "$HLINT_ARGUMENTS" = "" ]; then
    HLINT_ARGUMENTS=.
fi
curl -sSL https://raw.github.com/ndmitchell/hlint/master/misc/run.sh | sh -s $HLINT_ARGUMENTS

ghc --version
cabal --version
haddock --version

if [ "$INSTALL_FSATRACE" = "true" ]; then
    case $OS in
        Windows*|windows*)
            curl https://github.com/ndmitchell/shake/releases/download/fsatrace-1/fsatrace.zip -L -o fsatrace.zip
            # Important that fsatrace.exe is not in the Shake root since otherwise fsatrace*.dll is reported as
            # an untracked read - so we put 'fsatrace' one directory up.
            7z x fsatrace.zip -o../fsatrace
            export PATH=$PATH:`pwd`/../fsatrace
            ;;
        *)
            git clone https://github.com/jacereda/fsatrace.git .fsatrace
            (cd .fsatrace && make)
            export PATH=$PATH:`pwd`/.fsatrace
            ;;
    esac
    fsatrace v - -- echo fsatrace works
fi

if [ "$HASKELL_DEPENDENCIES" != "" ]; then
    retry cabal v2-build $HASKELL_DEPENDENCIES
fi

# Install dependencies
retry cabal v2-build --only-dependencies --enable-tests $CABALFLAGS

# Install the neil tool
retry git clone -b $BRANCH --depth=1 "https://github.com/$GITHUB_USER/neil" .neil
(cd .neil && retry cabal v2-install --allow-newer --flags=small --installdir=. --install-method=copy --overwrite-policy=always)

if [ "$MAKE_RELEASE" = "true" ]; then
    .neil/neil bin
    cabal v2-sdist
    cp dist-newstyle/sdist/*.tar.gz dist/
else
    timer .neil/neil test --install --cabal2
    # Make sure the output is on $PATH
    export PATH="$HOME/.cabal/bin:/home/runner/.cabal/bin:/c/Users/runneradmin/AppData/Roaming/cabal/bin:$PATH"

    # Run any additional tests, written in Haskell
    if [ -e travis.hs ]; then
        # We want to run travis.hs with the extra package in scope
        # Best way I can do that is by hijacking the Main.hs of .neil
        cp travis.hs .neil/src/Main.hs
        (cd .neil && cabal v2-install --allow-newer --flags=small --installdir=. --install-method=copy --overwrite-policy=always)
        .neil/neil
    fi

    # Check regenerating doesn't change anything
    git diff --exit-code
fi
