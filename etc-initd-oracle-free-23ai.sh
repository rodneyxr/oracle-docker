#!/bin/bash
#
# chkconfig: 2345 80 05
# description: This script is responsible for taking care of configuring the RPM Oracle FREE Database and its associated services. 
#
# processname: oracle-free-23ai
# Red Hat or SuSE config: /etc/sysconfig/oracle-free-23ai
#
# change log:
#    ivalopez  12/13/17 - Creation
#    mstalin   04/30/18 - DB configuration changes
#    rfgonzal  05/14/18 - Enh 27965960 & 27965939 - Enable service and clean env vars when launching dbca
#    mstalin   05/20/18 - 21261445 RTI, disable the checks
#    mstalin   05/29/18 - 28121518 password handling and connection string handling
#    mstalin   06/07/18 - Add memory distribution logic
#    rfgonzal  07/09/18 - Bug 28243127 - Cannot start/stop DB after fresh installation
#    mstalin   07/06/18 - Add sample schema to XE
#    mstalin   08/02/18 - 28353388 Add delete option to the usage text
#    mstalin   08/02/18 - 28242894 Reduce verbose of the script 
#    mstalin   10/06/18 - 28735641 Fix duplicate success messages and product name
#    mstalin   10/14/19 - 28785753 Add db_domain support
#    mstalin   10/15/19 - Add ignoreprereqs
#    mstalin   10/15/19 - ER 29677762 Configure EM global port
#    mstalin   10/15/19 - Skip datapatch
#    psainza   12/04/19 - ER 28330482: Adding support to status flag
#    mstalin   07/09/20 - 31591395 Remove hr schema in XE
#    mstalin   01/12/21 - 32245867 Changes for SLES15
#    mstalin   08/14/22 - 34513647 XE to Free
#    mstalin   08/30/22 - 34549652  Change SID of XE to free instead of freecdb
#    mstalin   11/18/22 - 34779697  Remove EM express
#    mstalin   02/22/23 - RTI 24751295 Incorrect listener status reported on a stopped listener
#    mstalin   02/23/23 - 35088681  ss command not found in certain environments
#    mstalin   02/07/23 - 36254577 - PROVIDE OPTION TO CONFIGURE TDE ENABLED DATABASE



# Set path if path not set
case $PATH in
    "") PATH=/bin:/usr/bin:/sbin:/etc
        export PATH ;;
esac

# Check if the root user is running this script
if [ $(id -u) != "0" ]
then
    echo "You must be root user to run the configure script. Login as root user and then run the configure script."
    exit 1
fi

# DB defaults
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export TEMPLATE_NAME=FREE_Database.dbc
export PDB_NAME=FREEPDB1
export LISTENER_NAME=LISTENER
export NUMBER_OF_PDBS=1
export CREATE_AS_CDB=true

# General exports and vars
export PATH=$ORACLE_HOME/bin:$PATH
LSNR=$ORACLE_HOME/bin/lsnrctl
SQLPLUS=$ORACLE_HOME/bin/sqlplus
NETCA=$ORACLE_HOME/bin/netca
DBCA=$ORACLE_HOME/bin/dbca
ORACLE_OWNER=oracle
RETVAL=0
CONFIG_NAME="oracle-free-23ai.conf"
CONFIGURATION="/etc/sysconfig/$CONFIG_NAME"
ORACLE_HOME_NAME="OraHomeFree"
MINIMUM_MEMORY=1048576
MAXIMUM_MEMORY=2097152
MINIMUM_MEMORY_STR="1GB"

MINIMUM_SPACE=4718592
MINIMUM_SPACE_STR="4.5GB"

# Commands
if [ -z "$SS" ];then SS=/usr/sbin/ss; fi
if [ -z "$SU" ];then SU=/bin/su; fi
if [ -z "$AWK" ];then AWK=/bin/awk; fi
if [ -z "$DF" ];then DF=/bin/df; fi
if [ -z "$GREP" ]; then GREP=/usr/bin/grep; fi
if [ ! -f "$GREP" ]; then GREP=/bin/grep; fi
if [ -z "$TAIL" ]; then TAIL=/usr/bin/tail; fi
if [ ! -f "$TAIL" ]; then TAIL=/bin/tail; fi
HOSTNAME_CMD="/bin/hostname"
MKDIR_CMD="/bin/mkdir"
if [ ! -f "$SS" ]; then SS="/sbin/ss"; fi

