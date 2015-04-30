#!/usr/bin/ksh
#
# SGeSAP Validation script for Serviceguard A.11.20 and higher in
# combination with SGeSAP extentions
# This script checks the serviceguard configuration whether the
# minimum parameters are setup correctly

# $Id: sgesap_validation.sh,v 1.8 2015/04/02 12:47:36 gdhaese1 Exp $

[[ -f /etc/cmcluster.conf ]] && . /etc/cmcluster.conf

#
# Parameters
#
PS4='$LINENO:=> ' # This prompt will be used when script tracing is turned on
typeset -x PRGNAME=${0##*/}                             # This script short name
typeset -x PRGDIR=$(dirname $0)                         # This script directory name
[[ $PRGDIR = /* ]] || {					# Acquire absolute path to the script
	case $PRGDIR in
		. ) PRGDIR=$(pwd) ;;
		* ) PRGDIR=$(pwd)/$PRGDIR ;;
	esac
	}

typeset -x ARGS="$@"                                    # the script arguments
[[ -z "$ARGS" ]] && ARGS="(empty)"			# is used in the header
typeset -x PATH=/usr/local/CPR/bin:/sbin:/usr/sbin:/usr/bin:/usr/xpg4/bin:$PATH:/usr/ucb:.
typeset -r platform=$(uname -s)                         # Platform
typeset -r model=$(uname -m)                            # Model
typeset -r HOSTNAME=$(uname -n)                         # hostname
typeset os=$(uname -r); os=${os#B.}                     # e.g. 11.31
typeset -r dlog=/var/tmp
#typeset instlog=$dlog/${PRGNAME%???}-$(date '+%Y%m%d-%H%M').scriptlog          # log file
typeset -x LOGFILE=					# will be set in the MAIN section
typeset -x ERRcode=0					
typeset -x DEBUG=                                       # by default no debugging enabled (use -d to do so)
typeset -x PKGname=""					# empty by default
typeset -x PKGnameConf=""				# empty by default
typeset -x TestSGeSAP=1					# Test the Serviceguard SGeSAP extention in the conf
							# (by default we test SGeSAP stuff too) - use -s to turn off
typeset -x oracle="oracle"				# default oracle account
typeset -x orasid="UNKNOWN"				# define it to please SAP WebDispatcher
typeset -x sidadm="UNKNOWN"				# define it to please SAP WebDispatcher
typeset -x SAPWEBDISPATCHER=0				# SAP WebDispatcher check (is a subset of SGeSAP extention)
typeset -x CONCLUSTERAWARE=N				# default setting N - package is not part of continental cluster
typeset -x RECOVERYCLUSTERACTIVE=N			# default setting N - package is not running on recovery cluster
typeset -x MONITORMODE=0				# by default do not run in monitor mode (use -m flag)
typeset -x PKGstatus=""					# Package status can be up, down
typeset -x account_is_expired=0				# we use this to indicate if an account has been expired (1)
typeset -r SENDMAIL=/usr/lib/sendmail			# used by function GenerateHTMLMail
typeset -x ERS_PACKAGE=0				# variable ERS_PACKAGE=1 means an ERS package (must have resource)
typeset -x PKGrunningNode=""				# variable contains hostname on which package is running
########################################################################################################################
#
# Functions
#
########################################################################################################################

function _echo
{
	case $platform in
		Linux|Darwin) arg="-e " ;;
	esac
	echo $arg "$*"
} # echo is not the same between UNIX and Linux

function _note
{
	_echo " ** $*"
} 

function _error
{
	printf " *** ERROR: $* \n"
	if [[ -f $LOGFILE ]]; then
		echo "  Log file for $PKGname is saved as $LOGFILE" >> $LOGFILE
	fi
	exit 255
}

function _warning
{
	printf " *** WARN: $* \n"
}

function _ok
{
	echo "[  OK  ]"
}

function _nok
{
	ERRcode=$((ERRcode + 1))
	echo "[FAILED]"
}

function _skip
{
	echo "[ SKIP ]"
}

function _warn
{
	echo "[ WARN ]"
}

function _askYN
{
	# input arg1: string Y or N; arg2: string to display
	# output returns 0 if NO or 1 if YES so you can use a unary test for comparison
	typeset answer

	case "$1" in
		Y|y)	order="Y/n" ;;
		*)	order="y/N" ;;
	esac

	_echo "$2 $order ? \c"
	read answer

	case "$1" in
		Y|y)
			if [[ "${answer}" = "n" ]] || [[ "${answer}" = "N" ]]; then
				return 0
			else
				return 1
			fi
			;;
		*)
			if [[ "${answer}" = "y" ]] || [[ "${answer}" = "Y" ]]; then
				return 1
			else
				return 0
			fi
			;;
	esac

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
	$(_line "#")
	EOD
}

function _print
{
	# arg1: counter (integer), arg2: "left string", arg3: "right string"
	typeset -i i
	i=$(_isnum $1)
	[[ $i -eq 0 ]] && i=22	# if i was 0, then make it 22 (our default value)
	printf "%${i}s %-80s " "$2" "$3"
}

function MailHeaders
{
    # input parameter (string of text) is used for subject line
    echo "From: ${FromUser:-root}"
    echo "To: ${ToUser:-root}"
    echo "Subject: $*"
    echo "Content-type: text/html"
    echo "$*" | grep -q "FAILED"
    if [[ $? -eq 0 ]]; then
        echo "Importance: high"
        echo "X-Priority: 1"
    else
        echo "Importance: normal"
        echo "X-Priority: 3"
    fi
    echo ""
}

function StartOfHtmlDocument
{
    # define HTML style (this function should be called 1st)
    echo '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2//EN">'
    echo '<HTML> <HEAD>'
    echo "<META NAME=\"CHANGED\" CONTENT=\" $(date) \">"
    echo "<META NAME=\"DESCRIPTION\" CONTENT=\"$PRGNAME\">"
    echo "<META NAME=\"subject\" CONTENT=\"Results of $PRGNAME\">"
    echo '<style type="text/css">'
    echo "Pre     {Font-Family: Courier-New, Courier;Font-Size: 10pt}"
    echo "BODY        {FONT-FAMILY: Arial, Verdana, Helvetica, Sans-serif; FONT-SIZE: 12pt;}"
    echo "A       {FONT-FAMILY: Arial, Verdana, Helvetica, Sans-serif}"
    echo "A:link      {text-decoration: none}"
    echo "A:visited   {text-decoration: none}"
    echo "A:hover     {text-decoration: underline}"
    echo "A:active    {color: red; text-decoration: none}"
    echo "H1      {FONT-FAMILY: Arial, Verdana, Helvetica, Sans-serif;FONT-SIZE: 20pt}"
    echo "H2      {FONT-FAMILY: Arial, Verdana, Helvetica, Sans-serif;FONT-SIZE: 14pt}"
    echo "H3      {FONT-FAMILY: Arial, Verdana, Helvetica, Sans-serif;FONT-SIZE: 12pt}"
    echo "DIV, P, OL, UL, SPAN, TD"
    echo "{FONT-FAMILY: Arial, Verdana, Helvetica, Sans-serif;FONT-SIZE: 11pt}"
    echo "</style>"
}

function SetTitleOfDocument
{
    # define title of HTML document and start of body (should be called 2th)
    echo "<TITLE>${PRGNAME} - $(hostname)</TITLE>"
    echo "</HEAD>"
    echo "<BODY>"
    echo "<CENTER>"
    echo "<H1> <FONT COLOR=blue>"
    echo "<P><hr><B>${PRGNAME} - $(hostname) - $*</B></P>"
    echo "</FONT> </H1>"
    echo "<hr> <FONT COLOR=blue> <small>Created on \"$(date)\" by $PRGNAME</small> </FONT>"
    echo "</CENTER>"
}

function EndOfHtmlDocument
{
    echo "</BODY> </HTML>"
}

function CreateTable
{
    # start of a new HTML table
    echo "<table width=100% border=0 cellspacing=0 cellpadding=0 style=\"border: 0 solid #000080\">"
}

function EndTable
{
    # end of existing HTML table
    echo "</table>"
}

function TableRow
{
    # function should be called when we are inside a table
    typeset row="$1"
    columns=""
    typeset color=${2:-white}  # default background color is white
    typeset -i c=0

    case "$( echo "$row" | cut -c1-3 )" in
        "** " ) columns[0]='**'
		row=$( echo "$row" | cut -c4- )
                ;;
	"== " ) columns[0]="==" 
                row=$( echo "$row" | cut -c4- )
                ;;
	*     ) columns[0]=""  ;;
    esac
    columns[1]=$( echo "$row" |  sed -e 's/\(.*\)\[.*/\1/' )   # the text with ** and [ ... ]
    echo "$row" | grep -q '\['
    if [[ $? -eq 0 ]]; then
        columns[2]=$( echo "$row" | sed -e 's/.*\(\[.*\]\)/\1/' )  # contains [  OK  ]
    else
        columns[2]=""
    fi
    # set the colors correct
    case "$( echo "${columns[2]}" | sed -e 's/\[//;s/\]//' -e 's/ //g' )" in
	"OK")		color="#00CA00" ;;	# greenish
	"FAILED")	color="#FF0000" ;;	# redish
	"WARN")
		if [[ "${columns[0]}" = "**" ]]; then
			color="#E8E800"		# yellow alike
		else
			color="#FB6104"		# orange alike
		fi
		;;
	"SKIP")		color="#000000" ;;	# black
    esac
    
    echo "<tr bgcolor=\"$color\">"

    while (( $c < ${#columns[@]} )); do
	if [[ "$color" = "#FF0000" ]] || [[ "$color" = "#FB6104" ]] || [[ "$color" = "#000000" ]]; then
		# foreground color white if background color is redish or orangish or black
		echo "  <td align=left><font size=-1 color="white">\c"
	else
        	echo "  <td align=left><font size=-1>\c"
	fi
	str=$( echo "${columns[c]}" | sed -e 's/^[:blank:]*//;s/[:blank:]*$//' )  # remove leading/trailing spaces
        [[ $c -eq 1 ]] && printf "<b>$str</b>" || printf "$str"
        echo "</td>"
        c=$((c + 1))
    done
    echo "</tr>"
}

function GenerateHTMLMail
{
    # input parameter (string of text) is used for subject line
    MailHeaders "$*"
    StartOfHtmlDocument
    SetTitleOfDocument "$*"
    CreateTable
    cat $LOGFILE | while read LINE
    do
        TableRow "$LINE"
    done
    EndTable
    EndOfHtmlDocument
}

function _whoami
{
	if [ "$(whoami)" != "root" ]; then
		_error "$(whoami) - You must be root to run this script $PRGNAME"
	fi
}

function _osrevision
{
	case $platform in
		HP-UX) : ;;
		*) _error "Script $PRGNAME does not support platform $platform" ;;
	esac
	_print 3 "**" "Running on $platform $os" ; _ok
}

function _is_var_empty
{
	[[ -z "$1" ]] && return 1
	return 0
}

function _date
{
	echo $(date '+%Y-%b-%d')	# format: 2012-Aug-06
}

function _my_grep
{
	# input arg1: "string to find" arg2: "string to be searched"
	echo "$2" | grep -q "$1"  && echo 1 || echo 0
}

function _isnum
{
	echo $(($1+0))		# returns 0 for non-numeric input, otherwise input=output
}

function _show_help_sgesap_validation
{
	cat - <<-end-of-text
	Usage: $PRGNAME [-d] [-s] [-h] [-f] [-M mail_address] package_name

	-d:	Enable debug mode (by default off)
	-s:	Disable SGeSAP testing in package configuration file
	-f:	Force the read the local package_name.conf file instead of the one from cmgetconf
	-m:	Monitor mode (less output) shows only warnings and failed lines
	-M:	Add one or more mail addresses with "mail-address1, mail-address2"
	-w:	SAP WebDispatcher
	-h:	Show usage [this page]

	end-of-text
}

function _validOS
{
	[[ "$os" = "11.31" ]] || _error "$PRGNAME only run on HP-UX 11.31 (and not on $os)"
	_osrevision
}

function _validSG
{
	release=$(/usr/sbin/swlist T1905CA.ServiceGuard | tail -1 | awk '{print $2}')
	rc=$(_my_grep "A.11.20" $release)
	if [[ $rc -eq 1 ]]; then
		_print 3 "**" "Serviceguard $release is valid" ; _ok
	else
		_error "Serviceguard $release is not valid (expecting A.11.20.*)"
	fi
}

function _validSGeSAP
{
	release=$(/usr/sbin/swlist T2803BA | tail -1 | awk '{print $2}')
	rc=$(_my_grep "B.05.10" $release)
	if [[ $rc -eq 1 ]]; then
		_print 3 "**" "Serviceguard Extension for SAP $release is valid" ; _ok
	else
		_print 3 "==" "Serviceguard Extension for SAP $release is not valid (expecting B.05.10)"; _warn
	fi
}

function _isPkgContinentalClusterAware
{
	# purpose is define 2 variables CONCLUSTERAWARE=[Y|N] and RECOVERYCLUSTERACTIVE=[Y|N] (defaults are N for both)
	# no input arguments; no output args except defining the vars
	# 1st: check if continental cluster software is installed; if not no need to proceed
	_check_continental_cluster_software || return 0
	# 2th: collect the CCCONFIG_FILE (we need the cmviewconcl executable)
	_collectContinentalClusterConfigurationFile || return 0
	# 3th: check if we are continental cluster aware - guess yes as we are still here
	_continentalClusterAware
	_debug "CONCLUSTERAWARE=$CONCLUSTERAWARE"
	_debug "RECOVERYCLUSTERACTIVE=$RECOVERYCLUSTERACTIVE"
	rm -f $CCCONFIG_FILE
}

