#!/bin/bash


##### FUNCTIONS ################################################################


func_HELP() {
    
    if [[ "$1" != "" ]]
    then
        printf '\n'
        printf '%s\n' "ERROR: $@"
    fi
    
    cat << 'EOF'

Dead Man's Switch v1.0.0 | Copyright (c) 2020 Perkolator
https://github.com/Perkolator/dead-mans-switch
Licensed under the MIT License as described in the file LICENSE.

Script for unmounting inactive encrypted shares automatically.
Meant to be run from Synology DSM Task Scheduler.

Usage  : bash <full path>/dead_mans_switch.bash [OPTION]...
Example: bash <full path>/dead_mans_switch.bash -d 2 --email

  -d NUM, --days NUM   Unmount after number of days of inactivity. (default 3)
  -l NUM, --log NUM    Log script output: 0 = No logging
                                          1 = Unmount logging (default)
                                          2 = Full logging
  -e, --email          Email log. Empty unmount logs will not be sent.
                       Note! Script exits with an error code for this to work.

  Email notification service from Synology "Control Panel -> Notification"
  needs to be enabled for the email log sending feature to work properly.

  "Save output results" needs to be turned on from Synology
  "Control Panel -> Task Scheduler -> Settings" for the logging to work.

  "Send run details by email" and "Send run details only when the script
  terminates abnormally" needs to be turned on from the task settings.

  Script file needs executable rights and task should be run with "root" user.

Notes:

"Inactivity" means no user connections to shares. The precision of detecting
inactivity isn't that great because Synology doesn't log every connection to a
share. It's safe to assume at least one logged connection to a share per day if
the user is actively using the share. Scheduling a task to run the script once
or twice a day should be enough to give reasonable precision and functionality.

At first, and also after Synology DSM update, it's wise to run the script with
full logging and email options for a while to see that all works as expected.

Any detected errors are always emailed, whether the email option is used or not.

If some machine on your network, or remotely, automatically connects
to an encrypted share, this script obviously won't work properly.

EOF

    exit 1
}


func_USAGE() {

    printf '\n' 1>&2
    printf '%s\n' "ERROR: $@" 1>&2
    printf '\n' 1>&2
    
    printf '%s\n' \
            "Script for unmounting inactive encrypted shares automatically." \
            "Usage: bash <full path>/dead_mans_switch.bash [OPTION]..." \
            "Try '--help' option for more information." 1>&2
    
    exit 1
}


func_ERROR() {
    
    printf '\n' 1>&2
    printf '%s\n' "ERROR: $@" 1>&2
    
    if [[ "$str_FULLLOG" != "" ]]
    then
        printf '\n%s\n' '--- FULL LOG ----------------------------' 1>&2
        printf '%s\n' "$str_FULLLOG" 1>&2
    fi
    
    exit 1
}


##### VARIABLES ################################################################


int_DAYS=3
int_LOG=1
int_EMAIL=0

str_FULLLOG=''
str_UNMOUNTLOG=''
str_SYNOCONNDB='/var/log/synolog/.SYNOCONNDB'


##### CHECK FOR PROBLEMS #######################################################


# Check that the script was ran from Synology Task Scheduler.
str_PPCOMM=$( ps --no-headers --format comm $PPID )

if ! [[ "$str_PPCOMM" == "synoschedtask" \
     || "$str_PPCOMM" == "SYNO.Core.TaskS" ]]
then
    func_HELP "Script was not run from Synology DSM Task Scheduler!" \
                "Parent process command was: '$str_PPCOMM'," \
                "expected: 'synoschedtask' or 'SYNO.Core.TaskS'."
fi


# Check if sqlite3 can be found and is executable.
if [[ ! -x "$( command -v sqlite3 )" ]]
then
    func_ERROR "Can't find or run 'sqlite3' program!"
fi

# Check if synoshare can be found and is executable.
if [[ ! -x "$( command -v synoshare )" ]]
then
    func_ERROR "Can't find or run 'synoshare' program!"
fi


# Check if the "--get" option of "synoshare" has been changed.
str_REGEX='^[[:blank:]]*--get sharename[[:blank:]]*$'

if [[ "$( synoshare --help | grep -c "$str_REGEX" )" != "1" ]]
then
    func_ERROR "The '--get' option of 'synoshare' program has been changed!"
fi

# Check if the "--enc_unmount" option of "synoshare" has been changed.
str_REGEX='^[[:blank:]]*--enc_unmount sharename1 sharename2 \.\.\.[[:blank:]]*$'

if [[ "$( synoshare --help | grep -c "$str_REGEX" )" != "1" ]]
then
    func_ERROR \
        "The '--enc_unmount' option of 'synoshare' program has been changed!"
fi

# Check if the "--enum" option of "synoshare" has been changed.
str_REGEX='^[[:blank:]]*'
str_REGEX+='--enum {ALL}|{LOCAL|USB|SATA|ENC|DEC|GLUSTER}{+}[[:blank:]]*$'

if [[ "$( synoshare --help | grep -c "$str_REGEX" )" != "1" ]]
then
    func_ERROR "The '--enum' option of 'synoshare' program has been changed!"
fi


# Check if the output of 'synoshare --enum' has been changed.
# Also save the line number where the last status message appears.
str_REGEX='^[0-9]\+ Listed:[[:blank:]]*$'

int_LISTEDLINE="$( synoshare --enum DEC | grep -n "$str_REGEX" | cut -f1 -d: )"

if [[ "$int_LISTEDLINE" == "" ]]
then
    func_ERROR "Output of 'synoshare --enum' has been changed!"
fi


# Check if the "Connection" DB file can't be read.
if [[ ! -r "$str_SYNOCONNDB" ]]
then
    func_ERROR "The file '$str_SYNOCONNDB' can't be read!"