# To start the DB
start()
{
    check_for_configuration
    RETVAL=$?
    if [ $RETVAL -eq 1 ]
    then
        echo "The Oracle Database is not configured. You must run '/etc/init.d/oracle-free-23ai configure' as the root user to configure the database."
        exit
    fi
    # Check if the DB is already started
    pmon=`ps -ef | egrep pmon_$ORACLE_SID'\>' | $GREP -v grep`
    if [ "$pmon" = "" ];
    then

        # Unset the proxy env vars before calling sqlplus
        unset_proxy_vars

        echo "Starting Oracle Net Listener."
        $SU -s /bin/bash $ORACLE_OWNER -c "$LSNR  start $LISTENER_NAME" > /dev/null 2>&1
        RETVAL=$?
        if [ $RETVAL -eq 0 ]
        then
            echo "Oracle Net Listener started."
        fi
        
        echo "Starting Oracle Database instance $ORACLE_SID."
        $SU -s /bin/bash  $ORACLE_OWNER -c "$SQLPLUS -s /nolog << EOF
                                                                connect / as sysdba
                                                                startup
                                                                alter pluggable database all open
                                                                exit;
                                                                EOF" > /dev/null 2>&1
        RETVAL1=$?
        if [ $RETVAL1 -eq 0 ]
        then
            echo "Oracle Database instance $ORACLE_SID started."
        fi
    else
        echo "The Oracle Database instance $ORACLE_SID is already started."
        exit 0
    fi
    
    echo
    if [ $RETVAL -eq 0 ] && [ $RETVAL1 -eq 0 ]
    then
        return 0
     else
        echo "Failed to start Oracle Net Listener using $ORACLE_HOME/bin/tnslsnr and Oracle Database using $ORACLE_HOME/bin/sqlplus."
        exit 1
    fi
}

# To stop the DB
stop()
{
    check_for_configuration
    RETVAL=$?
    if [ $RETVAL -eq 1 ]
    then
        echo "The Oracle Database is not configured. You must run '/etc/init.d/oracle-free-23ai configure' as the root user to configure the database."
        exit 1
    fi
    # Check if the DB is already stopped
    pmon=`ps -ef | egrep pmon_$ORACLE_SID'\>' | $GREP -v grep`
    if [ "$pmon" = "" ]
    then
        echo "Oracle Database instance $ORACLE_SID is already stopped."
        exit 1
    else

        # Unset the proxy env vars before calling sqlplus
        unset_proxy_vars

        echo "Shutting down Oracle Database instance $ORACLE_SID."
        $SU -s /bin/bash $ORACLE_OWNER -c "$SQLPLUS -s /nolog << EOF
                                                                connect / as sysdba
                                                                shutdown immediate
                                                                exit;
                                                                EOF" > /dev/null 2>&1
        RETVAL=$?
        if [ $RETVAL -eq 0 ]
        then
            echo "Oracle Database instance $ORACLE_SID shut down."
        fi
        
        echo "Stopping Oracle Net Listener."
        $SU -s /bin/bash  $ORACLE_OWNER -c "$LSNR stop $LISTENER_NAME" > /dev/null 2>&1
        RETVAL1=$?  
        if [ $RETVAL1 -eq 0 ]
        then
            echo "Oracle Net Listener stopped."
        fi
    fi
    
    echo 
    if [ $RETVAL -eq 0 ] && [ $RETVAL1 -eq 0 ]
    then
        return 0
    else
        echo "Failed to stop Oracle Net Listener using $ORACLE_HOME/bin/tnslsnr and Oracle Database using $ORACLE_HOME/bin/sqlplus."
        exit 1
    fi
}