function _check_continental_cluster_software
{
	# T2346BA  A.08.00.00     HP Continentalclusters
	/usr/sbin/swlist T2346BA,r\>=A.08.00.00 >/dev/null 2>&1
	return $?
}

function _collectContinentalClusterConfigurationFile
{
	# run a cmviewconcl command and collect the configuration file
	# input args: none; output args: 0 (cmviewconcl OK) or 1 (failure)
	type /usr/sbin/cmviewconcl >/dev/null 2>&1
	rc=$?
	if [[ $rc -eq 0 ]]; then
		CCCONFIG_FILE=/tmp/CCCONFIG_FILE.txt
		# it is important to keep the redirect from /dev/null - if you remove it, the while
		# loop will exit after the first iteration.  (this is comparable to the -n option for ssh)
		/usr/sbin/cmviewconcl </dev/null  >$CCCONFIG_FILE 2>&1
		rc=$?
	fi
	return $rc
}

function _continentalClusterAware
{
	# define CONCLUSTERAWARE and RECOVERYCLUSTERACTIVE
	CCCONFIG_FILE=/tmp/CCCONFIG_FILE.txt
	CC_NAME=$( grep "^CONTINENTAL CLUSTER" $CCCONFIG_FILE | awk '{print $3,$4}' )
	_debug "Continental Cluster name is $CC_NAME"
	PRIM_CL=$( _find_and_print_x_lines "PRIMARY CLUSTER" 2 $CCCONFIG_FILE | tail -1 | awk '{print $1}' )
	REC_CL=$( grep "RECOVERY CLUSTER" $CCCONFIG_FILE | awk '{print $3}' )
	_debug "Primary cluster name is $PRIM_CL"
	_debug "Recovery cluster name is $REC_CL"
	PRIM_CL_STATUS=$( _find_and_print_x_lines "PRIMARY CLUSTER" 2 $CCCONFIG_FILE | tail -1 | awk '{print $2}' )
	if [[ ! -z "$PRIM_CL_STATUS" ]]; then
		if [[ "$PRIM_CL_STATUS" = "up" ]]; then
			_debug "Primary cluster ($PRIM_CL) status is \"$PRIM_CL_STATUS\""
			CONCLUSTERAWARE=Y
			RECOVERYCLUSTERACTIVE=N
		else
			CONCLUSTERAWARE=Y
			_debug "Primary cluster ($PRIM_CL) status is \"$PRIM_CL_STATUS\""
			# check now if recovery cluster is up!
			grep recovery $CCCONFIG_FILE | grep -q up
			if [[ $? -eq 0 ]]; then
				_debug "Recovery cluster ($REC_CL) status is \"up\""
				RECOVERYCLUSTERACTIVE=Y
			else
				_debug "Recovery cluster status is down"
				RECOVERYCLUSTERACTIVE=N
			fi
		fi
	else
		_debug "Primary and recovery cluster status are not known"
	fi
}

function _find_and_print_x_lines
{
	# find a keyword (string) and print x nr of lines after that keyword (line of keyword included)
	# input args: $1 (string to find); $2=integer (amount of lines); $3=filename to search in
	# output: lines of text
	awk '/'"$1"'/ {p = '"$2"'} p > 0  {print $0; p--}' $3
}


function _validCluster
{
	out=$(cmviewcl -l cluster 2>&1 | tail -1)
	echo $out | grep -q up
	rc=$?
	if [[ $rc -eq 0 ]]; then
		_print 3 "**" "A valid cluster $(echo $out | awk '{print $1}') found, which is running (up)" ; _ok
		#_print 3 " "  "$out"
		#printf "\n"	# to have a proper linefeed
	else
		_error "Cluster is not up or not configured (yet)"
	fi
}

function _isPkgConfigured
{
	# we use this function to determine if pkg is running or not (=new pkg)
	#cmviewcl -f line -p $PackageNameDefined > /tmp/isPkgConfigured.txt 2>&1
	cmviewcl -f line | grep ^package | grep name= | cut -d= -f2 >/tmp/isPkgConfigured.txt
	PKGname_tmp=${PKGname##*/}       # if PKGname was a filename
	PKGname_tmp=${PKGname_tmp%.*}    # remove .conf
	grep -q "$PKGname_tmp" /tmp/isPkgConfigured.txt
	if [[ $? -ne 0 ]]; then
		# pkg is not running
		_print 3 "==" "Package $PKGname_tmp is \"not\" (yet) a configured package" ; _warn
		ForceCMGETCONF=0
	else
		_print 3 "**" "Package $PKGname_tmp is a configured package (cluster $(cmviewcl -fline | grep ^name= | cut -d= -f2))" ; _ok
		ForceCMGETCONF=1
	fi
}

function _isPkgRunning
{
	# purpose is to verify if package is running or not and we set a variable PKGstatus=(up|down|notconfigured)
	PKGname_tmp=${PKGname##*/}       # if PKGname was a filename
	PKGname_tmp=${PKGname_tmp%.*}    # remove .conf
	cmviewcl -f line -p $PKGname_tmp >/tmp/isPkgRunning.txt 2>/tmp/isPkgRunning.txt
	grep -q "is not a configured package name" /tmp/isPkgRunning.txt
	if [[ $? -eq 0 ]]; then
		_print 3 "==" "Package $PKGname_tmp is \"not\" (yet) a running package" ; _skip
		PKGstatus="notconfigured"
		return
	fi
	PKGstatus=$( grep status= /tmp/isPkgRunning.txt | cut -d= -f2 )
	# if PKGstatus=down then we should not check FS stuff as the VGs are not available anyway
	case $PKGstatus in
		"up")	_print 3 "**" "Package $PKGname_tmp is up and running" ; _ok
			;;
		"down")	# be careful if CONCLUSTERAWARE=Y and RECOVERYCLUSTERACTIVE=N
			if [[ "$CONCLUSTERAWARE" = "N" ]]; then
				_print 3 "==" "Package $PKGname_tmp is \"not\" running" ; _nok
			else
				# CONCLUSTERAWARE=Y
				if [[ "$RECOVERYCLUSTERACTIVE" = "N" ]]; then
					_print 3 "**" "Package $PKGname_tmp is \"not\" running" ; _ok
				else
					_print 3 "==" "Package $PKGname_tmp is \"not\" running" ; _nok
				fi
			fi
			;;
		*)	_print 3 "==" "Package $PKGname_tmp has shows status=$PKGstatus" ; _warn
			;;
	esac

}

