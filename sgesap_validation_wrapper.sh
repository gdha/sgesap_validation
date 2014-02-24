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
typeset	   ToUser="DL-NCSBE-ITSGTSCMonitor3@ITS.JNJ.com"
typeset -r SENDMAIL=/usr/lib/sendmail
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
	expand "$LOGFILE" | mailx -s "$*" $ToUser
}

function MailHeaders
{
    # input paramters (string of text) is used for subject line
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
    echo "<table width=100% border=0 cellspacing=0 cellpadding=0 style=\"border: 1 solid #000080\">"
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
        "OK")           color="#00CA00" ;;      # greenish
        "FAILED")       color="#FF0000" ;;      # redish
        "WARN")
                if [[ "${columns[0]}" = "**" ]]; then
                        color="#E8E800"         # yellow alike
                else
                        color="#FB6104"         # orange alike
                fi
                ;;
        "SKIP")         color="#000000" ;;      # black
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

function CreateParagraphLine
{
    echo "<P><HR></P>"
}

function GenerateHTMLMail
{
    MailHeaders "$*"
    StartOfHtmlDocument
    SetTitleOfDocument "$*"
    CreateTable
    cat $LOGFILE | while read LINE
    do
	case "$( echo $LINE | cut -c1-6 )" in
            "======"|"######" ) # markers to split up in tables
		      EndTable
		      CreateParagraphLine
		      CreateTable
		      ;;
               *    ) TableRow "$LINE" ;; 
	esac
    done
    EndTable
    EndOfHtmlDocument
}

###
### MAIN
###

{
_banner "Wrapper script (and monitoring) around sgesap_validation.sh"

/usr/sbin/cmviewcl -f line  > $TMPFILE 2>/dev/null
CLUSTER=$( grep ^name $TMPFILE | cut -d= -f 2 )
CLUSTER_STATE=$( grep ^status $TMPFILE | cut -d= -f 2 )
set -A CLUSTER_NODES $(grep ^node $TMPFILE | grep name= | cut -d= -f 2 )

if [[ -z "$CLUSTER" ]]; then
	echo "$(date '+%d-%m-%Y %H:%M:%S') No cluster running on this system ($HOSTNAME)"
else
	echo "$(date '+%d-%m-%Y %H:%M:%S') Cluster $CLUSTER is $CLUSTER_STATE (nodes are ${CLUSTER_NODES[@]})"
fi

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
[[ -z "$CLUSTER" ]] && CLUSTER="n/a"  # if we run this on a non-clustered system

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

if [[ $rc -eq 0 ]]; then
	#_mail "[SUCCESS] Results of package configuration  validation on cluster $CLUSTER"
	GenerateHTMLMail "[SUCCESS] Results of package configuration  validation on cluster $CLUSTER" | $SENDMAIL -t "$ToUser"
else
	#_mail "[FAILED] Results of package configuration  validation on cluster $CLUSTER"
	GenerateHTMLMail "[FAILED] Results of package configuration  validation on cluster $CLUSTER" | $SENDMAIL -t "$ToUser"
fi

###
### cleanup and exit
###
rm -f $TMPFILE /tmp/sgesap_validation_LOGFILE.name
exit $rc
