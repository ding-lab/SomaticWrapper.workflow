#!/bin/bash

# author: Matthew Wyczalkowski m.wyczalkowski@wustl.edu

# Usage: start_step.sh [options] UUID [UUID2 ...]
# Start processing given step.  Run on host computer
# options:
# -d: dry run.  This may be repeated (e.g., -dd or -d -d) to pass the -d argument to called functions instead, 
#     with each called function called in dry run mode if it gets one -d, and popping off one and passing rest otherwise
# -g LSF_GROUP: LSF group to use starting job
# -S SR_FILE: path to SR data file.  Default: config/SR.dat
# -O DATA_DIR: path to base of download directory (will write to $DATA_DIR/GDC_import). Default: ./data
# -s STEP: Step to process.  Default (and only available value) is 'import'
# -t TOKEN: token filename, path relative to container.  Default: /data/token/gdc-user-token.txt
# -D: Download only, do not index
# -I: Index only, do not Download.  DT must be "BAM"
# -M: MGI environment
# -B: Run BASH in Docker instead of gdc-client
# -f: force overwrite of existing data files
#
# If UUID is - then read UUID from STDIN
# 
# Path to importGDC directory is defined by environment variable IMPORTGDC_HOME.  Default
# is /usr/local/importGDC; can be changed with,
#```
#    export IMPORTGDC_HOME="/path/to/importGDC"
#```

# If environment variable not defined, set it for the duration of this script to the path below
if [ -z $IMPORTGDC_HOME ]; then
    IMPORTGDC_HOME="/usr/local/importGDC"
fi


function launch_import {
UUID=$1

NMATCH=$(grep $UUID $SR | wc -l)
if [ $NMATCH -ne "1" ]; then
    >&2 echo ERROR: UUID $UUID  matches $NMATCH lines in $SR \(expecting unique match\)
    exit 1;
fi

FN=$(grep $UUID $SR | cut -f 6)
DF=$(grep $UUID $SR | cut -f 8)


if [ -z "$FN" ]; then
    >&2 echo Error: UUID $UUID not found in $SR
    exit 1
fi

# If DRYRUN is 'd' then we're in dry run mode (only print the called function),
# otherwise call the function as normal with one less -d argument than we got
if [ -z $DRYRUN ]; then   # DRYRUN not set
    BASH="/bin/bash"
elif [ $DRYRUN == "d" ]; then  # DRYRUN is -d: echo the command rather than executing it
    BASH="echo /bin/bash"
    echo "Dry run in $0" >&2
else    # DRYRUN has multiple d's: strip one d off the argument and pass it to function
    BASH="/bin/bash"
    DRYRUN=${DRYRUN%?}
    XARGS="$XARGS -$DRYRUN"
fi

$BASH $IMPORTGDC_HOME/GDC_import.sh $XARGS -t $TOKEN -O $DATA_DIR -p $DF -n $FN  $UUID

}

# Default values
SR="config/SR.dat"
DATA_DIR="./data"
STEP="import"
TOKEN="/data/token/gdc-user-token.txt"

while getopts ":dg:S:O:s:t:IDMBf" opt; do
  case $opt in
    d)  # -d is a stack of parameters, each script popping one off until get to -d
      DRYRUN="d$DRYRUN"
      ;;
    B) # define LSF_GROUP
      XARGS="$XARGS -B"
      ;;
    g) # define LSF_GROUP
      XARGS="$XARGS -g $OPTARG"
      ;;
    S) 
      SR=$OPTARG
      echo "SR File: $SR" >&2
      ;;
    t) 
      TOKEN=$OPTARG
      echo "Token File: $TOKEN" >&2
      ;;
    O) # set DATA_DIR
      DATA_DIR="$OPTARG"
      echo "Data Dir: $DATA_DIR" >&2
      ;;
    s) 
      STEP="$OPTARG"
      ;;
    I)  
      XARGS="$XARGS -I"
      ;;
    D)  
      XARGS="$XARGS -D"
      ;;
    M)  
      XARGS="$XARGS -M"
      ;;
    f)  
      XARGS="$XARGS -f"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z $SR ]; then
    >&2 echo Error: SR file not defined \(-S\)
    exit 1
fi
if [ ! -e $SR ]; then
    >&2 echo "Error: $SR does not exist"
    exit 1
fi

if [ "$#" -lt 1 ]; then
    >&2 echo Error: Wrong number of arguments
    >&2 echo Usage: start_step.sh [options] UUID [UUID2 ...]
    exit 1
fi

# this allows us to get UUIDs in one of two ways:
# 1: start_step.sh ... UUID1 UUID2 UUID3
# 2: cat UUIDS.dat | start_step.sh ... -
if [ $1 == "-" ]; then
    UUIDS=$(cat - )
else
    UUIDS="$@"
fi

# Loop over all remaining arguments
for UUID in $UUIDS
do

    if [ $STEP == 'import' ]; then
        launch_import $UUID
    else
        echo Unknown step $STEP
        echo Only 'import' implemented
    fi

done
