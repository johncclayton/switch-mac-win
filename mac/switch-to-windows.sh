#!/bin/sh
# Go Windows! - Windows (DisplayPort) fullscreen on the Dell U4021QW.
# The watcher on Windows sees the input change and moves the Deskflow cursor back.
set -e
M1DDC=/opt/homebrew/bin/m1ddc
"$M1DDC" set pbp 0        # PBP/PIP off
sleep 1.5
"$M1DDC" set input 15     # DisplayPort 1
