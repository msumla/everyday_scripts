#!/bin/bash
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

outfile=$filepath.mp4
dir=`dirname $outfile`
file=`basename $outfile`

if [[ ! -d $dir ]]
then
    mkdir -p $dir
    echo Kaust \"$dir\" loodud
fi

if [[ -f $outfile ]]
then
	rm $outfile 2> /dev/null
fi

while true
do
    link=$link1$counter$link2
    wget -q $link -O ->> $outfile

    if [ $? -eq 0 ]
    then
        printf "Laen alla video osa nr \"$counter\"\r" ja kirjutan faili
        let counter+=1
    else
        echo -e "\nVideo fail \"$outfile\"" on salvestatud
        break
    fi
done
