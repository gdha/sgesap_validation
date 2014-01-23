#!/bin/ksh
# script sgesap_validation_wrapper.sh is a wrapper script around script sgesap_validation.sh
# it takes the output of cmviewcl listed packages and try to guess if it is SAP package or not
# as for non-SAP packages we need to -s flag ; furthermore we use here the -m flag (monitor mode)
# to trim the output to the bare essentials
# When we encountered errors (exit code >1) then we may send a message to the OVO console (TBD)

###
### paramaters
###
PS4='$LINENO:=> ' # This prompt will be used when script tracing is turned on
typeset -x PRGNAME=${0##*/}                             # This script short name
typeset -x PRGDIR=$(dirname $0)                         # This script directory name
[[ $PRGDIR = /* ]] || {                                 # Acquire absolute path to the script
	case $PRGDIR in
		. ) PRGDIR=$(pwd) ;;
		* ) PRGDIR=$(pwd)/$PRGDIR ;;
	esac
	}

typeset -x ARGS="$@"                                    # the script arguments
[[ -z "$ARGS" ]] && ARGS="(empty)"                      # is used in the header
typeset -x PATH=/usr/local/CPR/bin:/sbin:/usr/sbin:/usr/bin:/usr/xpg4/bin:$PATH:/usr/ucb:.
typeset -r platform=$(uname -s)                         # Platform
typeset -r model=$(uname -m)                            # Model
typeset -r HOSTNAME=$(uname -n)                         # hostname
typeset os=$(uname -r); os=${os#B.}                     # e.g. 11.31
typeset -r SGESAP_VAL_SCRIPT=/home/gdhaese1/bin/sgesap_validation.sh
typeset -r TMPFILE=/tmp/sgesap_validation_wrapper.$$
typeset -r LOGFILE=/var/adm/log/package-validation-monitoring-results.log
typeset -r COPYLOGFILE=/var/tmp/${PRGNAME%???}-$(date '+%Y%m%d-%H%M').log
typeset    ovocmd=/opt/OV/bin/OpC/opcmsg
typeset	   mailto="gdhaese1@its.jnj.com,pmertens@its.jnj.com,lgielen1@its.jnj.com"
typeset    rc=0

#
# Possible severity settings are:
#	Critical, Major => will result in a ticket
#	Minor, Warning
#	Normal
# default severity setting
severity="Warning"

###
### functions
###
function _isnum
{
	echo $(($1+0))          # returns 0 for non-numeric input, otherwise input=output
}

function _print
{
	# arg1: counter (integer), arg2: "left string", arg3: "right string"
	typeset -i i
	i=$(_isnum $1)
	[[ $i -eq 0 ]] && i=22  # if i was 0, then make it 22 (our default value)
	printf "%${i}s %-80s " "$2" "$3"
}

function _banner
{
	# arg1 "string to print next to Purpose"
	cat - <<-EOD
	$(_line "#")
	$(_print 22 "Script:" "$PRGNAME")
	$(_print 22 "Arguments:" "$ARGS")
	$(_print 22 "Purpose:" "$1")
	$(_print 22 "OS Release:" "$os")
	$(_print 22 "Model:" "$model")
	$(_print 22 "Host:" "$HOSTNAME")
	$(_print 22 "User:" "$(whoami)")
	$(_print 22 "Date:" "$(date +'%Y-%m-%d @ %H:%M:%S')")
	$(_print 22 "Log:" "$LOGFILE")
	$(_line "#")
	EOD
}

function _line
{
	typeset -i i
	while (( i < 95 )); do
	(( i+=1 ))
	echo "${1}\c"
	done
	echo
}


function do_opcmsg {
	echo "A possible OpC message could be:"
	echo $ovocmd severity=$severity msg_grp=Applications msg_text="\"${msg}\"" a="Package Validation" object=$object -option SCRIPT=$PRGNAME
}

function _mail {
	[ -s "$LOGFILE" ] || LOGFILE=/dev/null
	expand "$LOGFILE" | mailx -s "$*" $mailto
}

###
### MAIN
###

{
_banner "Wrapper script (and monitoring) around sgesap_validation.sh"

/usr/sbin/cmviewcl -f line  > $TMPFILE
CLUSTER=$( grep ^name $TMPFILE | cut -d= -f 2 )
CLUSTER_STATE=$( grep ^status $TMPFILE | cut -d= -f 2 )
set -A CLUSTER_NODES $(grep ^node $TMPFILE | grep name= | cut -d= -f 2 )

echo "$(date '+%d-%m-%Y %H:%M:%S') Cluster $CLUSTER is $CLUSTER_STATE (nodes are ${CLUSTER_NODES[@]})"

for pkg in $( cat $TMPFILE | grep ^package | grep "name=" | grep -v -E '(ccmon|cccon)' | cut -d= -f2 )
do
	PKGLOGFILE=""	# empty the LOGFILE name (to be sure)
	echo "$(date '+%d-%m-%Y %H:%M:%S') Inspecting package $pkg"
	
	# we make now the assumption if $pkg contains a 'db' string we are dealing with SAP
	case $pkg in
	   *db*|*DB*)
		$SGESAP_VAL_SCRIPT -m $pkg
		ERRORS=$?
		;;
	   *)	$SGESAP_VAL_SCRIPT -m -s $pkg
		ERRORS=$?
		;;
	esac
	if [[ -f /tmp/sgesap_validation_LOGFILE.name ]]; then
		PKGLOGFILE=$( cat /tmp/sgesap_validation_LOGFILE.name )
	fi
	if [[ $ERRORS -eq 255 ]]; then
		if [[ -f $PKGLOGFILE ]]; then
			cat $PKGLOGFILE
		fi
	fi
	echo "$(date '+%d-%m-%Y %H:%M:%S') $pkg returned the error code $ERRORS"
	_line "="
done

} 2>&1 | tee $LOGFILE


# count the amount of FAILED lines
ERRORS=$( grep FAILED $LOGFILE | wc -l )
CLUSTER=$( grep Cluster $LOGFILE | awk '{print $4}' )
if [[ $ERRORS -gt 0 ]]; then
	rc=1
	msg="ERROR: found $ERRORS error(s) in package configurations of cluster $CLUSTER (rc=$rc)"
	severity="Major"
	object=$LOGFILE
	do_opcmsg | tee -a $LOGFILE
	echo "$(date '+%d-%m-%Y %H:%M:%S') Total amount of error(s) found is $ERRORS" | tee -a $LOGFILE
else
	echo "$(date '+%d-%m-%Y %H:%M:%S') No errors were found (rc=$rc)" | tee -a $LOGFILE
fi

echo
_line "+" | tee -a $LOGFILE
echo "$(date '+%d-%m-%Y %H:%M:%S') A copy of this logfile is saved as $COPYLOGFILE" | tee -a $LOGFILE
_line "+" | tee -a $LOGFILE

cp $LOGFILE $COPYLOGFILE
chmod 644 $COPYLOGFILE

_mail "Results of package configuration  validation on cluster $CLUSTER (rc=$rc)"

###
### cleanup and exit
###
rm -f $TMPFILE /tmp/sgesap_validation_LOGFILE.name
exit $rc
