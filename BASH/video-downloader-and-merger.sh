#!/bin/bash

# Open the developer menu in the browser and filter out .m3u8 video and audio playlist files.
# Play the video and wait for the matching files to copy the hyperlinks and pass those to the script.

video_pl_link=$1
audio_pl_link=$2
filepath=$3

if [[ -z $video_pl_link ]] || [[ -z $audio_pl_link ]] || [[ -z $filepath ]]; then
    read -p 'Sisesta video faililoendi veebilink: ' video_pl_link
    read -p 'Sisesta heli faililoendi veebilink: ' audio_pl_link
    read -p 'Sisesta video väljundifaili asukoht: ' filepath
fi

video_plfile=video_plfile.$$.m3u8
audio_plfile=audio_plfile.$$.m3u8
outfile=$filepath
dir=`dirname $outfile`
file=`basename $outfile`
logfile=/tmp/$file.log
video_file=video_file.$$.mp4
audio_file=audio_file.$$.mp4

if [[ -f $logfile ]]; then
	rm $logfile 2>> $logfile
fi

if [[ -f $video_plfile ]]; then
	rm $video_plfile 2>> $logfile
fi

if [[ -f $audio_plfile ]]; then
	rm $audio_plfile 2>> $logfile
fi

if [[ -f $outfile ]]; then
	rm $outfile 2>> $logfile
fi

if [[ -f $videofile ]]; then
	rm $videofile 2>> $logfile
fi

if [[ -f $audiofile ]]; then
	rm $audiofile 2>> $logfile
fi

if [[ ! -d $dir ]]; then
    mkdir -p $dir
    echo Loodud kaust \"$dir\".
    echo Loodud kaust \"$dir\". >> $logfile
fi

wget -q $video_pl_link -O $video_plfile || wget --no-check-certificate -q $video_pl_link -O $video_plfile

while read line; do
    link=`echo "$line" | grep -oe http.*\.mp4 -oe http.*\.m4s`
    if [[ ! -z "$link" ]]; then
        wget -q $link -O ->> $video_file || wget --no-check-certificate -q $link -O ->> $video_file
        printf "Laen alla \"$file\" video segmenti URL-ilt \"$link\".\r"
        echo Laen alla video \"$file\" segmenti URL-ilt \"$link\". .. >> $logfile
    else
        continue
    fi

done < $video_plfile

echo -e "\nVideo fail \"$video_file\" on salvestatud."
echo Video fail \"$video_file\" on salvestatud. >> $logfile

wget -q $audio_pl_link -O $audio_plfile || wget --no-check-certificate -q $audio_pl_link -O $audio_plfile

while read line; do
    link=`echo "$line" | grep -oe http.*\.mp4 -oe http.*\.m4s`
    if [[ ! -z "$link" ]]; then
        wget -q $link -O ->> $audio_file || wget --no-check-certificate -q $link -O ->> $audio_file
        printf "Laen alla \"$file\" heli segmenti URL-ilt \"$link\".\r"
        echo Laen alla heli \"$file\" segmenti URL-ilt \"$link\". .. >> $logfile
    else
        continue
    fi

done < $audio_plfile

echo -e "\nHeli fail \"$audio_file\" on salvestatud."
echo Heli fail \"$audio_file\" on salvestatud. >> $logfile

echo -e "Video fail \"$video_file\" ja heli fail \"$audio_file\" ühendatakse \"$outfile\" faili."
echo Video fail \"$video_file\" ja heli fail \"$audio_file\" ühendatakse \"$outfile\" faili. >> $logfile

ffmpeg -i $video_file -i $audio_file -c copy $outfile >> $logfile 2>&1

echo -e "\"$outfile\" on valmis."
echo \"$outfile\' on valmis. >> $logfile

rm $video_plfile $audio_plfile $video_file $audio_file
