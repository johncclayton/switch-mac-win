#!/bin/sh
# Go Windows! - Windows (DisplayPort) fullscreen on the Dell U4021QW.
# The watcher on Windows sees the input change and moves the Deskflow cursor back.
#
# Order matters: once the Mac is no longer on screen it loses its DDC link, so
#  - Mac fullscreen: setting the input to DP is all it takes (PBP is already off);
#  - split view:     DP is already the main input, so turning PBP off finishes it.
# Whichever step makes the Mac disappear, the step after it may fail harmlessly.
M1DDC=/opt/homebrew/bin/m1ddc
"$M1DDC" set input 15 || true   # DisplayPort 1
sleep 1
"$M1DDC" set pbp 0 2>/dev/null || true   # PBP/PIP off
exit 0
