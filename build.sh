#!/bin/sh

TARGET_DIR=./build
OPTS="--output-path $TARGET_DIR --perl /usr/bin/perl"

mkdir -p $TARGET_DIR || exit 1

# Special case for static folder, rsync to the build dir
perl ./build-perldoc-static.pl $OPTS --template opera.tt --download
rsync -av static-html/build/* $TARGET_DIR
rm -rf static-html/build

perl ./build-perldoc-dist.pl $OPTS
perl ./build-perldoc-js.pl   $OPTS
#perl ./build-perldoc-pdf.pl $OPTS
perl ./build-perldoc-html.pl $OPTS --template opera.tt --download

