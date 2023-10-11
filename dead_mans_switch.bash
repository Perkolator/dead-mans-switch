#!/bin/bash


##### FUNCTIONS ################################################################


function func_HELP {
    
    if [[ "$#" != "0" ]]
    then
        printf '\n'
        printf '%s\n' "ERROR: $@"
    fi
    
    cat << 'EOF'

Dead Man's Switch v2.0.0 | Copyright (c) 2020-2023 Perkolator
https://github.com/Perkolator/dead-mans-switch
Licensed under the MIT License as described in the file LICENSE.

Script for unmounting inactive encrypted shares automatically.
Meant to be run from Synology DSM 6/7 Task Scheduler.
More information in the README.md file.

Usage  : /bin/bash <full path>/dead_mans_switch.bash [OPTION]...
Example: /bin/bash /volume1/share/folder/dead_mans_switch.bash -d 3 --email

  -d NUM, --days NUM   Unmount after number of days of inactivity. (default 2)
  -s      --strict     Unmount ALL if even one of the mounted encrypted shares
                       is found inactive (or has never been accessed, or returns
                       an error or an invalid time value from a database query),
                       regardless of when other shares have been last accessed.
  -l NUM, --log NUM    Logging: 0) None, 1) Unmount events (default), 2) Full
  -e,     --email      Email log. Empty unmount logs will not be sent.
                       Note! Script exits with an error code for this to work.
  -h,     --help       Display help text.

  Email notification service from Synology "Control Panel -> Notification"
  needs to be enabled for the email log sending feature to work properly.

  "Save output results" needs to be enabled from Synology
  "Control Panel -> Task Scheduler -> Settings" for the logging to work.

  "Send run details by email" and "Send run details only when the script
  terminates abnormally" needs to be enabled from the task settings.

  Script file needs executable rights and task should be run with "root" user.

EOF
    
    exit 1
}


function func_ERROR {
    
    printf '\n'
    printf '%s\n' "ERROR(S): $@"
    
    if [[ "$str_FULLLOG" != "" ]]
    then
        printf '\n%s\n' '--- FULL LOG -----------------------------'
        printf '%s\n' "$str_FULLLOG"
    fi
    
    exit 1
}


function func_UNMOUNT {
    
    local str_local_SHARENAME="$1"
    local str_local_RESULT=''
    local int_local_i=0
    
    # Try to unmount the share max 3 times.
    for int_local_i in {1..3}
    do
        str_local_RESULT="$( synoshare --enc_unmount \
                                 "$str_local_SHARENAME" 2>&1 )"
        
        if [[ "$?" == "0" ]]
        then
            # Break out from function and send "ok" return code.
            return 0
        else
            # Little pause if trying unmounting again.
            if [[ "$int_local_i" != "3" ]]
            then
                sleep 2
            fi
        fi
    done
    
    # Return the output of the last failed unmount command.
    printf '%s' "$str_local_RESULT"
    
    # Send "error" return code.
    return 1
}


##### VARIABLES ################################################################


int_DAYS=2
int_STRICT=0
int_LOG=1
int_EMAIL=0

int_TIMESTAMP="$( date +%s )"

str_ERRORLOG=''
str_FULLLOG=''
str_UNMOUNTLOG=''

str_SYNOCONNDB='/var/log/synolog/.SYNOCONNDB'


##### CHECK FOR PROBLEMS #######################################################


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

if [[ "$( synoshare --help | grep --count -- "$str_REGEX" )" != "1" ]]
then
    func_ERROR "The '--get' option of 'synoshare' program has been changed!"
fi

# Check if the "--enc_unmount" option of "synoshare" has been changed.
str_REGEX='^[[:blank:]]*--enc_unmount sharename1 sharename2 \.\.\.[[:blank:]]*$'

if [[ "$( synoshare --help | grep --count -- "$str_REGEX" )" != "1" ]]
then
    func_ERROR \
        "The '--enc_unmount' option of 'synoshare' program has been changed!"
fi