function _checkPKGname
{
	[[ -z $PKGname ]] && PKGname_tmp=empty || PKGname_tmp=$PKGname
	# PKGname_tmp could be a file name
	# Try to extract a package_name (best effort only!)
	if [[ -f $PKGname_tmp ]]; then
		PKGname_tmp=${PKGname_tmp##*/}    # remove everything before last /, ./pkg.conf becomes pkg.conf
		PKGname_tmp=${PKGname_tmp%.*}     # remove .*, pkg.conf becomes pkg
		PKGname=$PKGname_tmp
	fi
	find $SGCONF  ! -type f 2>/dev/null | grep -q $PKGname_tmp 2>/dev/null
	rc=$?
	if [[ $rc -eq 0 ]]; then
		_print 3 "**" "Package directory ($PKGname_tmp) found under $SGCONF" ; _ok
	else
		_print 3 "==" "Package directory ($PKGname_tmp) does not exist on $HOSTNAME" ; _warn
	fi
}

function _checkPKGnameConf
{
	##PKGnameConf="$SGCONF/${PKGname}/${PKGname}.conf"
	if [[ -f $PKGnameConf ]]; then
		_print 3 "**" "Found configuration file $PKGnameConf" ; _ok
	else
		_print 3 "==" "Serviveguard package configuration file $PKGnameConf not found" ; _nok
		_error "No package running (${PKGname}) nor did we find a $PKGnameConf file"
	fi
}

function _check_package_name
{
	PackageNameDefined=$(grep ^package_name $PKGnameConf | awk '{print $2}')
	if [[ -z $PackageNameDefined ]]; then
		_print 3 "==" "Missing package_name in ${PKGname}.conf" ; _nok
	else
		_print 3 "**" "Found package_name ($PackageNameDefined) in ${PKGname}.conf" ; _ok
	fi
}

function _check_package_running_on_node
{
	# show the status of the package and on which node it is running
	PackageNameDefined=$(grep ^package_name $PKGnameConf | awk '{print $2}')
	Nodes_status=$( cmviewcl -f line -v -p $PackageNameDefined 2>/dev/null | grep ^node | grep -E '(name=|status=)' | cut -d"|" -f2 | cut -d= -f2 | awk 1 ORS=' ' )
	# e.g. Nodes_status="gltdbdr1 down gltdbdr2 up"
	echo "$Nodes_status" | grep -q " up"   # mind the leading space to avoid mistakes with packagename containing up
	if [[ $? -eq 0 ]]; then
		# is it running on primary or alternate node?
		if [[ "$(echo $Nodes_status | awk '{print $2}')" = "up" ]]; then
			# package running on primary node
			PKGrunningNode="$(echo $Nodes_status | awk '{print $1}' | cut -d. -f1)"
			_print 3 "**" "Package ($PackageNameDefined) is running on primary node: $Nodes_status" ; _ok
		else
			# package running on alternate node
			PKGrunningNode="$(echo $Nodes_status | awk '{print $3}' | cut -d. -f1)"
			_print 3 "**" "Package ($PackageNameDefined) is running on alternate node: $Nodes_status" ; _warn
		fi
	else
		_print 3 "**" "Package ($PackageNameDefined) is not active: $Nodes_status" ; _ok
	fi
}

function _check_ers_package
{
	# verify if $PackageNameDefined contains "ers" or not (indicates an ERS package for SAPdb
	echo "$PackageNameDefined" | grep -i ers && ERS_PACKAGE=1
}

function _check_ip_monitor
{
	cmviewcl -fline -v | grep -i ip_monitor=on > /tmp/ip_monitor.$PKGname
	count=$( wc -l /tmp/ip_monitor.$PKGname | awk '{print $1}')
	if [[ $count -gt 0 ]]; then
		# issue ip_monitor=on means problems - see issue #25
		_print 3 "==" "Turn off ip_monitor in the cluster configuration (not package issue)" ; _warn
		_note "The following lines should be modified to off:"
		cat /tmp/ip_monitor.$PKGname 
		rm -f /tmp/ip_monitor.$PKGname 
	else
		_print 3 "**" "ip_monitor=off - should be off in cluster configuration" ; _ok
	fi
}

function _check_package_defined_in_hosts_file
{
	PackageNameDefined=$(grep ^package_name $PKGnameConf | awk '{print $2}')
	if [[ -z $PackageNameDefined ]]; then
		_print 3 "==" "Empty package_name - cannot check /etc/hosts file" ; _nok
	else
		for NODE in $( cmviewcl -fline -lnode | grep name= | cut -d= -f2 )
		do
			_debug "Checking on node $NODE the /etc/hosts file"
			cmdo -n $NODE grep "$PackageNameDefined" /etc/hosts | grep -v "^\#" | while read Line
			do
				echo $Line | grep -q "$PackageNameDefined" 2>/dev/null
				if [[ $? -eq 0 ]]; then
					_print 3 "**" "Found hostname ($PackageNameDefined) in /etc/hosts on node $NODE" ; _ok
				else
					_print 3 "==" "Hostname ($PackageNameDefined) not found in /etc/hosts on node $NODE" ; _nok
				fi
			done
		done
	fi
}

function _check_package_description
{
	PackageDescriptionDefined=$(grep ^package_description $PKGnameConf | cut -c20- | sed -e 's/"//g' | awk 'BEGIN {OFS=" "}{$1=$1; print}')
	if [[ -z $PackageDescriptionDefined ]]; then
		_print 3 "==" "Missing package_description in ${PKGname}.conf" ; _nok
	else
		_print 3 "**" "Found package_description ($PackageDescriptionDefined) in  ${PKGname}.conf" ; _ok
	fi
}


function _check_node_name
{
	typeset -i i count
	set -A NodeNames
	i=1
	grep ^node_name $PKGnameConf | awk '{print $2}' | while read node
	do
		NodeNames[$i]="$node"
		i=$((i+1))
	done
	count=$((i-1))
	if [[ $count -eq 0 ]]; then
		_print 3 "==" "Missing node_name in ${PKGname}.conf" ; _nok
	else
		node=${NodeNames[@]}	# ${NodeNames[@]} doesn't parse well in _print function
		_print 3 "**" "Found $count node_name line(s) (${node}) in ${PKGname}.conf" ; _ok
	fi
}

function _check_package_type
{
	PackageTypeDefined=$(grep ^package_type $PKGnameConf | awk '{print $2}')
	if [[ -z "$PackageTypeDefined" ]]; then
		_print 3 "==" "Missing package_type in ${PKGname}.conf" ; _nok
	elif [[ "$PackageTypeDefined" = "failover" ]]; then
		grep ^module_name $PKGnameConf | grep -q failover || {
			_warning "Use the package module file \"-m sg/failover\" with cmmakepkg"
		}
		_print 3 "**" "Found package_type ($PackageTypeDefined) in ${PKGname}.conf" ; _ok
	## FIXME: add elif for other package types
	else
		_print 3 "==" "Found package_type ($PackageTypeDefined) in ${PKGname}.conf" ; _nok
	fi
}

function _check_auto_run
{
	AutoRunDefined=$(grep ^auto_run $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$PackageTypeDefined" ]]; then
		_print 3 "==" "Missing auto_run in ${PKGname}.conf" ; _nok
	elif [[ "$AutoRunDefined" = "yes" ]]; then
		_print 3 "**" "Found auto_run ($AutoRunDefined) in ${PKGname}.conf" ; _ok
	else
		if [[ "$CONCLUSTERAWARE" = "Y" ]]; then
			_print 3 "**" "Found auto_run ($AutoRunDefined) in ${PKGname}.conf (continental cluster)" ; _ok
		else
			_print 3 "**" "Found auto_run ($AutoRunDefined) in ${PKGname}.conf (should be \"yes\")" ; _nok
		fi
	fi
}

function _check_node_fail_fast_enabled
{
	NodeFailFastEnabledDefined=$(grep ^node_fail_fast_enabled $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$NodeFailFastEnabledDefined" ]]; then
		_print 3 "==" "Missing node_fail_fast_enabled in ${PKGname}.conf (default is \"no\")" ; _warn
	elif [[ "$NodeFailFastEnabledDefined" = "no" ]]; then
		_print 3 "**" "Found node_fail_fast_enabled ($NodeFailFastEnabledDefined) in ${PKGname}.conf" ; _ok
	elif [[ "$NodeFailFastEnabledDefined" = "yes" ]]; then
		_print 3 "**" "Found node_fail_fast_enabled ($NodeFailFastEnabledDefined) in ${PKGname}.conf" ; _ok
	else
		_print "==" "Found node_fail_fast_enabled ($NodeFailFastEnabledDefined) in ${PKGname}.conf (use \"yes\" or \"no\")" ; _nok
	fi
}

function _check_failover_policy
{
	FailoverPolicyDefined=$(grep ^failover_policy $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$FailoverPolicyDefined" ]]; then
		_print 3 "==" "Missing failover_policy in ${PKGname}.conf" ; _nok
	elif [[ "$FailoverPolicyDefined" = "configured_node" ]]; then
		_print 3 "**" "Found failover_policy ($FailoverPolicyDefined) in ${PKGname}.conf" ; _ok
	else
		# FIXME: add entries for min_package_node, site_preferred, site_preferred_manual
		_print 3 "**" "Found failover_policy ($FailoverPolicyDefined) in ${PKGname}.conf" ; _warn
	fi
}

function _check_failback_policy
{
	FailbackPolicyDefined=$(grep ^failback_policy $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$FailbackPolicyDefined" ]]; then
		_print 3 "==" "Missing failback_policy in ${PKGname}.conf" ; _nok
	elif [[ "$FailbackPolicyDefined" = "manual" ]]; then
		_print 3 "**" "Found failback_policy ($FailbackPolicyDefined) in ${PKGname}.conf" ; _ok
	else
		# FIXME: add entry for 'automatic'
		_print 3 "**" "Found failback_policy ($FailbackPolicyDefined) in ${PKGname}.conf" ; _warn
	fi
}

function _check_run_script_timeout
{
	RunScriptTimeoutDefined=$(grep ^run_script_timeout $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$RunScriptTimeoutDefined" ]]; then
		_print 3 "==" "Missing run_script_timeout in ${PKGname}.conf" ; _nok
	elif [[ "$RunScriptTimeoutDefined" = "no_timeout" ]]; then
		_print 3 "**" "Found run_script_timeout ($RunScriptTimeoutDefined) in ${PKGname}.conf" ; _ok
	else
		# FIXME: integer > 0
		_print 3 "**" "Found run_script_timeout ($RunScriptTimeoutDefined) in ${PKGname}.conf" ; _warn
	fi
}

function _check_halt_script_timeout
{
	HaltScriptTimeoutDefined=$(grep ^halt_script_timeout $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$HaltScriptTimeoutDefined" ]]; then
		_print 3 "==" "Missing halt_script_timeout in ${PKGname}.conf" ; _nok
	elif [[ "$HaltScriptTimeoutDefined" = "no_timeout" ]]; then
		_print 3 "**" "Found halt_script_timeout ($HaltScriptTimeoutDefined) in ${PKGname}.conf" ; _ok
	else
		# FIXME: integer > 0
		_print 3 "**" "Found halt_script_timeout ($HaltScriptTimeoutDefined) in ${PKGname}.conf" ; _warn
	fi
}

function _check_successor_halt_timeout
{
	SuccessorHaltTimeoutputDefined=$(grep ^successor_halt_timeout $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$SuccessorHaltTimeoutputDefined" ]]; then
		_print 3 "==" "Missing successor_halt_timeout in ${PKGname}.conf" ; _nok
	elif [[ "$SuccessorHaltTimeoutputDefined" = "no_timeout" ]]; then
		_print 3 "**" "Found successor_halt_timeout ($SuccessorHaltTimeoutputDefined) in ${PKGname}.conf" ; _ok
	else
		# FIXME: integer >= 0 && <= 4294
		_print 3 "**" "Found successor_halt_timeout ($SuccessorHaltTimeoutputDefined) in ${PKGname}.conf" ; _warn
	fi
}

function _check_priority
{
	PriorityDefined=$(grep ^priority $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$PriorityDefined" ]]; then
		_print 3 "==" "Missing priority in ${PKGname}.conf" ; _nok
	elif [[ "$PriorityDefined" = "no_priority" ]]; then
		_print 3 "**" "Found priority ($PriorityDefined) in ${PKGname}.conf" ; _ok
	else
		# FIXME: integer between 1 and 3000
		_print 3 "**" "Found priority ($PriorityDefined) in ${PKGname}.conf" ; _warn
	fi
}

function _check_ip_subnet
{
	# check for ip_subnet (need extra space) as ip_subnet_node is also a known keyword
	IpSubnetDefined=$(grep "^ip_subnet[[:blank:]]" $PKGnameConf | awk '{print $2}' | wc -l)
	if [[ $IpSubnetDefined -ge 1 ]]; then
		_print 3 "**" "Found ip_subnet ($IpSubnetDefined line(s)) in ${PKGname}.conf" ; _ok
	else
		_print 3 "==" "Missing ip_subnet in ${PKGname}.conf" ; _nok
	fi
}

function _check_ip_address
{
	IpAddressDefined=$(grep ^ip_address $PKGnameConf | awk '{print $2}' | wc -l)
	if [[ $IpAddressDefined -ge 1 ]]; then
		_print 3 "**" "Found ip_address ($IpAddressDefined line(s)) in ${PKGname}.conf" ; _ok
		if [[ $IpAddressDefined -ne $IpSubnetDefined ]]; then
		    _compare_subnet_with_ip_addresses
	        fi
	else
		_print 3 "==" "Missing ip_address in ${PKGname}.conf" ; _nok
	fi
}

function _compare_subnet_with_ip_addresses
{
	# compare the amount of subnets with ip_addresses
	grep "^ip_subnet[[:blank:]]" $PKGnameConf | awk '{print $2}' | cut -d"." -f 1-3 | sort -u > /tmp/my_subnets_$$.txt
	grep ^ip_address $PKGnameConf | awk '{print $2}' | cut -d"." -f 1-3  | sort -u > /tmp/my_ip_addresses_$$.txt
	cmp -s /tmp/my_subnets_$$.txt /tmp/my_ip_addresses_$$.txt
	if [[ $? -eq 1 ]]; then
		_print 3 "==" "Amount of ip_subnet(s) ($(cat /tmp/my_subnets_$$.txt | wc -l)) do not correspond with amount of ip_address/subnets ($(cat /tmp/my_ip_addresses_$$.txt | wc -l))" ; _warn
	else
		_print 3 "**" "Amount of ip_subnet(s) ($(cat /tmp/my_subnets_$$.txt | wc -l)) and ip_address/subnets ($(cat /tmp/my_ip_addresses_$$.txt | wc -l)) are equal" ; _ok
	fi
	rm -f /tmp/my_subnets_$$.txt /tmp/my_ip_addresses_$$.txt
}

function _check_nslookup_address
{
	# input arg: name
	# output: 0=true (name resolvable); 1=false (name not found)
	nslookup "$1" > /tmp/_check_nslookup_address.txt 2>&1
	grep -q "^Address:" /tmp/_check_nslookup_address.txt && return 0
	return 1
}

function _check_local_lan_failover_allowed
{
	LocalLanFailoverAllowedDefined=$(grep ^local_lan_failover_allowed $PKGnameConf | awk '{print $2}' | tr '[A-Z]' '[a-z]')
	if [[ -z "$LocalLanFailoverAllowedDefined" ]]; then
		_print 3 "==" "Missing local_lan_failover_allowed in ${PKGname}.conf" ; _nok
	elif [[ "$LocalLanFailoverAllowedDefined" = "yes" ]]; then
		_print 3 "**" "Found local_lan_failover_allowed ($LocalLanFailoverAllowedDefined) in ${PKGname}.conf" ; _ok
	else
		_print 3 "**" "Found local_lan_failover_allowed ($LocalLanFailoverAllowedDefined) in ${PKGname}.conf" ; _warn
	fi
}

function _check_script_log_file
{
	ScriptLogFileDefined=$(grep ^script_log_file $PKGnameConf | awk '{print $2}')
	if [[ -z "$ScriptLogFileDefined" ]]; then
		_print 3 "==" "Missing script_log_file in ${PKGname}.conf" ; _nok
	else
		_print 3 "**" "Found script_log_file ($ScriptLogFileDefined) in ${PKGname}.conf" ; _ok
	fi
}

function _check_vgchange_cmd
{
	VgchangeCmdDefined=$(grep ^vgchange_cmd $PKGnameConf | cut -c 15- | sed -e 's/"//g' | awk 'BEGIN {OFS=" "}{$1=$1; print}')
	VgchangeCmdDefined2=$(echo $VgchangeCmdDefined | sed -e 's/ //g')
	if [[ -z "$VgchangeCmdDefined" ]]; then
		_print 3 "==" "Missing vgchange_cmd in ${PKGname}.conf" ; _nok
	elif [[ "$VgchangeCmdDefined2" = "vgchange-ae" ]]; then
		_print 3 "**" "Found vgchange_cmd ($VgchangeCmdDefined) in ${PKGname}.conf" ; _ok
	else
		# FIXME: what do we do with other possibilities?
		_print 3 "**" "Found vgchange_cmd ('$VgchangeCmdDefined') in ${PKGname}.conf" ; _nok
	fi
}

function _check_enable_threaded_vgchange
{
	EnableThreadedVgchangeDefined=$(grep ^enable_threaded_vgchange $PKGnameConf | awk '{print $2}')
	if [[ -z "$EnableThreadedVgchangeDefined" ]]; then
		 _print 3 "==" "Missing enable_threaded_vgchange in ${PKGname}.conf" ; _nok
	elif [[ $EnableThreadedVgchangeDefined -eq 1 ]]; then
		 _print 3 "**" "Found enable_threaded_vgchange ($EnableThreadedVgchangeDefined) in ${PKGname}.conf" ; _ok
	else
		_print 3 "**" "Found enable_threaded_vgchange ($EnableThreadedVgchangeDefined) in ${PKGname}.conf (use \"1\")" ; _warn
	fi

}

function _check_concurrent_vgchange_operations
{
	typeset -i i
	ConcurrentVgchangeOperationsDefined=$(grep ^concurrent_vgchange_operations $PKGnameConf | awk '{print $2}')
	if [[ -z "$ConcurrentVgchangeOperationsDefined" ]]; then
		_print 3 "==" "Missing concurrent_vgchange_operations in ${PKGname}.conf" ; _nok
	fi

	i=$(_isnum $ConcurrentVgchangeOperationsDefined)	# if string i=0, otherwise i=ConcurrentVgchangeOperationsDefined
	if [[ $ConcurrentVgchangeOperationsDefined -lt 2 ]]; then
		_print 3 "**" "Found concurrent_vgchange_operations ($ConcurrentVgchangeOperationsDefined) in ${PKGname}.conf (use \"2\")" ; _warn
	else
		_print 3 "**" "Found concurrent_vgchange_operations ($ConcurrentVgchangeOperationsDefined) in ${PKGname}.conf" ; _ok
	fi
}

function _check_fs_umount_retry_count
{
	typeset -i i
	FsUmountRetryCountDefined=$(grep ^fs_umount_retry_count $PKGnameConf | awk '{print $2}')
	if [[ -z "$FsUmountRetryCountDefined" ]]; then
		_print 3 "==" "Missing fs_umount_retry_count in ${PKGname}.conf" ; _nok
	fi

	i=$(_isnum $FsUmountRetryCountDefined)
	if [[ $FsUmountRetryCountDefined -lt 3 ]]; then
		_print 3 "**" "Found fs_umount_retry_count ($FsUmountRetryCountDefined) in ${PKGname}.conf (use \"3\")" ; _warn
	else
		_print 3 "**" "Found fs_umount_retry_count ($FsUmountRetryCountDefined) in ${PKGname}.conf" ; _ok
	fi
}

function _check_fs_mount_retry_count
{
	typeset -i i
	FsMountRetryCountDefined=$(grep ^fs_mount_retry_count $PKGnameConf | awk '{print $2}')
	if [[ -z "$FsMountRetryCountDefined" ]]; then
		_print 3 "==" "Missing fs_mount_retry_count in ${PKGname}.conf" ; _nok
	fi

	i=$(_isnum $FsMountRetryCountDefined)
	##if [[ $FsMountRetryCountDefined -lt 3 ]]; then   #original standard
	if [[ $FsMountRetryCountDefined -gt 0 ]]; then     #after discussions with HP
		_print 3 "**" "Found fs_mount_retry_count ($FsMountRetryCountDefined) in ${PKGname}.conf (use \"0\")" ; _warn
	else
		_print 3 "**" "Found fs_mount_retry_count ($FsMountRetryCountDefined) in ${PKGname}.conf" ; _ok
	fi
}

function _check_concurrent_mount_and_umount_operations
{
	typeset -i i
	ConcurrentMountAndUmountOperationsDefined=$(grep ^concurrent_mount_and_umount_operations $PKGnameConf | awk '{print $2}')
	if [[ -z "$ConcurrentMountAndUmountOperationsDefined" ]]; then
		_print 3 "==" "Missing concurrent_mount_and_umount_operations in ${PKGname}.conf" ; _nok
	fi

	i=$(_isnum $ConcurrentMountAndUmountOperationsDefined)
	if [[ $ConcurrentMountAndUmountOperationsDefined -lt 3 ]]; then
		_print 3 "**" "Found concurrent_mount_and_umount_operations ($ConcurrentMountAndUmountOperationsDefined) in ${PKGname}.conf (use \"3\")" ; _warn
	else
		_print 3 "**" "Found concurrent_mount_and_umount_operations ($ConcurrentMountAndUmountOperationsDefined) in ${PKGname}.conf" ; _ok
	fi
}

function _check_concurrent_fsck_operations
{
	typeset -i i
	ConcurrentFsckOperationsDefined=$(grep ^concurrent_fsck_operations $PKGnameConf | awk '{print $2}')
	if [[ -z "$ConcurrentFsckOperationsDefined" ]]; then
		_print 3 "==" "Missing concurrent_fsck_operations in ${PKGname}.conf" ; _nok
	fi

	i=$(_isnum $ConcurrentFsckOperationsDefined)
	if [[ $ConcurrentFsckOperationsDefined -lt 3 ]]; then
		_print 3 "**" "Found concurrent_fsck_operations ($ConcurrentFsckOperationsDefined) in ${PKGname}.conf (use \"3\")" ; _warn
	else
		_print 3 "**" "Found concurrent_fsck_operations ($ConcurrentFsckOperationsDefined) in ${PKGname}.conf" ; _ok
	fi
}

function _debug
{
	test "$DEBUG" && _note "$@"
}

function _check_user_name
{
	set -A UserNameDefined UserHostDefined UserRoleDefined
	i=0 ; count_username=0 ; count_userhost=0 ; count_userrole=0
	grep ^user_name $PKGnameConf | awk '{print $2}' | while read UserNameDefined[$i]
	do
		#[[ -z "${UserNameDefined[$i]}" ]]  && _print 3 "==" "Missing user_name in ${PKGname}.conf" ; _nok
		_debug "Found user_name ${UserNameDefined[$i]}"
		i=$((i+1))
	done
	count_username=$i
	#count_username=${#UserNameDefined[@]}
	#count_username=$((count_username-1))
	_debug "Amount of user_name line(s) defined in ${PKGname}.conf is $count_username"

	i=0
	grep ^user_host $PKGnameConf | awk '{print $2}' | while read UserHostDefined[$i]
	do
		_debug "Found user_host ${UserHostDefined[$i]}"
		i=$((i+1))
	done
	count_userhost=$i
	#count_userhost=$((count_userhost-1))
	_debug "Amount of user_host line(s) defined in ${PKGname}.conf is $count_userhost"

	i=0
	grep ^user_role $PKGnameConf | awk '{print $2}' | while read UserRoleDefined[$i]
	do
		_debug "Found user_role ${UserRoleDefined[$i]}"
		i=$((i+1))
	done
	count_userrole=$i
	#count_userrole=${#UserRoleDefined[@]}
	#count_userrole=$((count_userrole-1))
	_debug "Amount of user_role line(s) defined in ${PKGname}.conf is $count_userrole"

	if [[ $count_username -ne $count_userhost ]] && [[ $count_username -ne $count_userrole ]]; then
		_print 3 "==" "The amount of definitions of user_name, user_host and user_role are not the same!" ; _nok	
		return
	fi

	if [[ $count_username -eq 0 ]]; then
		_print 3 "**" "No user_name was defined. Perhaps this was on purpose, maybe not - pls verify"; _warn
		return
	fi

	# right, we found some valid definitions
	i=0
	while [[ $i -lt $count_username ]];
	do
		id ${UserNameDefined[$i]} >/dev/null 2>&1
		if [[ $? -ne 0 ]]; then
			_print 3 "==" "user_name ${UserNameDefined[$i]} is not a valid user!"; _nok
		else
			_print 3 "**" "user_name ${UserNameDefined[$i]} seems valid"; _ok
		fi
		i=$((i+1))
	done

	i=0
	while [[ $i -lt $count_userhost ]];
	do
		case ${UserHostDefined[$i]} in
			cluster_member_node|CLUSTER_MEMBER_NODE)
				_print 3 "**" "user_host ${UserHostDefined[$i]} is valid"; _ok
				;;
			any_serviceguard_node|ANY_SERVICEGUARD_NODE)
				_print 3 "==" "user_host ${UserHostDefined[$i]} is not what we expect"; _nok
				;;
			*)
				_print 3 "==" "user_host ${UserHostDefined[$i]} is not standard"; _nok
				;;
		esac
		i=$((i+1))
	done

	i=0
	while [[ $i -lt $count_userrole ]];
	do
		if [[ "${UserRoleDefined[$i]}" = "package_admin" ]] || [[ "${UserRoleDefined[$i]}" = "PACKAGE_ADMIN" ]]; then
			_print 3 "**" "user_role ${UserRoleDefined[$i]} is valid"; _ok
		else
			_print 3 "==" "user_role ${UserRoleDefined[$i]} is not valid"; _nok
		fi
		i=$((i+1))
	done
	unset UserNameDefined UserHostDefined UserRoleDefined
}

function _check_vg
{
	set -A VgDefined
	i=0
	egrep '^vg[[:blank:]]' $PKGnameConf | awk '{print $2}' | while read VgDefined[$i]
	do
		_debug "Found volumegroup ${VgDefined[$i]} in ${PKGname}.conf"
		i=$((i+1))
	done
	count_vg=$i
	_debug "Amount of volume group line(s) defined in ${PKGname}.conf is $count_vg"

	if [[ $count_vg -eq 0 ]]; then
		_print 3 "==" "No vg (volume group) defined in ${PKGname}.conf - must have at least one"; _nok
	else
		_print 3 "**" "We found $count_vg vg (volume group) line(s) in ${PKGname}.conf"; _ok
	fi
	# we will use array VgDefined in other functions too (do not unset it)
}

function _check_fs_lines
{
	typeset -i i j
	i=$(grep ^"fs_" $PKGnameConf | grep -v count | wc -l)
	j=$(grep ^"fs_name" $PKGnameConf | wc -l)
	if (( $((j%2)) )) ; then
		amount_is="odd"
	else
		amount_is="even"
	fi
	_debug "Total Amount of fs_ lines in ${PKGname}.conf is $i (must be $amount_is)"
	if (( $((i%2)) )) ; then
		i_is="odd"
	else
		i_is="even"
	fi
	if [[ "$i_is" = "$amount_is" ]]; then
		_print 3 "**" "Total amount of fs_ lines ($i) in ${PKGname}.conf must be $amount_is"; _ok
	else
		_print 3 "==" "Total amount of fs_ lines ($i) in ${PKGname}.conf must be $amount_is"; _nok
	fi
}

function _check_vg_active
{
	typeset -i i count rc
	i=0
	count=${#VgDefined[@]}
	count=$((count-1))
	_debug "_check_vg_active: VGs to check count=$count or count_vg=$count_vg"
	while [[ $i -lt $count ]];	# because we start with 0
	do
		_debug "Is VG=${VgDefined[i]} active on this node?"
		echo ${VgDefined[i]} | grep -q "^/dev" || VgDefined[$i]="/dev/${VgDefined[i]}"
		_debug "VgDefined[$i]=${VgDefined[i]}"
		vgdisplay ${VgDefined[i]} >/dev/null 2>&1
		rc=$?
		if [[ $rc -eq 0 ]]; then
			_print 3 "**" "VG ${VgDefined[i]} is active on this node"; _ok
			_check_fs_name ${VgDefined[i]}
			_check_fs_directory "${VgDefined[i]}"
		else
			_print 3 "**" "VG ${VgDefined[i]} is not active on this node"; _ok
			_print 3 "**" "We will skip lvol and fs in-depth analysis; rerun when VG is active" ; _skip
		fi
		i=$((i+1))
	done
}

function _check_fs_name
{
	# input arg1 VG
	typeset -i rc
	typeset VG="$1"
	count_lvols=$(ls "${VG}/" | grep -v -E '(group|^r)' | wc -l)	# what we see on $VG directory
	count_fs_name=$(grep "^fs_name" $PKGnameConf | grep "${VG}/" | wc -l)	# what is defined in conf file
	if [[ $count_lvols -ne $count_fs_name ]]; then
		grep "^fs_name" $PKGnameConf | grep "${VG}/" | cut -d/ -f4 | sort > /tmp/fs_name.1
		ls "${VG}/" | grep -v -E '(group|^r)' | sort > /tmp/fs_name.2
		# use an array to capture the differences (could be more then 1 LV)
		set -A LVdiff $( comm -3 /tmp/fs_name.1 /tmp/fs_name.2 )
		_print 3 "==" "The amount of fs_name lines ($count_fs_name) defined does not match $VG/*" ; _nok
		_warning "Lvol(s) ${LVdiff[*]} not defined in $PKGnameConf"
		rm -f /tmp/fs_name.1 /tmp/fs_name.2
	fi
	grep "^fs_name" $PKGnameConf | awk '{print $2}' | grep "${VG}/" | while read lvol
	do
		lvdisplay $lvol >/dev/null 2>&1
		rc=$?
		if [[ $rc -ne 0 ]]; then
			_debug "fs_name=$lvol is not active"
			_print 3 "==" "fs_name=$lvol is not responding on lvdisplay" ; _nok
		else
			_debug "fs_name=$lvol is active"
			fstyp=$(fstyp -v $lvol | grep version | awk '{print $2}')
			[[ $fstyp -eq 7 ]] && comment="$fstyp" || comment="$fstyp [pls. upgrade to 7]"
			_print 3 "**" "fs_name=$lvol (vxfs version $comment)" ; _ok
		fi
		grep -q "^$lvol" /etc/fstab && {
			_print 3 "==" "Lvol $lvol is found in /etc/fstab file (should be SG only)"; _nok
		}
	done
}

function _check_fs_directory
{
	# input arg1 VG
	typeset VG="$1"
	grep "^fs_directory" $PKGnameConf | awk '{print $2}' | while read dir
	do
		_debug "Checking fs_directory=$dir"
		if [[ "$PKGstatus" = "up" ]]; then
			if [[ ! -d $dir ]]; then
				_print 3 "==" "Mount path $dir does not exist" ; _nok
			fi
		fi
		# retrieve list of mounted FS (excl. NFS mounted)
		mount -v | grep -v NFSv | awk '{print $1, $3}' > /tmp/mount-VG-dirs
		# grep the dir - mind the $ to avoid sub-strings!
		grep -q "${dir}$" /tmp/mount-VG-dirs
		if [[ $? -eq 0 ]]; then
			_debug "File system $dir is mounted"
			vxupgrade $dir | grep -q "version 5" && _debug "Schedule exec: vxupgrade -n 6 $dir"
			vxupgrade $dir | grep -q "version 6" && _debug "Schedule exec: vxupgrade -n 7 $dir"
		else
			if [[ "$PKGstatus" = "down" ]]; then
				_debug "File system $dir is not mounted as package status is down"
			else
				_print 3 "==" "fs_directory=$dir is not mounted (package status=$PKGstatus)" ; _warn
			fi
		fi
	done
	rm -f /tmp/mount-VG-dirs
}

function _check_resource_module
{
	_debug "Entering function _check_resource_module"
	# in case we have SGeSAP DB or jdb or ERS we might need the module_name sg/resource
	module=$(grep "^module_name" $PKGnameConf | awk '{print $2}' | grep "resource")
	if [[ -z "$module" ]] ; then
		# check if we defined a resource_ line; the module must be defined as well
		grep -q "^resource_name" $PKGnameConf &&  {
			_print 3 "==" "No module_name sg/resource defined (resource_name setting requires it)" ; _nok
			_note "Use cmmakepkg -n <Package Name> -m sg/resource ..."
		}
	elif [[ ! -z "$module" ]] ; then
		_print 3 "**" "module_name sg/resource defined in ${PKGname}.conf" ; _ok
	fi
}

function _check_resource_lines
{
	_debug "Entering function _check_resource_lines"
	typeset -i count
	grep "^resource_" $PKGnameConf > /tmp/resources_${PKGname}
	count=$(wc -l /tmp/resources_${PKGname} | awk '{print $1}')
	if [[ $count -eq 0 ]] && [[ $ERS_PACKAGE -eq 1 ]]; then
		_print 3 "==" "Expecting 4 resource lines for ERS package in ${PKGnameConf}" ; _nok
		return
	fi
	modulus=$((count%4))  # 4 lines gives 0; otherwise remainder
	if [[ $modulus -ne 0 ]]; then
		# we should minimum 4 lines
		_print 3 "==" "Expecting even amount of resource lines (we have $count)" ; _warn
		_note "We found the following settings in ${PKGnameConf}"
		cat /tmp/resources_${PKGname}
	else
		_print 3 "**" "Amount of resource lines is even (count is $count)" ; _ok
		[[ $count -eq 0 ]] && _note "No resource lines are defined (EMS triggers not active)"
	fi
	rm -f /tmp/resources_${PKGname}
}

function _check_sap_modules
{
	set -A SGeSAP
	typeset -i count i j
	i=1
	grep "^module_name" $PKGnameConf | awk '{print $2}' | grep "sgesap" | cut -d"/" -f2 | while read SGeSAP[$i]
	do
		_debug "Found module_name=sgesap/${SGeSAP[$i]}"
		i=$((i+1))
	done
	count=$((i-1))	# because we started with 1 and array starts with 0
	_debug "Amount of sgesap modules found is $count"
	[[ $count -eq 0 ]] && {
		_print 3 "==" "No module_names of type sgesap/<string> found" ; _nok
		_note "Use cmmakepkg -n <Package Name> -m sgesap/dbinstance -m sgesap/sapinstance \\"
		_note "    -m sgesap/sapinfra ..."
		_note "Or, when no SGeSAP modules are required consider using: $PRGNAME -s"
		}
	# check the modules if we have them all loaded
	i=1
	j=0
	for mod in dbinstance db_global oracledb_spec maxdb_spec sybasedb_spec sapinstance sap_global stack sapinfra sapinfra_pre sapinfra_post
	do
		j=$((j+1))	# if j>11 then we went through the mod list
		if [[ "${SGeSAP[$i]}" = "$mod" ]]; then
			_print 3 "**" "module_name ${SGeSAP[$i]} present in ${PKGname}.conf" ; _ok 
			i=$((i+1))	# found a mod; check next one in our array
			j=0		# reset j=0 to go through mod list again
		elif [[ j -eq 11 ]]; then
			_print 3 "==" "Not all sgesap module_names are present" ; _nok
			break		# exit from for loop
		fi
	done
}

function _check_db_vendor
{
	DbVendorDefined=$(grep "^sgesap/db_global/db_vendor" $PKGnameConf | awk '{print $2}')
	if [[ -z "$DbVendorDefined" ]]; then
		_print 3 "==" "sgesap/db_global/db_vendor not defined in ${PKGname}.conf (set \"oracle\")" ; _nok
	elif [[ "$DbVendorDefined" = "oracle" ]]; then
		_print 3 "**" "sgesap/db_global/db_vendor set to $DbVendorDefined" ; _ok
	else
		# FIXME: we only assume oracle for the moment
		_print 3 "==" "sgesap/db_global/db_vendor ($DbVendorDefined) incorrect (should be \"oracle\")" ; _nok
	fi
}

function _check_db_system
{
	DbSystemDefined=$(grep "^sgesap/db_global/db_system" $PKGnameConf | awk '{print $2}')
	if [[ -z "$DbSystemDefined" ]]; then
		_print 3 "==" "sgesap/db_global/db_system not defined in ${PKGname}.conf (set \"<SID>\")" ; _nok
		orasid=UNKNOWN
		sidadm=UNKNOWN
		return
	fi
	# $DbSystemDefined contains the <SID> in uppercase
	sid=$(echo $DbSystemDefined | tr 'A-Z' 'a-z')	# lowercase <sid>
	if [[ -d "/usr/sap/$DbSystemDefined" ]]; then
		_print 3 "**" "Found directory /usr/sap/$DbSystemDefined" ; _ok
	else
		_print 3 "==" "Missing directory /usr/sap/$DbSystemDefined" ; _nok
	fi
	orasid="ora${sid}"
	sidadm="${sid}adm"
	# check home-dir of $orasid in /etc/passwd file (only required if pkg is DB)
	# function _check_pkg_contains_database checks if pkg is containing a DB (oracle)
	_check_pkg_contains_database ${PKGname} || return

	[[ "${orasid}" = "UNKNOWN" ]] && return

	homedir=$(grep ^${orasid} /etc/passwd | cut -d: -f6)
	if [[ -z "$homedir" ]]; then
		_print 3 "==" "User ${orasid} not known on this node" ; _nok
	elif [[ "$homedir" = "/oracle/${DbSystemDefined}" ]]; then	# /oracle/<SID>
		_print 3 "**" "User ${orasid} home directory is /oracle/${DbSystemDefined}"; _ok
	else
		_print 3 "==" "User ${orasid} home directory is $homedir (should be /oracle/${DbSystemDefined})" ; _nok
	fi
}

function _check_pkg_contains_database
{
	# function to verify if current package is DB related or not
	# input argument: package_name; output:0 (true) or 1 (false)
	echo "$1" | tr 'A-Z' 'a-z' | grep -q -E '(db|ora)'
	if [[ $? -eq 0 ]]; then	
		_debug "_check_pkg_contains_database function: package $1 is a database package"
		return 0
	else
		_debug "_check_pkg_contains_database function: package $1 is NOT a database package"
		return 1
	fi
}

function _check_sidadm_homedir
{
	# check home-dir of $sidadm 
	[[ "$sidadm" = "UNKNOWN" ]] && return
	homedir=$(grep ^${sidadm} /etc/passwd | cut -d: -f6)
	if [[ -z "$homedir" ]]; then
		_print 3 "==" "User ${sidadm} not known on this node" ; _nok
	else
		_print 3 "**" "User ${sidadm} home directory is $homedir"; _ok
	fi
}

function _check_startdb_log_ownership
{
	[[ "$sidadm" = "UNKNOWN" ]] && return
	homedir=$(grep ^${sidadm} /etc/passwd | cut -d: -f6)
	# all start*.log files must be owned by ${sidadm} - we will catch not valid user in $owner
	owner=$( ls -l $homedir/start*.log 2>/dev/null | awk '{print $3}' | sort -u | grep -v ${sidadm} | tail -1 )
	# owner should be an empty var (if all log files were owned by ${sidadm})
	if [[ ! -z "$owner" ]]; then
		_print 3 "==" "One or more start\*log files are owned by user $owner (should be ${sidadm})" ; _nok
	else
		_debug "All $homedir/start\*.log are owned by user ${sidadm}"
	fi
}

function _check_stopdb_log_ownership
{
	[[ "$orasid" = "UNKNOWN" ]] && return
	homedir=$(grep ^${sidadm} /etc/passwd | cut -d: -f6)
	# all start*.log files must be owned by ${sidadm} - we will catch not valid user in $owner
	owner=$( ls -l $homedir/stop*.log 2>/dev/null | awk '{print $3}' | sort -u | grep -v ${sidadm} | tail -1 )
	# owner should be an empty var (if all log files were owned by ${sidadm})
	if [[ ! -z "$owner" ]]; then
		_print 3 "==" "One or more stop\*log files are owned by user $owner (should be ${sidadm})" ; _nok
	else
		_debug "All $homedir/stop\*.log are owned by user ${sidadm}"
	fi
}

function _check_orasid_homedir
{
	if [[ "$orasid" = "UNKNOWN" ]]; then
		_print 3 "==" "Home directory of oraSID is unknown (webdispatcher perhaps?)" ; _skip
		return
	fi
	homedir=$(grep ^${orasid} /etc/passwd | cut -d: -f6)
	# cmdo is required as we do not know where the package is active and the extra " " after homedir is a must
	VG=$( cmdo mount -v | grep "${homedir} " | awk '{print $1}' | cut -d"/" -f3 )
	if [[ -z "$VG" ]]; then
		_debug "Home directory of ${orasid} is not mounted (DT Cluster node perhaps)?"
		return
	fi
	if [[ ! -c /dev/$VG/group ]]; then
		_print 3 "==" "Volume group $VG is unknown on this system ($lhost)" ; _nok
		_note "Schedule exec: vgexport (preview mode) and vgimport VG $VG"
	fi
	if [[ "$VG" = "vg00" ]]; then
		# is homedir of orasid is on the local disks then check other node as well
		_print 3 "==" "Home directory ${homedir} is located on /dev/$VG (use a SAN disk)"; _nok
	else
		# if homedir of orasid is on SAN disks we are ok
		_debug "Home directory ${homedir} is located on a SAN device (VG $VG)"
	fi
}

function _check_authorized_keys
{
	# check if var $1 (orasid or sidadm) homedir contains .ssh directory
	# be careful only required if pkg is a DB one
	_check_pkg_contains_database ${PKGname} || return

	homedir=$(grep ^${1} /etc/passwd | cut -d: -f6)
	if [[ ! -d ${homedir}/.ssh ]]; then
		_print 3 "==" "Directory ${homedir}/.ssh does not exist" ; _warn
		return  # nothing further to check if ~/.ssh does not exist
	else
		_debug "Found ${homedir}/.ssh"
	fi
	# check ~/.ssh permission (should be 700) (use H option to follow symbolic link)
	pmode=$( ls -lHd ${homedir}/.ssh | awk '{print $1}' )  # drwx------
	case "$pmode" in
	  "drwx------") _debug "Permission setting of ${homedir}/.ssh is correct" ;;
	  *           ) _print 3 "**" "Directory ${homedir}/.ssh should have permission mode 700" ; _warn ;; 
	esac
	# check ownership
	if [[ "$(ls -ld ${homedir} | awk '{print $3}')" != "${1}" ]]; then
		_print 3 "==" "Ownership is not correct of ${homedir} (must be ${1}" ; _nok
		_note "Schedule exec: chown -R ${1} ${homedir}"
	else
		_debug "Ownership of ${homedir} is correct"
	fi

	# check if ~/.ssh/authorized_keys exists
	if [[ ! -f ${homedir}/.ssh/authorized_keys ]]; then
		_print 3 "==" "SSH file ${homedir}/.ssh/authorized_keys not found" ; _warn
	else
		_debug "SSH file ${homedir}/.ssh/authorized_keys found"
	fi
}

function _check_ora_authorized_keys
{
	### obsolete function ###
	# the SGS user keys are created on host basis and cannot cope with a virtual hostname
	# therefore, we keep the keys for each orasid in /home/orasid/.ssh/authorized_keys file
	adinfo --zone | grep -q EU || return # non-EU zone; just return
	
	[[ -z "${orasid}" ]] && return		# no SID defined
	if [[ ! -d /home/${orasid} ]]; then
		_print 3 "==" "Local home directory /home/${orasid} does not exist" ; _nok
	else
		_debug "Found /home/${orasid}"
		if [[ ! -d /home/${orasid}/.ssh ]]; then
			_print 3 "==" "Local directory /home/${orasid}/.ssh does not exist" ; _nok
		else
			_debug "Found /home/${orasid}/.ssh"
			if [[ ! -f /home/${orasid}/.ssh/authorized_keys ]]; then
				_print 3 "==" "SSH file /home/${orasid}/.ssh/authorized_keys not found" ; _nok
			else
				_print 3 "**" "SSH file /home/${orasid}/.ssh/authorized_keys found" ; _ok
			fi
			_debug "Found /home/${orasid}/.ssh/authorized_keys"
			# check permissions
			[[ "$(ls -ld /home/${orasid}/.ssh | awk '{print $1}')" != "drwx------" ]] && {
				_print 3 "==" "Permission wrong of /home/${orasid}/.ssh (must be 700)" ; _nok
				}
			# check ownership
			[[ "$(ls -ld /home/${orasid} | awk '{print $3}')" != "${orasid}" ]] && {
				_print 3 "==" "Ownership is not correct of /home/${orasid} (must be ${orasid}" ; _nok
				_note "Schedule exec: chown ${orasid}:dba /home/${orasid}"
				}
		fi
	fi
	if [[ ! -d /oracle/${DbSystemDefined} ]]; then
		_print 3 "==" "Directory /oracle/${DbSystemDefined} does not exist" ; _nok
	else
		_debug "Found /oracle/${DbSystemDefined}"
		if [[ ! -h /oracle/${DbSystemDefined}/.ssh ]]; then
			_print 3 "==" "/oracle/${DbSystemDefined}/.ssh does not exist as link" ; _nok
			_note "Schedule exec: rm -rf /oracle/${DbSystemDefined}/.ssh"
			_note "Schedule exec: ln -s /home/${orasid}/.ssh /oracle/${DbSystemDefined}/.ssh"
		else
			_debug "Found link /oracle/${DbSystemDefined}/.ssh"
			# check if it is link to /home/${orasid}/.ssh
			# ll /oracle/RLC/.ssh | cut -d">" -f2 | awk '{print $1}'
			[[ "$(ll /oracle/${DbSystemDefined}/.ssh | cut -d">" -f2 | awk '{print $1}')" != "/home/${orasid}/.ssh" ]] && {
				_print 3 "==" "Wrong link $(ll /oracle/${DbSystemDefined}/.ssh | cut -d">" -f2 | awk '{print $1}')" ; _nok
				_note "Schedule exec: rm -f /oracle/${DbSystemDefined}/.ssh"
				_note "Schedule exec: ln -s /home/${orasid}/.ssh /oracle/${DbSystemDefined}/.ssh"
				}
			_print 3 "**" "/oracle/${DbSystemDefined}/.ssh correctly linked"; _ok
		fi
	fi
}

function _check_listener_name
{
	ListernerNameDefined=$(grep "^sgesap/oracledb_spec/listener_name" $PKGnameConf | awk '{print $2}')
	if [[ -z "$ListernerNameDefined" ]]; then
		_print 3 "==" "sgesap/oracledb_spec/listener_name not defined in ${PKGname}.conf (set \"LISTENER_<SID>\")" ; _nok
	elif [[ "$ListernerNameDefined" = "LISTENER_${DbSystemDefined}" ]]; then
		_print 3 "**" "sgesap/oracledb_spec/listener_name $ListernerNameDefined" ; _ok
	else
		_print 3 "==" "sgesap/oracledb_spec/listener_name $ListernerNameDefined (set \"LISTENER_${DbSystemDefined}\")"
		_nok
	fi
}

function _check_sap_system
{
	SapSystemDefined=$(grep "^sgesap/sap_global/sap_system" $PKGnameConf | awk '{print $2}')
	if [[ -z "$SapSystemDefined" ]]; then
		_print 3 "==" "sgesap/sap_global/sap_system not defined in ${PKGname}.conf (set \"<SID>\")" ; _nok
	elif [[ "$SapSystemDefined" = "$DbSystemDefined" ]]; then
		_print 3 "**" "sgesap/sap_global/sap_system $SapSystemDefined" ; _ok
	else
		if [[ -z "$DbSystemDefined" ]]; then
			_print 3 "**" "sgesap/sap_global/sap_system $SapSystemDefined (ers package?)" ; _ok
		else
			_print 3 "==" "sgesap/sap_global/sap_system $SapSystemDefined (should be $DbSystemDefined)"; _nok
		fi
	fi
}

function _check_rem_comm
{
	RemCommDefined=$(grep "^sgesap/sap_global/rem_comm" $PKGnameConf | awk '{print $2}')
	if [[ -z "$RemCommDefined" ]]; then
		_print 3 "==" "sgesap/sap_global/rem_comm not defined in ${PKGname}.conf (set \"ssh\")" ; _nok
	elif [[ "$RemCommDefined" = "ssh" ]]; then
		_print 3 "**" "sgesap/sap_global/rem_comm $RemCommDefined" ; _ok
	else
		 _print 3 "==" "sgesap/sap_global/rem_comm $RemCommDefined (should be \"ssh\")" ; _nok
	fi
}

function _check_cleanup_policy
{
	CleanupPolicyDefined=$(grep "^sgesap/sap_global/cleanup_policy" $PKGnameConf | awk '{print $2}')
	if [[ -z "$CleanupPolicyDefined" ]]; then
		_print 3 "==" "sgesap/sap_global/cleanup_policy not defined in ${PKGname}.conf (set \"normal\")" ; _nok
	elif [[ "$CleanupPolicyDefined" = "normal" ]]; then
		_print 3 "**" "sgesap/sap_global/cleanup_policy $CleanupPolicyDefined" ; _ok
	else
		_print 3 "==" "sgesap/sap_global/cleanup_policy $CleanupPolicyDefined (should be \"normal\")" ; _nok
	fi
}

function _check_retry_count
{
	# originally we used 5 as a good setting, however, according
	# http://h10025.www1.hp.com/ewfrf/wc/document?cc=us&lc=en&docname=c03774137
	# 15 is much better
	RetryCountDefined=$(grep "^sgesap/sap_global/retry_count" $PKGnameConf | awk '{print $2}')
	if [[ -z "$RetryCountDefined" ]]; then
		_print 3 "==" "sgesap/sap_global/retry_count not defined in ${PKGname}.conf (define \"15\")" ; _nok
	elif [[ "$RetryCountDefined" = "15" ]]; then
		_print 3 "**" "sgesap/sap_global/retry_count $RetryCountDefined" ; _ok
	else
		_print 3 "==" "sgesap/sap_global/retry_count $RetryCountDefined (define \"15\")" ; _warn
	fi
}

function _check_sap_instance
{
	grep -q  "^sgesap/stack/sap_instance" $PKGnameConf
	if [[ $? -ne 0 ]]; then
		_print 3 "==" "Missing sgesap/stack/sap_instance in ${PKGname}.conf" ; _nok
	fi
	grep "^sgesap/stack/sap_instance" $PKGnameConf | awk '{print $2}' | while read SapInstanceDefined
	do
		if [[ -z "$SapInstanceDefined" ]]; then
			_print 3 "==" "sgesap/stack/sap_instance not defined in ${PKGname}.conf" ; _nok
		else
			_print 3 "**" "sgesap/stack/sap_instance $SapInstanceDefined" ; _ok
		fi
	done
}

function _check_sap_virtual_hostname
{
	grep -q "^sgesap/stack/sap_virtual_hostname"  $PKGnameConf
	if [[ $? -ne 0 ]]; then
		_print 3 "==" "Missing sgesap/stack/sap_virtual_hostname in ${PKGname}.conf" ; _nok
	fi
	grep "^sgesap/stack/sap_virtual_hostname" $PKGnameConf | awk '{print $2}' | while read SapVirtualHostnameDefined
	do
		if [[ -z "$SapVirtualHostnameDefined" ]]; then
			_print 3 "==" "sgesap/stack/sap_virtual_hostname not defined in ${PKGname}.conf" ; _nok
		else
			_print 3 "**" "sgesap/stack/sap_virtual_hostname $SapVirtualHostnameDefined" ; _ok
		fi
	done
}

function _check_sap_infra_sw_type
{
	SapInfraSwTypeDefined=$(grep "^sgesap/sapinfra/sap_infra_sw_type" $PKGnameConf | awk '{print $2}' | tr 'A-Z' 'a-z')
	if [[ -z "$SapInfraSwTypeDefined" ]]; then
		_print 3 "==" "sgesap/sapinfra/sap_infra_sw_type not defined in ${PKGname}.conf (use \"saposcol\")" ; _nok
	elif [[ "$SapInfraSwTypeDefined" = "saposcol" ]]; then
		_print 3 "**" "sgesap/sapinfra/sap_infra_sw_type $SapInfraSwTypeDefined" ; _ok
	else
		# FIXME: other values are not checked
		_print 3 "==" "sgesap/sapinfra/sap_infra_sw_type $SapInfraSwTypeDefined (use \"saposcol\")" ; _nok
	fi
}

function _check_sap_infra_sw_treat
{
	SapInfraSwTreatDefined=$(grep "^sgesap/sapinfra/sap_infra_sw_treat" $PKGnameConf | awk '{print $2}' | tr 'A-Z' 'a-z')
	if [[ -z "$SapInfraSwTreatDefined" ]]; then
		_print 3 "==" "sgesap/sapinfra/sap_infra_sw_treat not defined in ${PKGname}.conf (use \"startonly\")" ; _nok
	elif [[ "$SapInfraSwTreatDefined" = "startonly" ]]; then
		_print 3 "**" "sgesap/sapinfra/sap_infra_sw_treat $SapInfraSwTreatDefined" ; _ok
	else
		_print 3 "==" "sgesap/sapinfra/sap_infra_sw_treat $SapInfraSwTreatDefined (use \"startonly\")" ; _nok
	fi
}

function _check_sapms_service
{
	# sapmsXSG        3610/tcp        # SAP System Message Server Port (in /etc/services)
	[[ -z "${DbSystemDefined}" ]] && return		# no SID defined
	for NODE in $( cmviewcl -fline -lnode | grep name= | cut -d= -f2 )
	do
		SapmsServiceDefined=$(cmdo -n $NODE -t 10 grep "^sapms${DbSystemDefined}[[:blank:]]" /etc/services | grep -v "^\#" | awk '{print $2}')
		_debug "Checking /etc/services for sapms${DbSystemDefined}"
		if [[ -z "$SapmsServiceDefined" ]]; then
			_print 3 "==" "No entry found (of sapms${DbSystemDefined}) in /etc/services on node $NODE" ; _warn
		else
			_print 3 "**" "Found entry $SapmsServiceDefined in /etc/services on node $NODE" ; _ok
		fi
	done
}

function _check_nfs_present
{
	rm -f /tmp/HANFS-TOOLKIT-not-present
	typeset -i rc=0
	grep -q "^nfs/hanfs" $PKGnameConf
	rc=$?
	if [[ $rc -eq 0 ]]; then
		grep "^module_name" $PKGnameConf | grep -q "nfs/hanfs"
		if [[ $? -eq 0 ]]; then
			_print 3 "**" "Found module_names for nfs/hanfs" ; _ok
		else
			_print 3 "==" "Missing module_names for nfs/hanfs in ${PKGname}.conf" ; _warn
			_note "Use cmmakepkg -n <Package Name> -m nfs/hanfs ..."
		fi
	else
		_print 3 "**" "No HANFS TOOLKIT defined in ${PKGname}.conf" ; _skip
		touch /tmp/HANFS-TOOLKIT-not-present
	fi
}

function _check_nfs_supported_netids
{
	NfsSupportedNetids=$(grep "^nfs/hanfs_export/SUPPORTED_NETIDS" $PKGnameConf | awk '{print $2}' | tr 'A-Z' 'a-z')
	if [[ -z "$NfsSupportedNetids" ]]; then
		_print 3 "==" "Missing nfs/hanfs_export/SUPPORTED_NETIDS in ${PKGname}.conf (default is \"udp\")" ; _warn
	elif [[ "$NfsSupportedNetids" = "udp" ]]; then
		_print 3 "==" "nfs/hanfs_export/SUPPORTED_NETIDS $NfsSupportedNetids (prefer \"tcp\")" ; _ok
	elif [[ "$NfsSupportedNetids" = "tcp" ]]; then
		_print 3 "**" "nfs/hanfs_export/SUPPORTED_NETIDS $NfsSupportedNetids (set to \"tcp\")" ; _ok
	else
		# FIXME: what about other udp6/tcp6?
		_print 3 "==" "nfs/hanfs_export/SUPPORTED_NETIDS $NfsSupportedNetids (should be \"tcp\")" ; _nok
	fi
}

function _check_file_lock_migration
{
	FileLockMigrationDefined=$(grep "^nfs/hanfs_export/FILE_LOCK_MIGRATION" $PKGnameConf | awk '{print $2}')
	if [[ -z "$FileLockMigrationDefined" ]]; then
		_print 3 "==" "Missing nfs/hanfs_export/FILE_LOCK_MIGRATION in ${PKGname}.conf (use \"1\")" ; _warn
	elif [[ $FileLockMigrationDefined -eq 1 ]]; then
		_print 3 "**" "nfs/hanfs_export/FILE_LOCK_MIGRATION $FileLockMigrationDefined" ; _ok
		if [[ "$(uname -n)" = "$PKGrunningNode" ]] ; then
			# only run the FLM holding dir check if package is running on this node
			_check_flm_holding_dir
			_check_nfsv4_flm_holding_dir
		fi
	else
		_print 3 "**" "nfs/hanfs_export/FILE_LOCK_MIGRATION $FileLockMigrationDefined ($FileLockMigrationDefined)" ; _ok
	fi
}

function _check_flm_holding_dir
{
	FlmHoldingDir=$(grep "^nfs/hanfs_flm/FLM_HOLDING_DIR" $PKGnameConf | awk '{print $2}' | sed -e 's/"//g')
	if [[ -z "$FlmHoldingDir" ]]; then
		_print 3 "==" "Missing nfs/hanfs_flm/FLM_HOLDING_DIR in ${PKGname}.conf (use /export/sapmnt/${DbSystemDefined}/nfs_flm)" ; _warn
	elif [[ ! -d "$FlmHoldingDir" ]]; then
		_print 3 "==" "nfs/hanfs_flm/FLM_HOLDING_DIR $FlmHoldingDir (directory not found!)" ; _nok
	else
		_print 3 "**" "nfs/hanfs_flm/FLM_HOLDING_DIR $FlmHoldingDir" ; _ok
	fi
}

function _check_nfsv4_flm_holding_dir
{
	Nfsv4FlmHoldingDir=$(grep "^nfs/hanfs_flm/NFSV4_FLM_HOLDING_DIR" $PKGnameConf | awk '{print $2}' | sed -e 's/"//g')
	if [[ -z "$Nfsv4FlmHoldingDir" ]]; then
		_print 3 "**" "nfs/hanfs_flm/NFSV4_FLM_HOLDING_DIR \"\"" ; _ok
	else
		_print 3 "==" "nfs/hanfs_flm/NFSV4_FLM_HOLDING_DIR $Nfsv4FlmHoldingDir (should be \"\")" ; _nok
	fi
}

function _check_monitor_interval
{
	NfsMonitorInternal=$(grep "^nfs/hanfs_export/MONITOR_INTERVAL" $PKGnameConf | awk '{print $2}')
	if [[ "$NfsMonitorInternal" = "10" ]]; then
		_print 3 "**" "nfs/hanfs_export/MONITOR_INTERVAL $NfsMonitorInternal" ; _ok
	else
		_print 3 "==" "nfs/hanfs_export/MONITOR_INTERVAL $NfsMonitorInternal (default 10)" ; _nok
	fi
}

function _check_statmon_waittime
{
	NfsStatmonWaittime=$(grep "^nfs/hanfs_flm/STATMON_WAITTIME" $PKGnameConf | awk '{print $2}')
	if [[ "$NfsStatmonWaittime" = "90" ]]; then
		_print 3 "**" "nfs/hanfs_flm/STATMON_WAITTIME $NfsStatmonWaittime" ; _ok
	else
		_print 3 "==" "nfs/hanfs_flm/STATMON_WAITTIME $NfsStatmonWaittime (default 90)" ; _nok
	fi
}

function _check_propagate_interval
{
	NfsPropagateInterval=$(grep "^nfs/hanfs_flm/PROPAGATE_INTERVAL" $PKGnameConf | awk '{print $2}')
	if [[ "$NfsPropagateInterval" = "5" ]]; then
		_print 3 "**" "nfs/hanfs_flm/PROPAGATE_INTERVAL $NfsPropagateInterval" ; _ok
	else
		_print 3 "==" "nfs/hanfs_flm/PROPAGATE_INTERVAL $NfsPropagateInterval (default 5)" ; _nok
	fi
}

function _check_portmap_retry
{
	NfsPortmapRetry=$(grep "^nfs/hanfs_export/PORTMAP_RETRY" $PKGnameConf | awk '{print $2}')
	if [[ "$NfsPortmapRetry" = "4" ]]; then
		_print 3 "**" "nfs/hanfs_export/PORTMAP_RETRY $NfsPortmapRetry" ; _ok
	else
		_print 3 "==" "nfs/hanfs_export/PORTMAP_RETRY $NfsPortmapRetry (default 4)" ; _nok
	fi
}

function _check_monitor_daemons_retry
{
	NfsMonitorDaemonsRetry=$(grep "^nfs/hanfs_export/MONITOR_DAEMONS_RETRY" $PKGnameConf | awk '{print $2}')
	if [[ "$NfsMonitorDaemonsRetry" = "4" ]]; then
		_print 3 "**" "nfs/hanfs_export/MONITOR_DAEMONS_RETRY $NfsMonitorDaemonsRetry" ; _ok
	else
		_print 3 "==" "nfs/hanfs_export/MONITOR_DAEMONS_RETRY $NfsMonitorDaemonsRetry (default 4)" ; _nok
	fi
}

function _check_monitor_lockd_retry
{
	NfsMonitorLockdRetry=$(grep "^nfs/hanfs_export/MONITOR_LOCKD_RETRY" $PKGnameConf | awk '{print $2}')
	if [[ "$NfsMonitorLockdRetry" = "4" ]]; then
		_print 3 "**" "nfs/hanfs_export/MONITOR_LOCKD_RETRY $NfsMonitorLockdRetry" ; _ok
	else
		_print 3 "==" "nfs/hanfs_export/MONITOR_LOCKD_RETRY $NfsMonitorLockdRetry (default 4)" ; _nok
	fi
}

function _check_nfs_xfs
{
	typeset -i i count
	i=1
	grep "^nfs/hanfs_export/XFS" $PKGnameConf | while read garbage val1 systems expdir
	do
		opts=$(echo $val1 | sed -e 's/"//g')
		if [[ "$opts" != "-o" ]]; then
			_print 3 "==" "nfs/hanfs_export/XFS $opts in ${PKGname}.conf incorrect (start with -o)"; _nok
		fi

		expdir=$(echo $expdir | sed -e 's/"//g')
		if [[ ! -d "$expdir" ]]; then
			_print 3 "==" "nfs/hanfs_export/XFS $expdir (directory not found!)" ; _nok
		else
			_print 3 "**" "nfs/hanfs_export/XFS $expdir (directory exists)" ; _ok
		fi

		# We need to check the minor number on all the nodes of exported NFS directory
		_check_minor_number "$expdir"

		# CR QXCR1001219901 access list must be < 4096 bytes
		count=$(echo $systems | wc -c)
		_debug "Access list length is $count"
		[[ $count -ge 4096 ]] && {
			_print 3 "==" "The nfs/hanfs_export/XFS access list is too long (>4096) - reduce it" ; _nok
			_note "nfs/hanfs_export/XFS consider using netgroups to reduce access list"
			}
		accesslistroot=$(echo $systems | cut -d, -f 1 | cut -d= -f2)
		accesslistrw=$(echo $systems | cut -d, -f 2 | cut -d= -f2)
		accesslistro=$(echo $systems | cut -d, -f 3 | cut -d= -f2)
		_debug "Access list root part: $accesslistroot"
		_debug "Access list rw part: $accesslistrw"
		if [[ "$accesslistroot" = "$accesslistrw" ]]; then
			_print 3 "**" "The XFS access list \"root=\" matches the \"rw=\" for $expdir" ; _ok
		else
			_print 3 "==" "The XFS access list for \"root=\" is not the same as for \"rw=\"" ; _nok
			_note "Compare root=$accesslistroot for $expdir with the \rw=\" line in ${PKGname}.conf"
		fi
		_debug "Access list ro part: $accesslistro"
		# now check if $accesslistro is resolvable via nslookup
		_check_nslookup_address $accesslistro
		if [[ $? -eq 0 ]]; then
			_print 3 "**" "The XFS access list \"ro=$accesslistro\" is correct" ; _ok
		else
			_print 3 "==" "The XFS access list \"ro=$accesslistro\" is not correct" ; _nok
			_note "Use \"ro=$PKGname\" for XFS access list of $expdir"
		fi
	done
}

function _check_netgroup_file
{
	# purpose is when we use /etc/netgroup aliases we should check also the XFS lines to see if there are matches
	if [[ $( grep -v \# /etc/netgroup | wc -l ) -eq 0 ]]; then
		_debug "File /etc/netgroup is not used (no problem)"
	else
		# ok, seems we are using entries in /etc/netgroup, crosscheck with XFS entries needed
		# save our entries first
		grep "^nfs/hanfs_export/XFS" $PKGnameConf | awk '{print $3}' | cut -d"," -f2 | cut -d= -f2 | \
		 tr ':' '\012' | sort -u > /tmp/myXFS_nodelist.tmp
		for ALIAS in $( grep -v \# /etc/netgroup | awk '{print $1}' )
		do
			grep -q $ALIAS /tmp/myXFS_nodelist.tmp
			if [[ $? -eq 0 ]]; then
				_print 3 "**" "Found network-group alias $ALIAS in /etc/netgroup used by XFS"; _ok
			else
				_print 3 "**" "Found network-group alias $ALIAS in /etc/netgroup not used by XFS"; _skip
			fi
		done
		rm -f /tmp/myXFS_nodelist.tmp
	fi
}

function _check_debug_file
{
	if [[ -f /var/adm/cmcluster/debug_$PKGname ]]; then
		_print 3 "**" "DEBUG file /var/adm/cmcluster/debug_$PKGname found" ; _ok
	else
		_print 3 "**" "DEBUG file /var/adm/cmcluster/debug_$PKGname NOT found" ; _ok
	fi
}

function _check_ext_scripts
{
	[[ -z "$SGCONF" ]] && SGCONF=/etc/cmcluster
	grep "^external_script" $PKGnameConf | awk '{print $2}' | while read extscript
	do
		extscript=${extscript##*/}
		_debug "external_script $SGCONF/$extscript defined in ${PKGname}.conf"
		if [[ -f ${SGCONF}/scripts/ext/${extscript} ]]; then
			_print 3 "**" "\$SGCONF/scripts/ext/${extscript} defined in ${PKGname}.conf" ; _ok
		else
			_print 3 "==" "\$SGCONF/scripts/ext/${extscript} not found on this node!" ; _nok
		fi
	done
}

function _compare_conf_files
{
	typeset -i i count
	[[ -z "$SGCONF" ]] && SGCONF=/etc/cmcluster
	count=${#NodeNames[@]}
	_debug "Count of Node Names is $count"
	i=1
	ThisHost=$(hostname)
	_debug "This Node is $ThisHost"
	while [[ $i -le $count ]]
	do
		if [[ "$ThisHost" != "${NodeNames[i]}" ]]; then
			OtherHost=${NodeNames[i]}
			_debug "Other Node is $OtherHost"
		fi
		i=$((i+1))
	done
	cp $PKGnameConf /tmp/${PKGname}.conf.$ThisHost
	cmcp $OtherHost:$PKGnameConf /tmp/${PKGname}.conf.$OtherHost
	diff /tmp/${PKGname}.conf.$ThisHost /tmp/${PKGname}.conf.$OtherHost >/dev/null
	if [[ $? -eq 0 ]]; then
		_print 3 "**" "The ${PKGname}.conf is the same on both nodes" ; _ok
	else
		_print 3 "==" "The ${PKGname}.conf differs on both nodes" ; _nok
		_note "Schedule exec: cmcp $PKGnameConf $OtherHost:$SGCONF/${PKGname}/"
	fi
}

function _check_netids_in_auto_direct
{
	# check if a automount line is present and that proto=udp is not mentioned
	# SID=$DbSystemDefined
	
	# we need to check on all nodes the /etc/auto.direct file
	for NODE in $( cmviewcl -fline -lnode | grep name= | cut -d= -f2 )
	do
		_debug "Checking on node $NODE the /etc/auto.direct file"
		cmdo -n $NODE grep "$DbSystemDefined" /etc/auto.direct | grep -v "^\#" | while read Line
		do
			# ok, we found a line of SID, now check netids protocol (must match $NfsSupportedNetids)
			#/sapmnt/OAC "-vers=3,proto=tcp,retry=3" dbciOAC.ncsbe.eu.jnj.com:/export/sapmnt/OAC
			mntpt=$(echo $Line | awk '{print $1}')
			echo $Line | grep -q "proto=tcp"
			if [[ $? -eq 0 ]]; then
				protocol=tcp
			else
				protocol=udp
			fi
			if [[ "$NfsSupportedNetids" = "$protocol" ]]; then
				_print 3 "**" "$mntpt in /etc/auto.direct (on node $NODE) uses \"$protocol\" to mount" ; _ok
			elif [[ -z "$NfsSupportedNetids" ]]; then
				# we assume if "$NfsSupportedNetids" is empty the proto=udp
				if [[ "$protocol" = "udp" ]]; then
					_print 3 "**" "$mntpt in /etc/auto.direct (on node $NODE) uses \"$protocol\" to mount" ; _ok
				else
					_print 3 "==" "$mntpt in /etc/auto.direct (on node $NODE) contains \"proto=$protocol\"" ; _nok
					_note "Schedule exec on node $NODE: define nfs/hanfs_export/SUPPORTED_NETIDS \"udp\" in ${PKGname}.conf"
				fi
			else
				_print 3 "==" "$mntpt in /etc/auto.direct (on node $NODE) contains \"proto=$protocol\"" ; _nok
				_note "Schedule exec on node $NODE: Change \",proto=$protocol\" into \",proto=$NfsSupportedNetids\" from line $mntpt in /etc/auto.direct"
			fi
		done
	done
}

function _check_commented_sapmnt_in_auto_direct
{
	# purpose of this function is to display any /sapmnt/SID line which is commented in /etc/auto.direct
	# SID=$DbSystemDefined
	[[ -z "$DbSystemDefined" ]] && return
	if [[ "$DbSystemDefined" = "<SID>" ]]; then
		_print 3 "**" "Cannot find \"<SID>\" in /etc/auto.direct" ; _skip
		return
	fi

	# we need to check on all nodes the /etc/auto.direct file
	for NODE in $( cmviewcl -fline -lnode | grep name= | cut -d= -f2 )
	do
		_debug "Checking on node $NODE the /etc/auto.direct file for commented sapmnt entries"
		cmdo -n $NODE grep "$DbSystemDefined" /etc/auto.direct | grep "^\#" | while read Line
		do
			# as we grep # lines skip the ##Executing on node line
			echo $Line | grep -q "Executing on node" && continue
			# ok, we found a line of SID, now check
			#/sapmnt/XRC "-vers=3,proto=udp,retry=3" dbciXRC.company.com:/export/sapmnt/XRC
			mntpt=$(echo $Line | awk '{print $1}' | sed -e 's/\#//')  # remove #
			_print 3 "==" "Mount point $mntpt is commented in /etc/auto.direct on node $NODE" ; _nok
			_note "Schedule exec on node $NODE: Remove the \"#\" from $mntpt in /etc/auto.direct" 
		done
	done
}

function _check_dfstab
{
	# check if we did not foresee a manual share in /etc/dfs/dfstab
	[[ "$DbSystemDefined" = "<SID>" ]] && return
	[[ -z "$DbSystemDefined" ]] && return
	grep "$DbSystemDefined" /etc/dfs/dfstab | grep -v "^\#" | while read Line
	do
		_print 3 "==" "Please move the following line into the ${PKGname}.conf (XFS line)" ; _nok
		_note "Schedule exec: move out /etc/fstab - $Line"
	done
}

function _check_minor_number
{
	# input arg: expdir
	expdir="$1"
	# map the expdir to its VG/lvol
	lvolexpdir=$(mount -l | grep $expdir | awk '{print $3}')
	# check minor number on both nodes as this could lead to stale NFS issues
	for NODE in $( cmviewcl -fline -lnode | grep name= | cut -d= -f2 )
	do
		_debug "Checking minor number of export NFS mount point on node $NODE"
		cmdo -n $NODE ls -ld $lvolexpdir | tail -1 | awk '{print $6}' >/tmp/minor_nr.$NODE
	done
	count=$(sort -u /tmp/minor_nr.* | wc -l)
	case $count in
		1) _print 3 "**" "The minor number of NFS dir $expdir is equal on all nodes" ; _ok
		   ;;
		*) _print 3 "==" "The minor number of NFS dir $expdir is not the same on all nodes" ; _nok
		   for NODE in $( cmviewcl -fline -lnode | grep name= | cut -d= -f2 )
		   do
			_note "On node $NODE the minor nr is $(cat /tmp/minor_nr.$NODE)"
		   done
	esac
	rm -f /tmp/minor_nr.*
}

function _check_node_enablement
{
	cmviewcl -f line -vp ${PKGname} > /tmp/_check_node_enablement.txt 2>&1
	grep  -E 'switching' /tmp/_check_node_enablement.txt | while read Line
	do
		echo $Line | grep -q "disabled" 
		if [[ $? -eq 0 ]]; then
			# disabled
			_print 3 "==" "Node enablement: $Line" ; _warn
		else
			_print 3 "**" "Node enablement: $Line" ; _ok
		fi
	done
	rm -f /tmp/_check_node_enablement.txt
}

function _is_account_locked
{
	# purpose is the check if account $1 is locked or not
	# return 1 means NOT locked; 0 is locked
        message=$( /usr/lbin/getprpw -m lockout ${1} 2>/dev/null )
        case $? in
        0)      # success (and system is trusted)
                case "$(echo ${message} | cut -d= -f2)" in
                        "0000000") # exists and is not locked
                                return 1 ;;
			"0000001") # exists and is intentionally disabled
				return 1 ;;
                        *) # account exists and is locked
                                return 0 ;;
                esac
                ;;
        4)      # system is not trusted (so not using /tcb/ structure)
                i=$( /usr/bin/passwd -s ${1} 2>/dev/null | awk '{print NF}' )
                case $i in
                        2) /usr/bin/passwd -s ${1} | grep -q LK  && return 0 || return 1 ;;
                        5|6)    # account contains an expiry date! format date mm/dd/yy
                                current_date=$( date '+%m/%d/%y' )
                                expiry_date=$( /usr/bin/passwd -s ${1} | awk '{print $3}' )
                                if [[ "$expiry_date" < "$current_date" ]] ; then
                                        print 3 "==" "Account ${1} is expired (${expiry_date})" ; _warn
                                        #sys_logger ${PRGNAME} "${1} account is expired (${expiry_date})"
                                        account_is_expired=1       # account is expired
                                fi
                                /usr/bin/passwd -s ${1} | grep -q LK  && return 0 || return 1 ;;
                        *) return 1 ;;  # unknown status or output (no action)
                esac
                ;;
        *)      return 1 ;;     # no account - no need to unlock it
        esac
}

