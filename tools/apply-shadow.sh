#!/usr/bin/env bash

if ! command -v magick >> /dev/null 2>&1
then
    echo "apply-shadow.sh requires imagemagick to be installed"
    exit 1
fi

if [[ -z "$1" ]]
then
    echo "usage: ./apply-shadow.sh <FRAME_DIR>"
    exit 1
fi

declare -r frameDir="$1"
declare -r frameOutDir="frames_shadowed"
mkdir "$frameOutDir"

readarray -t entries < <(ls -1 "$frameDir")

for entry in "${entries[@]}"
do
    magick "$frameDir/$entry" \( +clone -background "#8a6048" -shadow 86x2+0+0 \) +swap -background none -layers merge +repage "$frameOutDir/$entry"
done

echo "Done! Applied shadow to x${#entries[@]} frames"