configure_delete()
{
    # Unset the proxy env vars before calling dbca and netca
    unset_proxy_vars
    ORABASE=`$ORACLE_HOME/bin/orabase`
    NETCA_LOG_DIR="$ORABASE/cfgtoollogs/netca"
    if [ ! -d "$NETCA_LOG_DIR" ]
    then
       $SU -s /bin/bash $ORACLE_OWNER -c "$MKDIR_CMD -p $NETCA_LOG_DIR"   
    fi
    NETCA_LOG="$NETCA_LOG_DIR/netca_deinst_out.log"
    if [ ! -f "$NETCA_LOG" ]
    then
       $SU -s /bin/bash $ORACLE_OWNER -c "echo Netca deconfiguration log > $NETCA_LOG"
       chmod 640 $NETCA_LOG
    fi
 
    echo "Deleting Oracle Listener."

    $SU -s /bin/bash $ORACLE_OWNER -c "$LSNR  stop $LISTENER_NAME" > /dev/null 2>&1

    $SU -s /bin/bash $ORACLE_OWNER -c "$NETCA /deinst >>$NETCA_LOG"

    echo "Deleting Oracle Database $ORACLE_SID."

    $SU -s /bin/bash  $ORACLE_OWNER -c "$DBCA -silent -deleteDatabase -sourceDB $ORACLE_SID -skipSYSDBAPasswordPrompt true"

}
# To call DBCA to configure the DB
configure_perform()
{

    DBDOMAIN_CONSTRUCT="-gdbName $ORACLE_SID"
    if [ "x$DB_DOMAIN" != "x" ] 
    then
	DBDOMAIN_CONSTRUCT="-gdbName $ORACLE_SID.$DB_DOMAIN"
    fi
    DBFILE_CONSTRUCT=""
    if [ "x$DBFILE_DEST" != "x" ] 
    then
	DBFILE_CONSTRUCT="-storageType FS -datafileDestination $DBFILE_DEST"
    fi
   
    LSNRPORT_CONSTRUCT=""
    if [ "x$LISTENER_PORT" != "x" ] 
    then
        LSNRPORT_CONSTRUCT="/lisport $LISTENER_PORT"
    fi
    CONFIGURE_TDE_CONSTRUCT=""
    if [ "x$CONFIGURE_TDE" = "xtrue" ] 
    then
        CONFIGURE_TDE_CONSTRUCT="-configureTDE true"
	if [ "x$ENCRYPT_TABLESPACES" != "x" ]
    	then
        	TABLESPACES_CONSTRUCT="-encryptTablespaces $ENCRYPT_TABLESPACES"
    	fi
    fi
    # Unset the proxy env vars before calling dbca and netca
    unset_proxy_vars

    MEMORY_CONSTRUCT=""
    mem=`cat /proc/meminfo |grep MemTotal`
    # Total physical memory 
    if [ "x$mem" != "x" ]
    then

       #Convert into string array

       OLDIFS="$IFS"
       IFS=' '
       str=($mem)
       IFS=$OLDIFS
       
       #40 percent of physical memory
       dbmem=$(( 40*${str[1]}/100 ))
       
       #Oracle memory is less than 2GB distribute to pga and sga
       if [ "$dbmem" -lt "$MAXIMUM_MEMORY" ]
       then
          memory=$(( $dbmem/1024 ))
          pga=$(( $memory/4 ))
          sga=$(( 3*$memory/4 )) 
          MEMORY_CONSTRUCT="-initParams sga_target=${sga}M,pga_aggregate_target=${pga}M"
       fi 
       
    fi
    ## Adding env var to disable custom scripts run post db creation
    #
    SQLSCRIPT_CONSTRUCT="-customScripts $ORACLE_HOME/assistants/dbca/postdb_creation.sql"
    if [ "x$NO_POSTSCRIPT" != "x" ]
    then
       SQLSCRIPT_CONSTRUCT=""
    fi
    
    echo "Configuring Oracle Listener."

    ORABASE=`$ORACLE_HOME/bin/orabase`
    NETCA_LOG_DIR="$ORABASE/cfgtoollogs/netca"
    if [ ! -d "$NETCA_LOG_DIR" ]
    then
       $SU -s /bin/bash $ORACLE_OWNER -c "$MKDIR_CMD -p $NETCA_LOG_DIR"
    fi
    NETCA_LOG="$NETCA_LOG_DIR/netca_configure_out.log"
    if [ ! -f "$NETCA_LOG" ]
    then
       $SU -s /bin/bash $ORACLE_OWNER -c "echo Netca configuration log > $NETCA_LOG"
       chmod 640 $NETCA_LOG
    fi

    $SU -s /bin/bash $ORACLE_OWNER -c "$NETCA /orahome $ORACLE_HOME /instype typical /inscomp client,oraclenet,javavm,server,ano /insprtcl tcp /cfg local /authadp NO_VALUE /responseFile $ORACLE_HOME/network/install/netca_typ.rsp /silent  /orahnam $ORACLE_HOME_NAME /listenerparameters DEFAULT_SERVICE=FREE $LSNRPORT_CONSTRUCT >> $NETCA_LOG" 

    RETVALNETCA=$?
    if [ $RETVALNETCA -eq 0 ]
    then
        $SU -s /bin/bash $ORACLE_OWNER -c "$LSNR start $LISTENER_NAME > /dev/null"
        $SU -s /bin/bash $ORACLE_OWNER -c "$LSNR status $LISTENER_NAME > /dev/null"
        RETVALLSNRCTL=$?
        if [ $RETVALLSNRCTL -eq 0 ]
        then
                echo "Listener configuration succeeded."
        else
                echo "Listener configuration failed. Check logs under '$NETCA_LOG_DIR'."
                exit 1
        fi
    else
        echo "Listener configuration failed. Check log '$NETCA_LOG' for more details."
        exit 1
    fi


    echo "Configuring Oracle Database $ORACLE_SID."
   
 
    DBCA_CLI="$DBCA -silent -createDatabase -templateName $TEMPLATE_NAME -characterSet $CHARSET -createAsContainerDatabase $CREATE_AS_CDB -numberOfPDBs $NUMBER_OF_PDBS -pdbName $PDB_NAME -sid $ORACLE_SID -J-Doracle.assistants.dbca.validate.DBCredentials=false -ignorePrereqs -J-Doracle.assistants.skipAvailableSharedMemoryCheck=true -skipDatapatch true $SQLSCRIPT_CONSTRUCT $DBFILE_CONSTRUCT $MEMORY_CONSTRUCT $DBDOMAIN_CONSTRUCT $CONFIGURE_TDE_CONSTRUCT $TABLESPACES_CONSTRUCT" 
    if [ "x$CONFIGURE_TDE" = "xtrue" ]    
    then
	(echo $ORACLE_PASSWORD; echo $ORACLE_PASSWORD; echo $ORACLE_PASSWORD; echo $ORACLE_PASSWORD) | $SU -s /bin/bash  $ORACLE_OWNER -c $DBCA_CLI
    else
	(echo $ORACLE_PASSWORD; echo $ORACLE_PASSWORD; echo $ORACLE_PASSWORD) | $SU -s /bin/bash  $ORACLE_OWNER -c $DBCA_CLI
    fi
       
    RETVAL=$?
    
    echo
    if [ $RETVAL -eq 0 ]
    then
         print_success_connect
         return 0
    else
        echo "Database configuration failed. Check logs under '$ORABASE/cfgtoollogs/dbca'."
        exit 1
    fi
    return 0
}
print_success_connect()
{

  connectstr=`$ORACLE_HOME/bin/lsnrctl status $LISTENER_NAME |grep Connecting`
  if [ "x$connectstr" != "x" ]
  then
    str1=($connectstr)
    portfound=0
    i=0
    for str in "${str1[@]}"
    do
      istr=`echo $str`
      if [ "$portfound" = "1" ]
      then
        break
      else
        if [ "x$istr" != "x" ]
        then
                if [ "$istr" != "${istr/\(PORT/}" ] 
                then
                        portfound=1
                        index=$i
                fi
        fi
      fi
     i=$(( $i+1 ))
   done 
  fi
  if [ index = 0 ]
  then
    portv="PORT"
  else
    finalstr="${str1[index]}"
    finalstr=`echo $finalstr |cut -d'=' -f 6`
    portv="${finalstr/\)*/}"
  fi
  if [ "x$portv" = "x" ]
  then
    portv="PORT"
  fi
  hostname=`$HOSTNAME_CMD`
  if [ "x$portv" = "x1521" ]
  then
	connectstr1="$hostname"
	connectstr2="$hostname/$PDB_NAME"
  else
	connectstr1="$hostname:$portv"
	connectstr2="$hostname:$portv/$PDB_NAME"
  fi

  echo "Connect to Oracle Database using one of the connect strings:"
  echo '     Pluggable database: '$connectstr2''
  echo '     Multitenant container database: '$connectstr1''

}