function _show_locked_msg
{
	# purpose of this script is to display the locked account info (input var is $1 account)
	message=$( /usr/lbin/getprpw -m lockout ${1} 2>/dev/null | cut -d= -f2 )
        case $? in
        4)      # System is not trusted
		# unlock and set NP
                _print 3 "==" "Account $1 seems to be locked" ; _warn
		_note "Schedule exec: /usr/bin/passwd -d ${1}"
		;;
        *)      # System is trusted
		case "$message" in
		    "1000000") _print 3 "==" "Account $1 seems to be locked (past password lifetime)" ; _warn ;;
		    "0100000") _print 3 "==" "Account $1 seems to be locked (past last login time (inactive account))" ; _warn ;;
		    "0010000") _print 3 "==" "Account $1 seems to be locked (past absolute account lifetime)" ; _warn ;;
		    "0001000") _print 3 "==" "Account $1 seems to be locked (exceeded unsuccessful login attempts)" ; _warn ;;
		    "0000100") _print 3 "==" "Account $1 seems to be locked (password required and a null password)" ; _warn ;;
		    "0000010") _print 3 "==" "Account $1 seems to be locked (admin lock)" ; _warn ;;
		    "1100001") _print 3 "==" "Account $1 seems to be wrongly created (tcb password entry is an *)" ; _warn ;;
		    *)         _print 3 "==" "Account $1 seems to be locked" ; _warn ;;
		esac
                _note "Schedule exec: /usr/lbin/modprpw -k ${1}"
		;;
        esac
}

