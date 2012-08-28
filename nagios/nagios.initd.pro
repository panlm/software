#!/bin/sh
# 
# chkconfig: 345 99 01
# description: Nagios network monitor
#
# File : nagios
#
#
# Description: Starts and stops the Nagios monitor
#              used to provide network services status.
#
# Changes: Version  for GroundWork professional that uses the Nagios Event Broker with the integrated NSCA client
#
  
status_nagios ()
{

	if test ! -f $NagiosRunFile; then
		echo "No lock file found in $NagiosRunFile"
		return 1
	fi

	NagiosPID=`head -n 1 $NagiosRunFile`
	if test -x $NagiosCGI/daemonchk.cgi; then
		if $NagiosCGI/daemonchk.cgi -l $NagiosRunFile; then
		        return 0
		else
			return 1
		fi
	else
		if ps -p $NagiosPID; then
		        return 0
		else
			return 1
		fi
	fi

	return 1
}


killproc_nagios ()
{
	# this subroutine has been modified by GWRK on 4/17/2008 to
	# kill children of nagios children more quickly.

	if test ! -f $NagiosRunFile; then
		echo "No lock file found in $NagiosRunFile"
		return 1
	fi

	NagiosPID=`head -n 1 $NagiosRunFile`
	kill $2 $NagiosPID

	# GroundWork add here to kill nagios process
	# if she hasn't died yet. we'll wait a second, then make her.
	sleep 10
	NagiosProcs=`ps auwwx |grep -v grep|grep "nagios -d"|awk '{print $2}'`
	NagiosProcs=`for Proc in $NagiosProcs ; do echo -en "$Proc "; done`
	while test "X$NagiosProcs" != "X" ; do
		echo "Nagios hasn't died yet ( $NagiosProcs)... Trying again."
		for Proc in $NagiosProcs ; do

			# in here we have to look at each child and determine if it
			# has any child processes such as plugins that we need to
			# terminate
			NagiosChildProcs=`/bin/ps --ppid $Proc|grep -v 'TTY'|awk '{print $1}'`
			NagiosChildProcs=`for ChildProc in $NagiosChildProcs ; do echo -en "$ChildProc "; done`

			while test "X$NagiosChildProcs" != "X" ; do
				echo "Nagios children haven't died yet ( $NagiosChildProcs)... Trying again."
				for ChildProc in $NagiosChildProcs ; do
					kill -9 $ChildProc > /dev/null 2>&1
				done
				NagiosChildProcs=`/bin/ps --ppid $Proc|grep -v 'TTY'|awk '{print $1}'`
				NagiosChildProcs=`for ChildProc in $NagiosChildProcs ; do echo -en "$ChildProc "; done`
			done

			kill -9 $Proc > /dev/null 2>&1
		done
		sleep 1
		NagiosProcs=`ps auwwx |grep -v grep|grep "nagios -d"|awk '{print $2}'`
		NagiosProcs=`for Proc in $NagiosProcs ; do echo -en "$Proc "; done`
	done
}

# Call this for reload
killproc_nagios_sig ()
{

	if test ! -f $NagiosRunFile; then
		echo "No lock file found in $NagiosRunFile"
		return 1
	fi

	NagiosPID=`head -n 1 $NagiosRunFile`
	kill $2 $NagiosPID

}


# Source function library
# Solaris doesn't have an rc.d directory, so do a test first
if [ -f /etc/rc.d/init.d/functions ]; then
	. /etc/rc.d/init.d/functions
elif [ -f /etc/init.d/functions ]; then
	. /etc/init.d/functions
fi

# Modify for GroundWork Monitor directories
arch=$(arch)
libdir=lib
if [ "$arch" == "x86_64" ] ; then
  libdir=lib64
fi

export prefix=/usr/local/groundwork/nagios
export LD_LIBRARY_PATH=${prefix}/$libdir

exec_prefix=${prefix}
NagiosBin=${exec_prefix}/bin/nagios
NagiosCfgFile=${prefix}/etc/nagios.cfg
NagiosStatusFile=${prefix}/var/status.log
NagiosTempFile=${prefix}/var/nagios.tmp
NagiosRetentionFile=${prefix}/var/nagiosstatus.sav
NagiosCommandFile=${prefix}/var/spool/nagios.cmd
NagiosVarDir=${prefix}/var
NagiosRunFile=${prefix}/var/nagios.lock
NagiosLockDir=/var/lock/subsys
NagiosLockFile=nagios
NagiosCGIDir=${exec_prefix}/apache2/cgi-bin/nagios
NagiosUser=nagios
NagiosGroup=nagios
          