# Enh 27965939 - Unsets the proxy env variables
unset_proxy_vars()
{
    if [ "$http_proxy" != "" ]
    then
        unset http_proxy
    fi

    if [ "$HTTP_PROXY" != "" ]
    then
        unset HTTP_PROXY
    fi

    if [ "$https_proxy" != "" ]
    then
        unset https_proxy
    fi

    if [ "$HTTPS_PROXY" != "" ]
    then
        unset HTTPS_PROXY
    fi
}

# Check if the DB is already configured
check_for_configuration()
{
    configfile=`$GREP --no-messages ^$ORACLE_SID: /etc/oratab` > /dev/null 2>&1
    if [ "$configfile" = "" ]
    then
        return 1
    fi
    return 0
}

read_config_file()
{
    if [ -f "$CONFIGURATION" ]
    then
        . "$CONFIGURATION"
    else
        echo "The Oracle Database is not configured. Unable to read the configuration file '$CONFIGURATION'"
        exit 1;
    fi
}

# Validation method to check for the port availability for Oracle DB listener
check_port_availability()
{
    if [ "x$SKIP_VALIDATIONS" = "xtrue" ]
    then
	return 0
    fi
    if [ "x$LISTENER_PORT" = "x" ]
    then
       return 0    
    fi    
    
    $SU -s /bin/bash $ORACLE_OWNER -c "$LSNR  status LISTENER" > /dev/null 2>&1
        RETVAL=$?
        if [ $RETVAL -eq 0 ]
        then
            echo "Oracle Net Listener configured."
	    return 0
        fi
    port=`$SS -n --tcp --listen | $GREP :$LISTENER_PORT`
    if [ "$port" != "" ]
    then
        echo "Port $LISTENER_PORT appears to be in use by another application. Specify a different port in the configuration file '$CONFIGURATION'"
        exit 1;
    fi
}

