#!/bin/bash

# Introduction:
# Use when you are anxious to receive a package from Omniva and you want to monitor \
# its progress in an automated way.
# The script will request your package's status after every n seconds and notify \
# with a message and a sound (experimental) if there has been a change in the status.

# Usage:
# Enter the barcode reference instead of "<barcode_here>" or as the 1st CLI parameter.
# Enter the request interval instead of "<seconds_here>" or as the 2nd CLI parameter.
 
# variables
barcode=${1-<barcode_here>}
seconds=${2-<seconds_here>}

# initial request
a=`curl -s https://www.omniva.ee/api/search.php?search_barcode=${barcode}&lang=est`
echo -e "$a\n"

# polling
while true; do
    b=`curl -s https://www.omniva.ee/api/search.php?search_barcode=${barcode}&lang=est`

    if [[ "$a" == "$b" ]]; then
	echo "No changes yet, trying again in ${seconds} second(s) ..."
    else
        echo -e "$b\n"
        echo -e "Something seems to have changed!"
        printf '\7'; sleep 1; printf '\7'; sleep 1; printf '\7'; sleep 1; printf '\7'
	exit 0
    fi

    sleep $seconds
done