# Check that nagios exists.
if [ ! -f $NagiosBin ]; then
    echo "Executable file $NagiosBin not found.  Exiting."
    exit 1
fi

# Check that nagios.cfg exists.
if [ ! -f $NagiosCfgFile ]; then
    echo "Configuration file $NagiosCfgFile not found.  Exiting."
    exit 1
fi
          
# See how we were called.
case "$1" in

	start)
	echo -en "\nStarting network monitor: nagios"
	rm -f ${prefix}/var/nagios.tmp*
	$NagiosBin -v $NagiosCfgFile > /dev/null 2>&1;
	if [ $? -eq 0 ]; then
	su - $NagiosUser -c "touch $NagiosVarDir/nagios.log $NagiosRetentionFile"
	rm -f $NagiosCommandFile
	touch $NagiosRunFile
	chown $NagiosUser:$NagiosGroup $NagiosRunFile
	$NagiosBin -d $NagiosCfgFile
        if [ $? -eq 0 ] ; then
        	#echo -e '\E[0m'"\033[61G[\033[0m"
        	#echo -e '\E[1;37;32m'"\033[63GOK\033[0m" ]
        	echo -e "\nNagios start complete"
        else
        	#echo -en '\E[0m'"\033[61G[\033[0m"
        	#echo -e '\E[1;37;31m'"\033[63GFAILED\033[0m" ]
        	echo -e "\nNagios start [FAILED]"
        fi

	if [ -d $NagiosLockDir ]; then touch $NagiosLockDir/$NagiosLockFile; fi

		exit 0
	else
		echo "CONFIG ERROR!  Start aborted.  Check your Nagios configuration."
			exit 1
		fi
		;;

	stop)

		echo  "Stopping network monitor: nagios"
		killproc_nagios nagios

 		# now we have to wait for nagios to exit and remove its
 		# own NagiosRunFile, otherwise a following "start" could
 		# happen, and then the exiting nagios will remove the
 		# new NagiosRunFile, allowing multiple nagios daemons
 		# to (sooner or later) run - John Sellens
		# echo -n 'Waiting for nagios to exit .'
 		for i in 1 2 3 4 5 6 7 8 9 10 ; do
 		    if status_nagios > /dev/null; then
 			echo -n ' .'
 			sleep 1
 		    else
 			break
 		    fi
 		done
 		if status_nagios > /dev/null; then
 		    echo ''
 		    echo 'Warning - running nagios did not exit in time'
 		fi

		rm -f $NagiosStatusFile $NagiosTempFile $NagiosRunFile $NagiosLockDir/$NagiosLockFile $NagiosCommandFile
		;;

	status)
		echo -en "Network monitor nagios:"
		status_nagios nagios > /dev/null 2>&1
		if [ $? -eq 0  ] ; then
                        echo -en '\E[0m'"\033[61G[\033[0m"
                        echo -e  '\E[1;37;32m'"\033[63Grunning\033[0m" ]
                else
                        echo -en '\E[0m'"\033[61G[\033[0m"
                        echo -e  '\E[1;37;31m'"\033[63Gdead\033[0m" ]
                fi
		;;

	restart)
		printf "Running configuration check..."
		$NagiosBin -v $NagiosCfgFile > /dev/null 2>&1;
		if [ $? -eq 0 ]; then
			echo "done"
			$0 stop
			$0 start
		else
			#$NagiosBin -v $NagiosCfgFile
			echo " FAILED!  Restart aborted.  Check your Nagios configuration."
			exit 1
		fi
		;;

	reload|force-reload)
		printf "Running configuration check..."
		$NagiosBin -v $NagiosCfgFile > /dev/null 2>&1;
		if [ $? -eq 0 ]; then
			echo "done"
			if test ! -f $NagiosRunFile; then
				$0 start
			else
				NagiosPID=`head -n 1 $NagiosRunFile`
				if status_nagios > /dev/null; then
					printf "Reloading nagios configuration..."
					killproc_nagios_sig nagios -HUP
					echo "done"
				else
					$0 stop
					$0 start
				fi
			fi
		else
			#$NagiosBin -v $NagiosCfgFile
			echo " FAILED!  Reload aborted.  Check your Nagios configuration."
			exit 1
		fi
		;;

	*)
		echo "Usage: nagios {start|stop|restart|reload|force-reload|status}"
		exit 1
		;;

esac
  
# End of this script
