#!/bin/bash

# This script attempts to setup a GBC dev environment
#
# Example:
# ./gbc-setup400.sh 

set_default_build()
{
LAST=$(ls -1 $GBCPROJECTDIR/fjs-${GBC}-${GBCV}.*-project.zip | tail -1 )
VER=$(echo $LAST | cut -d'-' -f3)
BLD=$(echo $LAST | cut -d'-' -f4)
}

BASE=$(pwd)

GBC=gbc
VER=$1
BLD=$2
NVMVER=12.18.4

if [ -z "$GENVER" ]; then
	echo "GENVER is not set!"
	exit 1
fi

if [ "$GENVER" = "400" ]; then
	GBCV=4
else
	GBCV=1
fi

if [ -z $GBCPROJECTDIR ]; then
	echo "WARNING: GBCPROJECTDIR is not set to location of GBC project zip file(s)"
	GBCPROJECTDIR=~/FourJs_Downloads/GBC
	echo "Defaulting GBCPROJECTDIR to $GBCPROJECTDIR"
fi
if [ ! -e $GBCPROJECTDIR ]; then
	echo "$GBCPROJECTDIR doesn't exist, aborting!"
	exit 1
fi

if [ $# -ne 2 ]; then
	set_default_build
fi

if [ -z $VER ]; then
	echo "VER is not set! aborting!"
	echo "./gbc-setup.sh 1.00.38 build201707261501"
	exit 1
fi
if [ -z $BLD ]; then
	echo "BLD is not set! aborting!"
	echo "./gbc-setup.sh 1.00.38 build201707261501"
	exit 1
fi

echo "VER=$VER BLD=$BLD"

SRC="$GBCPROJECTDIR/fjs-$GBC-$VER-$BLD-project.zip"

SAVDIR=$(pwd)
cd ..

if [ -d gbc-current$GENVER ]; then
	BLDDIR=gbc-current$GENVER
fi

if [ ! -d $BLDDIR ]; then
	mkdir -p $BLDDIR
	if [ ! -e "$SRC" ]; then
		echo "Missing $SRC Aborting!"
		exit 1
	fi
	unzip $SRC
	ln -s gbc-$VER gbc-current$GENVER
fi

cd $SAVDIR
if [ ! -d gbc-current$GENVER ]; then
	ln -s /opt/fourjs/gbc-current$GENVER ./gbc-current$GENVER
fi

cd gbc-current$GENVER

source ~/.nvm/nvm.sh
nvm install $NVMVER

