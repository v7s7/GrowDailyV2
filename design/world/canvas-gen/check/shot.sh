#!/bin/zsh
# usage: shot.sh out.png w h cellw cellh file1 file2 ...
out=$1; W=$2; H=$3; cw=$4; ch=$5; shift 5
page=$PWD/_grid.html
echo "<!doctype html><html><body style='margin:0;display:flex;flex-wrap:wrap;gap:8px;background:#888'>" > $page
for f in "$@"; do echo "<iframe src='file://$PWD/$f' style='width:${cw}px;height:${ch}px;border:0;background:#fff'></iframe>" >> $page; done
echo "</body></html>" >> $page
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --allow-file-access-from-files --hide-scrollbars --virtual-time-budget=3000 --window-size=$W,$H --screenshot=$PWD/$out file://$page 2>/dev/null
