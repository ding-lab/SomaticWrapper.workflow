#!/bin/bash

# author: Matthew Wyczalkowski m.wyczalkowski@wustl.edu

# Evaluate status of all samples in batch file 
# Usage: evaluate_status.sh [options] batch.dat
#
# Output written to STDOUT

# options
# -f status: output only lines matching status, e.g., -f run_pindel:complete
# -u: include only SN in output
# -D DATAD: path to base of SomaticWrapper analysis directory.  Required
# -S SCRIPTD: path to LSF logs. Required
# -M: MGI environment.  Evaluate LSF logs 


# Look at importGDC/batch.import/evaluate_status.sh
# for example of implementation on DC2

# Its not clear how to test completion of a program in a general way, and to test if it exited with an error status
# For now, we'll grep for "Successfully completed." in the .out file of the submitted job
# This will probably not catch jobs which exit early for some reason (memory, etc), and is LSF specific

# pass filename of log file, "completed" if finished successfully, "running" if not, and "unknown" if associated 
# log file does not exist
function test_LSF_success {
# BRCA77
LOG=$1

if [ ! -e $LOG ]; then
#>&2 echo Warning: $LOG does not seem to exist
echo unknown
return
fi

ERROR="Exited with exit code"
if grep -Fq "$ERROR" $LOG; then
    echo error
    return
fi

SUCCESS="Successfully completed."
if grep -Fxq "$SUCCESS" $LOG; then
    echo completed
else
    echo running
fi
}

# Usage: pass strelka bsub stderr, stdout log files
# Return completed, running, error, or unknown
function test_strelka_success {
# BRCA77
STROUT=$1
STRERR=$2

if [ ! -e $STRERR ]; then  # Error log does not exist
#>&2 echo Warning: $F does not seem to exist
echo unknown
return
fi

if grep -Fq "ERROR" $STRERR; then
    echo error
    return
fi

test_LSF_success $STROUT

}

# Usage: pass pindel bsub stderr, stdout log files
# Return completed, running, error, or unknown
function test_pindel_success {
# BRCA77
STROUT=$1
STRERR=$2

# Note we are adding ad hoc tests to check for specific error conditions

if [ ! -e $STRERR ]; then  # Error log does not exist
#>&2 echo Warning: $F does not seem to exist
echo unknown
return
fi

if grep -Fq "disk quota exceeded" $STRERR; then
    echo error.disk_quota
    return
fi

if grep -Fq "Killed" $STRERR; then
    echo error.killed
    return
fi

test_LSF_success $STROUT

}

# TODO: put together a function to test if the merged vcf was written
function test_merge_success {
# BRCA77
STROUT=$1
STRERR=$2

test_LSF_success $STROUT

}

# It is possible to devise other test for success/failure based on output in data directory
# For instance, if Pindel LSF indicates success but data files not generated, that implies an error

function get_job_status {
# BRCA77
SN=$1
# evaluates status of varscan, pindel, strelka runs by checking LSF logs

# Its not clear how to test completion of a program in a general way, and to test if it exited with an error status
# For now, we'll grep for "Successfully completed." in the .out file of the submitted job
# This will probably not catch jobs which exit early for some reason (memory, etc), and is LSF specific

LOGD="$SCRIPTD/logs" 

#ERRLOG="$LOGD/$SN.STEP-${STEP}.err"
#OUTLOG="$LOGD/$SN.STEP-${STEP}.out"


TEST1=$(test_strelka_success $LOGD/${SN}.STEP-1.out $LOGD/${SN}.STEP-1.err)  # run_strelka
TEST2=$(test_LSF_success $LOGD/${SN}.STEP-2.out)  # run_varscan
TEST5=$(test_pindel_success $LOGD/${SN}.STEP-5.out $LOGD/${SN}.STEP-5.err)  # run_pindel

TEST3=$(test_LSF_success $LOGD/${SN}.STEP-3.out)  # parse_strelka
TEST4=$(test_LSF_success $LOGD/${SN}.STEP-4.out)  # parse_varscan
TEST7=$(test_LSF_success $LOGD/${SN}.STEP-7.out)  # parse_pindel

TEST8=$(test_merge_success $LOGD/${SN}.STEP-8.out)  # merge_vcf

TEST10=$(test_LSF_success $LOGD/${SN}.STEP-10.out)  # run_vep

printf "$SN\trun_strelka:$TEST1\trun_varscan:$TEST2\trun_pindel:$TEST5\tparse_strelka:$TEST3\tparse_varscan:$TEST4\tparse_pindel:$TEST7\tmerge_vcf:$TEST8\trun_vep:$TEST10\n"
}

# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts ":uf:D:S:" opt; do
  case $opt in
    u)  
      SN_ONLY=1
      ;;
    M)  
      MGI=1
      ;;
    f) 
      FILTER=$OPTARG
      ;;
    D) # set DATA_DIR
      DATAD="$OPTARG"
      ;;
    S) 
      SCRIPTD="$OPTARG"
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
    >&2 echo Usage: evaluate_status.sh \[options\] batch.dat
    exit 1
fi

BATCH=$1

DATD="$DATA_DIR/GDC_import"
if [ ! -e $DATD ]; then
    >&2 echo "Error: Data directory does not exist: $DATD"
    exit 1
fi

while read L; do
    # Skip comments and header
    [[ $P = \#* ]] && continue

    SN=$(echo "$L" | cut -f 1)   # sample name

    STATUS=$(get_job_status $SN )

    # which columns to output?
    if [ ! -z $SN_ONLY ]; then
        COLS="1"
    else 
        COLS="1-" 
    fi

    if [ ! -z $FILTER ]; then
        echo "$STATUS" | grep $FILTER | cut -f $COLS
    else 
        echo "$STATUS" | cut -f $COLS
    fi

    exit

done <$BATCH