# Check if the "--enum" option of "synoshare" has been changed.
# DSM 7
str_REGEX='^[[:blank:]]*--enum {ALL}|{LOCAL|USB|SATA|ENC|DEC|GLUSTER|C2|'
str_REGEX+='COLD-STORAGE|MISSING-VOL|OFFLINE-VOL|CEPH|WORM}{+}[[:blank:]]*$'

if [[ "$( synoshare --help | grep --count -- "$str_REGEX" )" != "1" ]]
then
    # DSM 6
    str_REGEX='^[[:blank:]]*'
    str_REGEX+='--enum {ALL}|{LOCAL|USB|SATA|ENC|DEC|GLUSTER}{+}[[:blank:]]*$'
    
    if [[ "$( synoshare --help | grep --count -- "$str_REGEX" )" != "1" ]]
    then
        func_ERROR \
            "The '--enum' option of 'synoshare' program has been changed!"
    fi
fi


# Check if the output of 'synoshare --enum' has been changed.
# Also save the line number where the last status message appears.
str_REGEX='^[0-9]\+ Listed:[[:blank:]]*$'

int_LISTEDLINE="$( synoshare --enum DEC \
                 | grep --line-number -- "$str_REGEX" \
                 | cut --delimiter=":" --fields=1 )"

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
mix_SQLTEST="$( sqlite3 -readonly -safe file:"$str_SYNOCONNDB" \
   'SELECT time
    FROM logs
    WHERE msg
    LIKE "%accessed shared folder [%"
    ORDER BY id
    LIMIT 1;' 2>&1 )"

# Check if the SQL query produced an error.
if [[ "$?" != "0" ]]
then
    func_ERROR "SQL query failed! The Connection DB has been altered." \
               "Output from sqlite3:" \
               "'$mix_SQLTEST'"
fi

# Check if the SQL query returned zero share "accessed" entries.
if [[ "$mix_SQLTEST" == "" ]]
then
    func_ERROR "Can't find any share 'accessed' entries from Connection DB!" \
               "Synology might have changed the log message syntax," \
               "or there are no connections to shares yet."
fi

# Check if the SQL query returned an invalid timestamp.
date --date="@$mix_SQLTEST" >/dev/null 2>&1

if [[ "$?" != "0" ]]
then
    func_ERROR "Can't find valid timestamps from Connection DB!"
fi


##### OPTIONS & PARAMETERS #####################################################


while [[ "$#" != "0" ]]
do
    case "$1" in
        
        -d | --days )
            
            # Check for a valid option parameter.
            if [[ ! "$2" =~ ^[0-9]+$ ]]
            then
                func_HELP "Parameter for option '$1' is missing or invalid."
            fi
            
            shift
            int_DAYS=$(( $1 ))
            ;;
            
        -l | --log )
            
            # Check for a valid option parameter.
            if [[ "$2" != [0-2] ]]
            then
                func_HELP "Parameter for option '$1' is missing or invalid."
            fi
            
            shift
            int_LOG=$1
            ;;
            
        -s | --strict )
            
            int_STRICT=1
            ;;
            
        -e | --email )
            
            int_EMAIL=1
            ;;
            
        -h | --help )
            
            func_HELP
            ;;
            
        * )
            func_HELP "Invalid option '$1'."
            ;;
    esac
    
    shift
done


##### MAIN #####################################################################