check_memory()
{
        if [ "x$SKIP_VALIDATIONS" = "xtrue" ]
	then
		return 0
	fi
     	mem=`cat /proc/meminfo |grep MemFree`
	if [ "x$mem" != "x" ]
	then
   		str=($mem)
   		echo "Free memory available in the system ${str[1]}"
		if [ "${str[1]}" -lt "$MINIMUM_MEMORY" ]
		then
			echo "Free memory available is not enough for database configuration"
			echo "Need at least $MINIMUM_MEMORY_STR free for database configuration"
			exit 1
		fi
	fi
}

check_space()
{
        if [ "x$SKIP_VALIDATIONS" = "xtrue" ]
        then
                return 0
        fi
        
        DBF_DEST_VALID=$DBFILE_DEST	
    	if [ "x$DBF_DEST_VALID" = "x" ]
	then
		DBF_DEST_VALID=`$ORACLE_HOME/bin/orabase`
	fi
    	if [ "x$DBF_DEST_VALID" != "x" ]
	then
		dspace=`$DF -k $DBF_DEST_VALID --output=source,avail | $TAIL -n 1| $AWK '{print $2}'`
		dspace="${dspace//[$'\t\r\n ']}"
	        if [ "x$dspace" != "x" ]
        	then
                	if [ "$dspace" -lt "$MINIMUM_SPACE" ]
                	then
                              echo "The location '$DBF_DEST_VALID' specified for database files has insufficient space."
                              echo "Database creation needs at least '$MINIMUM_SPACE_STR' disk space."
                              echo "Specify a different database file destination that has enough space in the configuration file '$CONFIGURATION'."
                              exit 1
                	fi
		fi
        fi
}


# Entry point to configure the DB
configure()
{
    check_for_configuration
    RETVAL=$?
    if [ $RETVAL -eq 0 ]
    then
        echo "There is an Oracle Database instance $ORACLE_SID already configured in the server."
        exit 1
    fi
    read_config_file
    check_space
    check_port_availability
    configure_ask
    configure_perform
}



