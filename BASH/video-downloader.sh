#!/bin/bash

# Open the developer menu in the browser and filter out .ts files. Play the video and wait for the first segment to copy the hyperlink.

link1=$1
counter=$2
link2=$3
filepath=$4

if [[ -z $link1 ]] || [[ -z $counter ]] || [[ -z $link2 ]] || [[ -z $filepath ]]
then
    read -p 'Sisesta video veebilingi esimene pool: ' link1
    read -p 'Sisesta video veebilingi muutuja arv: ' counter
    read -p 'Sisesta video veebilingi teine pool: ' link2
    read -p 'Sisesta video faili asukoht: ' filepath
fi

logfile=$filepath.log
outfile=$filepath
dir=`dirname $outfile`
file=`basename $outfile`

if [[ -f $logfile ]]
then
	rm $logfile 2>> $logfile
fi

if [[ -f $outfile ]]
then
	rm $outfile 2>> $logfile
fi

if [[ ! -d $dir ]]
then
    mkdir -p $dir
    echo Loodud kaust \"$dir\".
    echo Loodud kaust \"$dir\". >> $logfile
fi

while true
do
    link=$link1$counter$link2
    wget -q $link -O ->> $outfile || wget --no-check-certificate -q $link -O ->> $outfile

    if [ $? -eq 0 ]
    then
        printf "Laen alla video \"$file\" segmenti nr \"$counter\" ..\r"
        echo Laen alla video \"$file\" segmenti nr \"$counter\" .. >> $logfile
        let counter+=1
    else
        echo -e "\nVideo fail \"$outfile\" on salvestatud."
        echo Video fail \"$outfile\" on salvestatud. >> $logfile
        break
    fi
done