# Get all valid mounted encrypted share names.
# Read output of "synoshare --enum DEC" as lines.
# Skipping the status message lines at the beginning.
#
# Also get all last "accessed" timestamps of found mounted encrypted shares
# at this point because when unmounting an encrypted share in DSM 7,
# all other mounted encrypted shares get new "accessed" database entries
# if there are still "active" connections to those shares.
arr_SHARENAME=()
arr_SHARETIME=()
while IFS=$'\n' read -r str_LINE
do
    # Check if the line has a real share name.
    synoshare --get "$str_LINE" >/dev/null 2>&1
    
    if [[ "$?" != "0" ]]
    then
        str_ERRORLOG+="$( printf '%s\n' \
            $'\n' \
            "- Non-existing share name of '$str_LINE'" \
            "was found from the output of 'synoshare --enum'!" \
            "Synology might have changed the output syntax." )"
        
        # Skip rest of the iteration for the current line.
        continue
    fi
    
    
    # Get the timestamp of the last access to a share.
    mix_SQLRESULT="$( sqlite3 -readonly -safe file:"$str_SYNOCONNDB" \
       'SELECT time
        FROM logs
        WHERE msg
        LIKE "%accessed shared folder ['"$str_LINE"']%"
        ORDER BY id
        DESC
        LIMIT 1;' 2>&1 )"
    
    # Check if the SQL query produced an error.
    if [[ "$?" != "0" ]]
    then
        str_ERRORLOG+="$( printf '%s\n' \
            $'\n' \
            "- SQL query to Connection DB failed for share '$str_LINE'!" \
            "As a precaution, the share will be unmounted immediately." \
            "Output from sqlite3:" \
            "'$mix_SQLRESULT'" )"
        
        # Set the timestamp value as error, the share will be closed later.
        mix_SQLRESULT="ERROR"
    fi
    
    # Check if the SQL query returned an invalid timestamp.
    if [[ "$mix_SQLRESULT" != "" \
       && "$mix_SQLRESULT" != "ERROR" ]]
    then
        date --date="@$mix_SQLRESULT" >/dev/null 2>&1
        
        if [[ "$?" != "0" ]]
        then
            str_ERRORLOG+="$( printf '%s\n' \
                $'\n' \
                "- SQL query to Connection DB failed to find" \
                "a valid timestamp for share '$str_LINE'!" \
                "As a precaution, the share will be unmounted immediately." )"
            
            # Set the timestamp value as error, the share will be closed later.
            mix_SQLRESULT="ERROR"
        fi
    fi
    
    arr_SHARENAME+=( "$str_LINE" )
    arr_SHARETIME+=( "$mix_SQLRESULT" )
    
done < <( synoshare --enum DEC | tail --lines=+"$(( $int_LISTEDLINE + 1 ))" )


# If "strict" option was used, check if ALL mounted encrypted shares should be
# unmounted if even one them is found inactive (or other conditions are met),
# regardless of when other mounted encrypted shares have been last accessed.
#
# Do not check if only one mounted encrypted share was found.
if [[ "$int_STRICT"          == "1" \
   && "${#arr_SHARENAME[@]}" != "1" ]]
then
    for i in "${!arr_SHARENAME[@]}"
    do
        # For a share that had a valid "accessed" timestamp in the DB.
        if [[ "${arr_SHARETIME[$i]}" != "" \
           && "${arr_SHARETIME[$i]}" != "ERROR" ]]
        then
            # Check if a share should be closed.
            #
            # When unmounting a share in DSM 7, it creates new "accessed"
            # timestamps for shares that have "active" connections to them.
            # Making the comparison timestamp a little
            # smaller (120 sec) avoids delays to next unmounts
            # those new timestamps might otherwise create.
            if [[ "$int_TIMESTAMP" -ge \
                  "$(( $int_DAYS * 86400 + ${arr_SHARETIME[$i]} - 120 ))" ]]
            then
                # Set to close all shares.
                int_STRICT="2"
                # Save the share name that triggered it.
                str_STRICTSHARENAME="${arr_SHARENAME[$i]}"
                # Jump out of the for loop.
                break
            fi
        
        # For a share that:
        # - had no "accessed" timestamp in the database.
        # - failed the SQL query for a timestamp.
        # - returned an invalid timestamp from the SQL query.
        else
            # Set to close all shares.
            int_STRICT="2"
            # Save the share name that triggered it.
            str_STRICTSHARENAME="${arr_SHARENAME[$i]}"
            # Jump out of the for loop.
            break
        fi
    done
fi


# If all mounted encrypted shares are to be forced
# to unmount, write a note about it in the logs.
if [[ "$int_STRICT" == "2" ]]
then
    str_UNMOUNTLOG=$'\n'"$( printf '%s\n' \
        "All mounted encrypted shares were selected" \
        "for unmounting because the 'strict' option" \
        "was used and one of the conditions was met" \
        "for a share: '$str_STRICTSHARENAME'."  )"$'\n'
    
    str_FULLLOG="$str_UNMOUNTLOG"
fi


