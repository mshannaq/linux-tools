#!/bin/bash

swap_file_location=/swapfile1

if [[ $# -gt 0 ]]
then 
echo "Swap file creator , usage $0 [swapsize] [swapfilename] , eg $0 512 /swapfile"
else 
    echo "swap file allows Linux to simulate the disk space as RAM"
    echo "This tools come from https://github.com/mshannaq/linux-tools with MIT License"
    echo "This $0 allow you to create a swap file"
    echo ""
    echo "examples:"
    echo "$0 515 /swapfile"
    echo "it will create a swap file with 512 MB size in /swapfile file"
    echo ""
    echo "$0 1024 /swapfile1"
    echo "it will create a swap file with 1024 MB (1GB) size in /swapfile1 file"
    echo ""
    echo "Note that: If RAM is less than 1 GB, swap size should be at least the size of RAM and at most double the size of RAM."
    echo "If RAM is more than 1 GB, swap size should be at least equal to the square root of the RAM size and at most double the size of RAM"

fi


if [[ $EUID > 0 ]]; then  
  echo "You must run this file as root / sudo"
  echo
  exit 1
fi

if [ -z "$1" ]
  then
    echo ""
    read -p "Enter the amount of MB of SWAP that you want to create (in mb , where 1024 means 1GB):" swap_space_inmb
  else
   swap_space_inmb=$1
fi

if [ -z "$2" ]
  then
   echo "Will create default swap file $swap_file_location"
  else
   swap_file_location=$2
fi



swap_space=$(($swap_space_inmb))

if  [ $swap_space == 0 ]; then
    echo "[ERROR] SWAP Space must be more than 0 , double check that you entered a swap storage space"
    exit 2
fi

swap_space_blocksize=$(($swap_space*1024)) 

if [ -f "$swap_file_location" ]; then
    echo "[ERROR] $swap_file_location file already exists. cannot create file"
    exit 3
fi


echo "Creating a swap file of $swap_space which is $swap_space_blocksize blocks"
dd if=/dev/zero of=$swap_file_location bs=1024 count=$swap_space_blocksize

echo "Chowning swap file $swap_file_location "
chmod 600 $swap_file_location

echo "make a file as swap $swap_file_location"
mkswap $swap_file_location

echo "swapon  file swap_file_location"
swapon $swap_file_location
echo "make a backup copy of /etc/fstab to /etc/fstab.bak"
cp -v /etc/fstab /etc/fstab.bak
echo "writing swap file defintion to /etc/fstab"
echo "$swap_file_location          swap            swap    defaults        0 0" >> /etc/fstab
echo "Looking for Memory size"
free -mh