configure_ask()
{
    if [ "x$ORACLE_PASSWORD" != "x" ]
        then
                return 0
        fi
    
    #get the database password
	    while :
	    do
	    echo -n "Specify a password to be used for database accounts. Oracle recommends that the password entered should be at least 8 characters in length, contain at least 1 uppercase character, 1 lower case character and 1 digit [0-9]. Note that the same password will be used for SYS, SYSTEM and PDBADMIN accounts:"
	     while [ 1 ]
             do
	     /bin/stty -echo > /dev/null 2>&1
	     temp=`echo $IFS`
             export IFS="\n"	
	     while [ 1 ]
  	     do
	     read LINE
             while [ -z "$LINE" ]
	     do
		 echo
		 echo -n "Password cannot be null. Enter password:"  
	         read LINE
	     done

	     result=`expr index "$LINE" [\!\@\%\^\&\*\(\)\+\=\\|~\[\]{}\;\:\'\"\,\<\>\/\?]`
	     if [ $result != 0 ];
	     then
             	echo 
			echo -n "The password you entered contains invalid characters. Enter password:"
	     else
		break
	     fi
	     done
		echo
		echo -n "Confirm the password:"
	        read LINE1
		echo
                if [ "$LINE" != "$LINE1" ];
		then
			if [ ! -z $1 ]
			then
				echo
				echo "Passwords do not match. Specify the same password for both ORACLE_PASSSWORD and 
ORACLE_CONFIRM_PASSWORD, and retry the configuration."
				trap "rm -fr $1" exit
				exit
			fi
			echo    
			echo -n "Passwords do not match.  Enter the password:"
		else
			break
		fi
	done
            /bin/stty echo > /dev/null 2>&1
            ORACLE_PASSWORD=$LINE
	    export IFS=$temp
            break;
	done

}

restart()
{
    # Check if the DB is already stopped
    pmon=`ps -ef | egrep pmon_$ORACLE_SID'\>' | $GREP -v grep`
    if [ "$pmon" = "" ]
    then
        start
    else
        stop
        start
    fi
}

status()
{
    echo "Status of the Oracle $ORACLE_SID 23ai service:"
    echo ""
    listener_status="NOT CONFIGURED"
    database_status="NOT CONFIGURED"
    #Scan the Listener component first
    #Check for listener configuration
    orabasehome=`$ORACLE_HOME/bin/orabasehome`
    deflt_service="false"
    deflt_lsnr="false"
    if [ -e $orabasehome/network/admin/listener.ora ]
    then

        while read line; do
           if [ "$line" != "${line#DEFAULT_SERVICE_LISTENER*}" ]
           then
               deflt_service="true"
           fi
    
           if [ "$line" != "${line#LISTENER*}" ]
           then
               deflt_lsnr="true"
           fi

        done < $orabasehome/network/admin/listener.ora

    fi

    if [ $deflt_service = "true" ] && [ $deflt_lsnr = "true" ]
    then
        listener_status="STOPPED"
    fi

    $SU -s /bin/bash $ORACLE_OWNER -c "$LSNR  status LISTENER" > /dev/null 2>&1
    RETVAL=$?
    if [ $RETVAL -eq 0 ]
    then
       listener_status="STOPPED"
    fi
    #Check for listener execution
    process=`ps -ef | egrep "$ORACLE_HOME/bin/tnslsnr $LISTENER_NAME" | $GREP -v grep`
    if [ "$process" != "" ]
    then
       listener_status="RUNNING"
    fi
    #Then proceed with the Database
    #Check for database configuration
    oratab_content=`$GREP --no-messages $ORACLE_SID:$ORACLE_HOME /etc/oratab` > /dev/null 2>&1
    if [ "$oratab_content" != "" ]
    then
        database_status="STOPPED"
    fi
    #Check for database execution
    process=`ps -ef | egrep pmon_$ORACLE_SID'\>' | $GREP -v grep`
    if [ "$process" != "" ]
    then
       database_status="RUNNING"
    fi
    #Finally we print the summary
    echo "$LISTENER_NAME status: $listener_status"
    echo "$ORACLE_SID Database status:   $database_status"

}

case "$1" in
    start)
        start
    ;;
    stop)
        stop
    ;;
    configure)
        configure
    ;;
    delete)
        configure_delete
    ;;
    restart)
        restart
    ;;
    status)
        status
    ;;
    *)
        echo $"Usage: $0 {start|stop|restart|configure|delete|status}"
        exit 1
    ;;
esac

exit 0
