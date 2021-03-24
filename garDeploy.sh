#!/bin/bash

GARNAME=${2:-mobDemo}  #< your gar file name - without the .gar >
#GARNAME=${2:-mdAppSrv}  #< your gar file name - without the .gar >

SECURE=0 #< 1 or 0 - to secure the service behind GIP >

# All these value must be set correctly before the script will work.
SETUP=1 # IMPORTANT: change this to 1 when you have updated the values below!
SRV=${1:-1}
case $SRV in
0) # Local
	SRV=local
;;
1) # PI
	SRV=pi3
;;
3) # control-2
	SRV=control2
;;
*) 
	echo "Invalid server number!"
	exit 1
esac

source $SRV.srv
TOKENFILE=$SRV.tok

# These values shouldn't need to be changed.
GETTOKEN=$FGLDIR/web_utilities/services/gip/bin/gettoken/GetToken.42r
DEPLOYGAR=$FGLDIR/web_utilities/services/gip/bin/deploy/DeployGar.42r
WSSCOPE="deployment register"
GARFILE=distbin/${GARNAME}.gar
LOG=garDeploy.log
export FGLWSDEBUG=0
unset FGLPROTOKENFILE

# Sanity checks.
if [ $SETUP -eq 0 ]; then
	echo "This script has not be configured yet!"
	exit 1
fi

if [ -z $FGLDIR ]; then
	echo "FGLDIR is not set!"
	exit 1
fi

if [ ! -e $GARFILE ]; then
	echo "Gar file '$GARFILE' is missing!"
	exit 1
fi

# clear the log file if it exists
rm -f $LOG

echo "Deploy to $SRV ..."

# Get a token if we don't have a recent one.
if [ "$(find $TOKENFILE -mmin +9)" ] || [ ! -e $TOKENFILE ]; then
	echo "Getting new token file: $TOKENFILE from $GASURL ..."
	echo "fglrun $GETTOKEN client_credentials --client_id $CLIENTID --secret_id $SECRETID --idp $GASURL/ws/r/services/GeneroIdentityProvider --savetofile $TOKENFILE $WSSCOPE >> $LOG"
	fglrun $GETTOKEN client_credentials --client_id $CLIENTID --secret_id $SECRETID --idp $GASURL/ws/r/services/GeneroIdentityProvider --savetofile $TOKENFILE $WSSCOPE >> $LOG
else
	echo "Using existing token file: $TOKENFILE."
fi
if [ ! -e $TOKENFILE ]; then
	echo "Failed to get token!"
	exit 1
fi

# Get list of deployed gar's - mainly to check our access is working.
echo "Getting deployed list / checking access ..."
fglrun $DEPLOYGAR list --xml --tokenfile $TOKENFILE $GASURL > deployed.list
if [ $? -ne 0 ]; then
	echo "Failed to get deployed list!"
	cat deployed.list
	exit 1
fi

# Check if already deployed and try and undeploy it.
deployed=$( grep ARCHIVE deployed.list | grep $GARNAME >> $LOG )
if [ $? -eq 0 ]; then
	echo "Gar already deployed, attempting to disable and undeploy ..."
	echo "Disable $GARNAME ..."
	fglrun $DEPLOYGAR disable -f $TOKENFILE $GARNAME $GASURL >> $LOG
	echo "Undeploy $GARNAME ..."
	fglrun $DEPLOYGAR undeploy -f $TOKENFILE $GARNAME $GASURL >> $LOG
fi

rm deployed.list

# Deploy / Secure / Enable
echo "Deploy $GARNAME ..."
fglrun $DEPLOYGAR deploy -f $TOKENFILE $GARFILE $GASURL >> $LOG
if [ $? -ne 0 ]; then
	echo "Failed!"
	exit 1
else
	echo "Okay"
fi

if [ $SECURE -eq 1 ]; then
	echo "Secure $GARNAME ..."
	fglrun $DEPLOYGAR secure  -f $TOKENFILE $GARNAME $GASURL >> $LOG.secure
	if [ $? -ne 0 ]; then
		echo "Failed!"
		exit 1
	else
		echo "Okay"
	fi
#	SRVXCF=dfmv2.xcf
#	echo fglrun $DEPLOYGAR delegate -f $TOKENFILE $GARNAME $SRVXCF $GASURL
#	fglrun $DEPLOYGAR delegate -f $TOKENFILE $GARNAME $SRVXCF $GASURL
fi

echo "Enable $GARNAME ..."
fglrun $DEPLOYGAR enable  -f $TOKENFILE $GARNAME $GASURL >> $LOG
if [ $? -ne 0 ]; then
	echo "Failed!"
	exit 1
else
	echo "Okay"
fi

#fglrun $DEPLOYGAR connfig -f $TOKENFILE -c ${GARNAME}.json get $APPCLIENTID $GASURL/
#fglrun $DEPLOYGAR list --xml --tokenfile $TOKENFILE $GARURL | grep ARCHIVE | grep $GARNAME
fglrun $DEPLOYGAR list --xml --tokenfile $TOKENFILE $GARURL > deployed2.list
echo "Finished: " `date`