function _check_oracle_account
{
	grep -q ^${oracle} /etc/passwd
	if [[ $? -eq 0 ]]; then
		account_is_expired=0
		_is_account_locked ${oracle}
		if [[ $? -eq 0 ]]; then
			_show_locked_msg ${oracle}
		else
			_print 3 "**" "Account ${oracle} is useable" ; _ok
		fi
	fi
}

#########################################################################################################
#
# MAIN
#
#########################################################################################################
while [ $# -gt 0 ]; do
	case "$1" in
		-d) DEBUG=1		# turn debugging on
		    shift 1
		    ;;
		-s) TestSGeSAP=0	# no SGeSAP testing required
		    shift 1
		    ;;
		-h) _show_help_${PRGNAME%.*}
		    exit 1
		    ;;
		-m) MONITORMODE=1
		    shift 1
		    ;;
                -M) ToUser="$2"
		    _is_var_empty "$ToUser" || ToUser=""
		    shift 2
		    ;;
		-w) SAPWEBDISPATCHER=1
		    TestSGeSAP=1        # we turn TestSGeSAP on in case we give option '-s' and '-w'
		    shift 1
		    ;;
                -f) READLOCALCONFFILE=1
		    shift 1
		    ;;
		-*) _show_help_${PRGNAME%.*}
		    exit 1
		    ;;
		*)  PKGname=$1		# expecting a package name (will be checked)
		    shift 1
		    ;;
	esac