# Iterate through all found mounted encrypted shares,
# if any, and try to unmount if conditions apply.
for i in "${!arr_SHARENAME[@]}"
do
    str_LINELOG=$'\n'"Share  : ${arr_SHARENAME[$i]}"
    
    # For a share that had a valid "accessed" timestamp in the DB.
    if [[ "${arr_SHARETIME[$i]}" != "" \
       && "${arr_SHARETIME[$i]}" != "ERROR" ]]
    then
        str_LINELOG+=$'\n'"Access : $( date --rfc-email \
                                            --date="@${arr_SHARETIME[$i]}" )"
        
        # Check if a share should be closed.
        #
        # When unmounting a share in DSM 7, it creates new "accessed"
        # timestamps for shares that have "active" connections to them.
        # Making the comparison timestamp a little smaller (120 sec) avoids
        # delays to next unmounts those new timestamps might otherwise create.
        if [[ "$int_STRICT" == "2" ]] \
           || \
           [[ "$int_TIMESTAMP" -ge \
              "$(( $int_DAYS * 86400 + ${arr_SHARETIME[$i]} - 120 ))" ]]
        then
            # Try unmounting.
            str_UNMOUNTRESULT="$( func_UNMOUNT "${arr_SHARENAME[$i]}" )"
            
            if [[ "$?" != "0" ]]
            then
                str_ERRORLOG+="$( printf '%s\n' \
                    $'\n' \
                    "- Failed to unmount share '${arr_SHARENAME[$i]}'!" \
                    "Output from synoshare:" \
                    "'$str_UNMOUNTRESULT'" )"
                
                str_LINELOG+=$'\n'"Action : - (ERROR)"
            else
                str_LINELOG+=$'\n'"Action : Unmounted"
                
                str_UNMOUNTLOG+="$str_LINELOG"$'\n'
            fi
        else
            str_LINELOG+=$'\n'"Action : -"
        fi
        
    # Unmount a share automatically that:
    # - had no "accessed" timestamp in the database.
    # - failed the SQL query for a timestamp.
    # - returned an invalid timestamp from the SQL query.
    else
        if [[ "${arr_SHARETIME[$i]}" == "ERROR" ]]
        then
            str_LINELOG+=$'\n'"Access : - (ERROR)"
        else
            str_LINELOG+=$'\n'"Access : -"
        fi
        
        # Try unmounting.
        str_UNMOUNTRESULT="$( func_UNMOUNT "${arr_SHARENAME[$i]}" )"
        
        if [[ "$?" != "0" ]]
        then
            str_ERRORLOG+="$( printf '%s\n' \
                $'\n' \
                "- Failed to unmount share '${arr_SHARENAME[$i]}'!" \
                "Output from synoshare:" \
                "'$str_UNMOUNTRESULT'" )"
            
            str_LINELOG+=$'\n'"Action : - (ERROR)"
            
        else
            str_LINELOG+=$'\n'"Action : Unmounted"
            
            str_UNMOUNTLOG+="$str_LINELOG"$'\n'
        fi
    fi
    
    str_FULLLOG+="$str_LINELOG"$'\n'
    
done


# Check if there were no mounted encrypted shares at all.
if [[ "$str_FULLLOG" == "" ]]
then
    str_FULLLOG=$'\n''There were no mounted encrypted shares.'
fi


# Check if there were errors. Emails both error and full log.
if [[ "$str_ERRORLOG" != "" ]]
then
    func_ERROR "$str_ERRORLOG"
fi


# Unmount logging.
# Empty unmount log is not saved to a log file nor emailed.
if [[ "$int_LOG"        == "1" \
   && "$str_UNMOUNTLOG" != "" ]]
then
    printf '\n%s\n' '--- UNMOUNT LOG --------------------------'
    printf '%s\n' "$str_UNMOUNTLOG"
    
    if [[ "$int_EMAIL" == "1" ]]
    then
        exit 1
    fi
fi

# Full logging.
if [[ "$int_LOG" == "2" ]]
then
    printf '\n%s\n' '--- FULL LOG -----------------------------'
    printf '%s\n' "$str_FULLLOG"
    
    if [[ "$int_EMAIL" == "1" ]]
    then
        exit 1
    fi
fi
