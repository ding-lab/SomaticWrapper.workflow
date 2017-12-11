#!/bin/bash

# author: Matthew Wyczalkowski m.wyczalkowski@wustl.edu

# Evaluate status of all samples in batch file 
# Usage: evaluate_status.sh [options] batch.dat
#
# Output written to STDOUT

# options
# -f status: output only lines matching status, e.g., -f import:complete
# -u: include only UUID in output
# -D: include data file path in output
# -O DATA_DIR: path to base of download directory (data in $DATA_DIR/GDC_import)
#       Default: ./data
# -L LOG_DIR: path to LSF logs. Default: ./bsub-logs
# -M: MGI environment.  Evaluate LSF logs 

LOG_DIR="./bsub-logs"
DATA_DIR="./data"

# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts ":uf:DO:L:" opt; do
  case $opt in
    u)  
      UUID_ONLY=1
      ;;
    D)  
      DATA_PATH=1
      ;;
    M)  
      MGI=1
      ;;
    f) 
      FILTER=$OPTARG
      ;;
    O) # set DATA_DIR
      DATA_DIR="$OPTARG"
      ;;
    L) 
      LOG_DIR="$OPTARG"
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

if [ "$#" -ne 1 ]; then
    >&2 echo Error: Wrong number of arguments
    >&2 echo Usage: update_batch_status.sh \[options\] batch.dat
    exit 1
fi

BATCH=$1

DATD="$DATA_DIR/GDC_import"
if [ ! -e $DATD ]; then
    >&2 echo "Error: Data directory does not exist: $DATD"
    exit 1
fi


# Evaluate download status of gdc-client by examining LSF logs (MGI-specific) and existence of output file
# Returns one of "ready", "running", "complete", "incomplete", "error"
# Usage: test_import_success UUID FN
# where FN is the filename (relative to data directory) as written by gdc-client
function test_import_success {
UUID=$1
FN=$2

LOGERR="$LOG_DIR/$UUID.err"  # this is generally not used
LOGOUT="$LOG_DIR/$UUID.out"
DAT="$DATD/$FN"
DATP="$DATD/$FN.partial"

# flow of gdc-client download and processing
# 1. create output directory and $DAT.partial file as it is being downloaded
# 2. index file (if it is a .bam) to create .bai file
# 3. Create $DAT when it is finished.  Write "Successfully completed." to log.out file
# 4. If dies for some reason, write "Exited with exit code" to log.out file

# Other, tests may be added as necessary

# If neither DAT or DATP created, assume download did not start and status is ready
if [ ! -e $DAT ] && [ ! -e $DATP ] ; then
    echo ready
    return
fi

# Handle the case where LOGOUT does not exist - this might happen during some error conditions.
# We won't know if running or error, but might establish complete or incomplete
if [ $MGI ]; then 
    if [ ! -e $LOGOUT ]; then
        >&2 echo WARNING: Log file $LOGOUT does not exist.  Continuing.
    else
        ERROR="Exited with exit code"
        if fgrep -Fq "$ERROR" $LOGOUT; then
            echo error
            return
        fi

        SUCCESS="Successfully completed."
        if ! fgrep -Fxq "$SUCCESS" $LOGOUT; then
            echo running
            return
        fi
    fi
fi

# In case of BAM file, test if .bai file exists.  If it does, we are completed.  Otherwise, incomplete
# We are testing for filename extension since we don't have data format information
FNB=$(basename "$FN")
EXT="${FNB##*.}"

if [ $EXT == 'bam' ]; then
    BAI="$DAT.bai"
    if [ -e $BAI ]; then
        echo complete
    else
        echo incomplete
    fi
else
# If not BAM file, just test if result file exists
    if [ -e $DAT ]; then
        echo complete
    else
        echo incomplete
    fi
fi



}

function get_job_status {
UUID=$1
SN=$2
FN=$3
# evaluates status of import by checking LSF logs
# Based on /gscuser/mwyczalk/projects/SomaticWrapper/SW_testing/BRCA77/2_get_runs_status.sh

# Its not clear how to test completion of a program in a general way, and to test if it exited with an error status
# For now, we'll grep for "Successfully completed." in the .out file of the submitted job
# This will probably not catch jobs which exit early for some reason (memory, etc), and is LSF specific


TEST1=$(test_import_success $UUID $FN)  

# for multi-step processing would report back a test for each step
printf "$UUID\t$SN\t$DATD/$FN\timport:$TEST1\n"
}

while read L; do
    # Skip comments and header
    [[ $P = \#* ]] && continue

    UUID=$(echo "$L" | cut -f 1) # unique ID of file
    SN=$(echo "$L" | cut -f 2)   # sample name
    FN=$(echo "$L" | cut -f 3)   # filename

    STATUS=$(get_job_status $UUID $SN $FN )

    # which columns to output?
    if [ ! -z $UUID_ONLY ]; then
        COLS="1"
    elif [ ! -z $DATA_PATH ]; then        
        COLS="1-4" 
    else 
        COLS="1,2,4" 
    fi

    if [ ! -z $FILTER ]; then
        echo "$STATUS" | grep $FILTER | cut -f $COLS
    else 
        echo "$STATUS" | cut -f $COLS
    fi

done <$BATCH