done

_is_var_empty "$PKGname"
if [[ $? -eq 1 ]]; then
	_show_help_${PRGNAME%.*}
	exit 1
fi

# define the proper LOGFILE before start logging
PKGname_tmp=${PKGname##*/}       # if PKGname was a filename
PKGname_tmp=${PKGname_tmp%.*}    # remove .conf
LOGFILE=$dlog/${PRGNAME%???}-${PKGname_tmp}-$(date '+%Y%m%d-%H%M').log
echo "Detailed logging about package $PKGname_tmp is saved under $LOGFILE"

{ # start of MAIN body (everything will be logged)
	[[ -z "$SGCONF" ]] && SGCONF=/etc/cmcluster
	[[ $MONITORMODE -eq 0 ]] && _banner "Test the consistency of serviceguard (SGeSAP) configuration script"
	_validOS
	_validSG
	_validSGeSAP
	_validCluster
	_checkPKGname
	_isPkgConfigured

	# checking general package parameters
	# when package is running download the configuration instead of using an older config file
	if [[ -z "$READLOCALCONFFILE" ]] && [[ $ForceCMGETCONF -eq 1 ]]; then
		# we will save our temp. config file in /var/tmp (these will cleaned up automatically)
		 _print 3 "**" "Executing cmgetconf -p $PKGname > /var/tmp/${PKGname}.conf.$(date +%d%b%Y)"
		cmgetconf -p $PKGname > /var/tmp/${PKGname}.conf.$(date +%d%b%Y) && _ok || _nok
		PKGnameConf=/var/tmp/${PKGname}.conf.$(date +%d%b%Y)
		if [[ ! -s $PKGnameConf ]]; then
			# cmgetconf failed and config file is empty
			_note "Switching back to $SGCONF/${PKGname}/${PKGname}.conf as failback procedure!"
			PKGnameConf=$SGCONF/${PKGname}/${PKGname}.conf
			rm -f /var/tmp/${PKGname}.conf.$(date +%d%b%Y)
		fi
        else
		PKGnameConf=$SGCONF/${PKGname}/${PKGname}.conf
	fi
	# before doing the check if package is running we need to verify if we are dealing with a
	# continental cluster setup, and if package resides on recovery cluster then when it is
	# down to not consider this as a warning, but show ok instead
	_isPkgContinentalClusterAware  # define variables CONCLUSTERAWARE and RECOVERYCLUSTERACTIVE
	_isPkgRunning
	_checkPKGnameConf
	# if package exists in cluster (status=up or down) then run the following
	if [[ "$PKGstatus" = "up" ]] || [[ "$PKGstatus" = "down" ]]; then
		_check_node_enablement
	fi
	# check if package is running on primary node or on an alternate node (informative)
	_check_package_running_on_node
	_check_package_name
	_check_ers_package
	_check_package_defined_in_hosts_file
	_check_package_description
	_check_node_name
	_check_package_type
	_check_resource_module
	_check_ip_monitor
	_check_auto_run
	_check_node_fail_fast_enabled
	_check_failover_policy
	_check_failback_policy
	_check_run_script_timeout
	_check_halt_script_timeout
	_check_successor_halt_timeout
	_check_priority
	_check_ip_subnet
	_check_ip_address
	_check_local_lan_failover_allowed
	_check_script_log_file
	_check_vgchange_cmd
	_check_enable_threaded_vgchange
	_check_concurrent_vgchange_operations
	_check_fs_umount_retry_count
	_check_fs_mount_retry_count
	_check_concurrent_mount_and_umount_operations
	_check_concurrent_fsck_operations
	_check_user_name

	# checking Volume Group and file systems
	_check_vg
	_check_fs_lines
	_check_vg_active	# more functions are called to anlyse fs_name; fs_directory

	# when oracle account is present run a check if it is locked or not
	_check_oracle_account


	if [[ TestSGeSAP -eq 1 ]]; then
		# continue with testing SGeSAP stuff in conf file
		_check_sap_modules
		_check_resource_lines
		[[ $SAPWEBDISPATCHER -eq 0 ]] && _check_db_vendor  # do not check for SAP Webdispatcher
		[[ $SAPWEBDISPATCHER -eq 0 ]] && _check_db_system
		[[ $SAPWEBDISPATCHER -eq 0 ]] && _check_orasid_homedir
		_check_sidadm_homedir
		# account_is_expired can be set to 1 by function _is_account_locked
		account_is_expired=0
		[[ "${orasid}" != "UNKNOWN" ]] && _is_account_locked ${orasid} && _show_locked_msg ${orasid}
		if [[ $account_is_expired -eq 1 ]]; then
			_print 3 "==" "Account ${orasid} is expired" ; _warn
			account_is_expired=0   # reset
		fi
		[[ "${sidadm}" != "UNKNOWN" ]] && _is_account_locked ${sidadm} && _show_locked_msg ${sidadm}
		if [[ $account_is_expired -eq 1 ]]; then
			_print 3 "==" "Account ${orasid} is expired" ; _warn
		fi
		# check the SSH keys (if in use)
		[[ "${orasid}" != "UNKNOWN" ]] && _check_authorized_keys ${orasid}
		[[ "${sidadm}" != "UNKNOWN" ]] && _check_authorized_keys ${sidadm}
		# function to check sidadm startdb.log ownership (if root is owner then SAP will not start)
		_check_startdb_log_ownership
		_check_stopdb_log_ownership
		_check_sapms_service
		[[ $SAPWEBDISPATCHER -eq 0 ]] && _check_listener_name
		_check_sap_system
		_check_rem_comm
		_check_cleanup_policy
		_check_retry_count
		_check_sap_instance
		_check_sap_virtual_hostname
		[[ $SAPWEBDISPATCHER -eq 0 ]] && _check_sap_infra_sw_type
		[[ $SAPWEBDISPATCHER -eq 0 ]] && _check_sap_infra_sw_treat
	fi

	# checking hanfs
	_check_nfs_present
	if [[ ! -f /tmp/HANFS-TOOLKIT-not-present ]]; then
		_check_nfs_supported_netids
		_check_file_lock_migration # this will check flm if required
		_check_monitor_interval
		_check_monitor_lockd_retry
		_check_monitor_daemons_retry
		_check_portmap_retry
		#_check_flm_holding_dir
		#_check_nfsv4_flm_holding_dir
		_check_propagate_interval
		_check_statmon_waittime
		_check_nfs_xfs
		_check_netgroup_file
		_check_commented_sapmnt_in_auto_direct
		_check_netids_in_auto_direct
		_check_dfstab
	fi

	_check_ext_scripts
	_check_debug_file
	# comparing the config files is not really necessary anymore as the real source is saved by cmgetconf
	#_compare_conf_files

	echo $ERRcode > /tmp/ERRcode.sgesap
}  2>&1 > $LOGFILE
##}  2>&1 | tee $LOGFILE # tee is used in case of interactive run

if [[ $MONITORMODE -eq 0 ]]; then
	cat $LOGFILE
else
	grep -v -E '( OK |SKIP)' $LOGFILE
fi

PKGnameConf="$SGCONF/${PKGname}/${PKGname}.conf"

# check error count
[ ! -f /tmp/ERRcode.sgesap ] && exit	# no pkgname given probably
ERRcode=$(cat /tmp/ERRcode.sgesap)

if [[ $MONITORMODE -eq 0 ]]; then
    # interactive (no monitor mode)
    if [[ $ERRcode -eq 0 ]]; then
	echo "
	*************************************************************************
	  No errors were found in $PKGnameConf
	  Run \"cmcheckconf -v -P $PKGnameConf\"
	  followed by \"cmapplyconf -v -P $PKGnameConf\"
	*************************************************************************" | tee -a $LOGFILE
    else
	echo "
	*************************************************************************
	  There were $ERRcode error(s) found in $PKGnameConf
	  Please correct these first and rerun $PRGNAME
	*************************************************************************" | tee -a $LOGFILE
    fi
fi

echo "	Log file for $PKGname is saved as $LOGFILE" | tee -a $LOGFILE

if [[ ! -z "$ToUser" ]]; then
    # when we manually defined -M mail@adress send an HTML mail
    if [[ $ERRcode -eq 0 ]]; then
        GenerateHTMLMail "[SUCCESS] Results of package configuration of SG package ${PKGname}" | $SENDMAIL -t "$ToUser"
    else
        GenerateHTMLMail "[FAILED] Results of package configuration of SG package ${PKGname}"  | $SENDMAIL -t "$ToUser"
    fi
fi

# to help our wrapper script we will save our LOGFILE name(!!) into a file
# /tmp/sgesap_validation_wrapper_logfile.name (we may not remove this file of course)
echo $LOGFILE > /tmp/sgesap_validation_LOGFILE.name

#
# cleanup
#
rm -f /tmp/ERRcode.sgesap /tmp/isPkgConfigured.txt
rm -f /tmp/HANFS-TOOLKIT-not-present /tmp/_check_nslookup_address.txt
# The END - the exit code will be picked up by monitor script
exit $ERRcode
