#!/bin/bash

set -e
set -x

DATE=$(which gdate >/dev/null 2>&1 && echo gdate || echo date)

if [[ -z "$EVERPARSE_HOME" ]] ; then
    # This file MUST be run from the EverParse root directory
    export EVERPARSE_HOME=$PWD
fi

if [[ -z "$SATS_TOKEN" ]] ; then
    echo Missing environment variable: SATS_TOKEN
    exit 1
fi

if [[ -z "$OS" ]] ; then
    OS=$(uname)
fi

is_windows=false
if [[ "$OS" = "Windows_NT" ]] ; then
   is_windows=true
fi

remote=https://${SATS_TOKEN}@github.com/project-everest/everparse.git

branchname=$(git rev-parse --abbrev-ref HEAD)
git diff --staged --exit-code
git diff --exit-code
git fetch $remote --tags
git pull $remote $branchname --ff-only

everparse_version=$(cat $EVERPARSE_HOME/version.txt)
everparse_last_version=$(git show --no-patch --format=%h $everparse_version || true)
everparse_commit=$(git show --no-patch --format=%h)
if [[ $everparse_commit != $everparse_last_version ]] ; then
    everparse_version=$($DATE '+v%Y.%m.%d')
    echo $everparse_version > $EVERPARSE_HOME/version.txt
    git add $EVERPARSE_HOME/version.txt
    git commit -m "Release $everparse_version"
    git tag $everparse_version
fi
#strip the v
export everparse_nuget_version=${everparse_version:1}

src/package/package.sh -zip

# push my commit and the tag
git push $remote $branchname $everparse_version

platform=$(uname -m)

if $is_windows ; then
    ext=.zip
else
    ext=.tar.gz
fi

function upload_archive () {
    archive="$1"

    docker build \
       -t everparse-release:$everparse_version \
       -f src/package/Dockerfile.release \
       --build-arg SATS_FILE=$archive \
       --build-arg SATS_TAG=$everparse_version \
       --build-arg SATS_COMMITISH=$branchname \
       --build-arg SATS_TOKEN=$SATS_TOKEN \
       .
}

upload_archive everparse_"$everparse_version"_"$OS"_"$platform""$ext"

if $is_windows ; then
    # Also upload the NuGet package to GitHub releases
    upload_archive EverParse."$everparse_nuget_version".nupkg
fi