fi


# SQL query for testing.
mix_SQLTEST="$( sqlite3 "$str_SYNOCONNDB" '
    SELECT time
    FROM logs
    WHERE msg
    LIKE "%accessed shared folder [%"
    ORDER BY id
    LIMIT 1;
' 2>&1 )"

# Check if the SQL query produced an error.
if [[ "$?" != "0" ]]
then
    func_ERROR "SQL query failed! The Connection DB has been altered." \
                "Output from sqlite3: $mix_SQLTEST"
fi

# Check if the SQL query returned zero share access entries.
if [[ "$mix_SQLTEST" == "" ]]
then
    func_ERROR "Can't find any share access entries from Connection DB!" \
                "Synology might have changed the log message syntax," \
                "or there are no connections to shares yet."
fi

# Check if the SQL query returned an invalid timestamp.
date --date="@$mix_SQLTEST" >/dev/null 2>&1

if [[ "$?" != "0" ]]
then
    func_ERROR "Can't find valid timestamps from Connection DB!"
fi


##### CMDLINE OPTIONS & ARGUMENTS ##############################################


while [[ "$1" != "" ]]
do
    case "$1" in
        
        -d | --days )
            
            # Check for a valid option argument.
            if [[ ! "$2" =~ ^[0-9]+$ ]]
            then
                func_USAGE "Argument for option '$1' is missing or invalid."
            fi
            
            shift
            int_DAYS=$(( $1 ))
            ;;
            
        -l | --log )
            
            # Check for a valid option argument.
            if [[ "$2" != [0-2] ]]
            then
                func_USAGE "Argument for option '$1' is missing or invalid."
            fi
            
            shift
            int_LOG=$1
            ;;
            
        -e | --email )
            
            int_EMAIL=1
            ;;
            
        -h | --help )
            
            func_HELP
            ;;
            
        * )
            func_USAGE "Invalid option '$1'."
            ;;
    esac
    
    shift
done


##### MAIN #####################################################################


# Read output of "synoshare --enum DEC" as lines.
# Skipping the status message lines at the beginning.
while IFS=$'\n' read -r str_LINE
do
    str_LINELOG=''
    
    # Check if the line has a real share name.
    synoshare --get "$str_LINE" >/dev/null 2>&1
    
    if [[ "$?" != "0" ]]
    then
        func_ERROR "Non-existing share name of '$str_LINE'" \
                    "was found from the output of 'synoshare --enum'!" \
                    "Synology might have changed the output syntax."
    fi
    
    # Get the timestamp of last access to a share.
    int_TIMESTAMP="$( sqlite3 "$str_SYNOCONNDB" '
        SELECT time
        FROM logs
        WHERE msg
        LIKE "%accessed shared folder ['"$str_LINE"']%"
        ORDER BY id
        DESC
        LIMIT 1;
    ' )"
    
    str_LINELOG+=$'\n'"Share  : $str_LINE"
    
    # Process a share that has a last access timestamp in the DB.
    if [[ "$int_TIMESTAMP" != "" ]]
    then
        str_LINELOG+=$'\n'"Access : $( date -R --date="@$int_TIMESTAMP" )"
        str_LINELOG+=$'\n'"Action : "
        
        # Check if a share should be closed.
        if [[ "$( date +%s )" -ge "$(( $int_DAYS * 86400 + $int_TIMESTAMP ))" ]]
        then
            # Try unmounting.
            str_UNMOUNTRESULT="$( synoshare --enc_unmount "$str_LINE" 2>&1 )"
            
            if [[ "$?" != "0" ]]
            then
                func_ERROR "There was a problem unmounting '$str_LINE' share!" \
                            "Output from synoshare: $str_UNMOUNTRESULT"
            fi
            
            str_LINELOG+="Unmounted"$'\n'
            
            str_UNMOUNTLOG+="$str_LINELOG"
        else
            str_LINELOG+="-"$'\n'
        fi
        
        str_FULLLOG+="$str_LINELOG"
        
    # Unmount share automatically if there's no last access timestamp in the DB.
    else
        str_LINELOG+=$'\n'"Access : -"
        
        # Try unmounting.
        str_UNMOUNTRESULT="$( synoshare --enc_unmount "$str_LINE" 2>&1 )"
        
        if [[ "$?" != "0" ]]
        then
            func_ERROR "There was a problem unmounting '$str_LINE' share!" \
                        "Output from synoshare: $str_UNMOUNTRESULT"
        fi
        
        str_LINELOG+=$'\n'"Action : Unmounted"$'\n'
        
        str_UNMOUNTLOG+="$str_LINELOG"
        str_FULLLOG+="$str_LINELOG"
    fi
    
done < <( synoshare --enum DEC | tail -n +"$(( $int_LISTEDLINE + 1 ))" )


# Check if there were no mounted shares at all.
if [[ "$str_FULLLOG" == "" ]]
then
    str_FULLLOG=$'\n''There were no mounted encrypted shares.'
fi


# Unmount logging.
# Empty unmount log is not saved to log file nor emailed.
if [[ "$int_LOG" == "1" && "$str_UNMOUNTLOG" != "" ]]
then
    printf '\n%s\n' '--- UNMOUNT LOG -------------------------'
    printf '%s\n' "$str_UNMOUNTLOG"
    
    if [[ "$int_EMAIL" == "1" ]]
    then
        exit 1
    fi
fi

# Full logging.
if [[ "$int_LOG" == "2" ]]
then
    printf '\n%s\n' '--- FULL LOG ----------------------------'
    printf '%s\n' "$str_FULLLOG"
    
    if [[ "$int_EMAIL" == "1" ]]
    then
        exit 1
    fi
fi
