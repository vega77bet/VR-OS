#!/bin/bash
set -euo pipefail
# A small, original H-SBS clip for eye routing and stereo depth checks.
# Requires ffmpeg; generated media is not a film download.
ffmpeg -y -f lavfi -i "color=c=0x202630:s=1280x720:r=30:d=8" \
  -vf "drawgrid=w=64:h=72:t=1:c=white@0.15,drawbox=x=320:y=155:w=160:h=160:c=cyan:t=fill,drawbox=x=948:y=155:w=160:h=160:c=cyan:t=fill,drawbox=x=180:y=420:w=120:h=120:c=yellow:t=fill,drawbox=x=826:y=420:w=120:h=120:c=yellow:t=fill,drawbox=x=2:y=2:w=636:h=716:c=blue:t=4,drawbox=x=642:y=2:w=636:h=716:c=red:t=4" \
  -c:v libx264 -pix_fmt yuv420p -crf 22 -movflags +faststart -an \
  "${1:-VR-OS-demo-H-SBS.mp4}"
