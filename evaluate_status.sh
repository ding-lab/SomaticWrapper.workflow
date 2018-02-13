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
# -g: debug mode.  print debug statements of logic tests
# -1: quit after one.
# -e: Summarize sample status, returning one of the following for each:
    # "runs ready to start"
    # "runs incomplete"
    # "runs had error"
    # "parsing incomplete"
    # "parsing ready to start"
    # "merge ready to start"
    # "merge incomplete"
    # "workflow complete"
    # "error"  # not used


# Look at importGDC/batch.import/evaluate_status.sh
# for example of implementation on DC2

# Its not clear how to test completion of a program in a general way, and to test if it exited with an error status
# For now, we'll grep for "Successfully completed." in the .out file of the submitted job
# This will probably not catch jobs which exit early for some reason (memory, etc), and is LSF specific

function debug {
    if [ $DEBUG ]; then
        >&2 echo DEBUG: "$@"
    fi
}

# pass filename of log file, "completed" if finished successfully, "running" if not, and "unknown" if associated 
# log file does not exist
function test_LSF_success {
# BRCA77
LOG=$1

if [ ! -e $LOG ]; then
    debug $LOG does not seem to exist
    echo unknown
    return
fi

ERROR="Exited with exit code"
if grep -Fq "$ERROR" $LOG; then
    debug $LOG : $ERROR
    echo error
    return
fi

SUCCESS="Successfully completed."
if grep -Fxq "$SUCCESS" $LOG; then
    debug $LOG : $SUCCESS
    echo completed
else
    debug $LOG : NOT $SUCCESS
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
    debug $STRERR does not seem to exist
    echo unknown
    return
fi

if grep -Fq "ERROR" $STRERR; then
    debug $STRERR has ERROR
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

# Usage: get_status LINE STEP
# Where LINE is a single line from configuration file and STEP is the step name (e.g. 'run_varscan')
# We do not assume an order for the columns
function get_status {
LINE=$1
STEP=$2

S=$(echo $LINE | awk -v step=$STEP '{ for(i = 1; i <= NF; i++) { if ($i ~ step) print $i; } }' )

if [ -z $S ]; then
>&2 echo Error: $STEP not found in $LINE
>&2 echo Exiting
exit
fi

echo $S | cut -f 2 -d :
}


function evaluate_start {
SAMPLE_NAME=$1
LINE=$2

RUN_VARSCAN=$(get_status "$LINE" "run_varscan")
RUN_PINDEL=$(get_status "$LINE" "run_pindel")
RUN_STRELKA=$(get_status "$LINE" "run_strelka")

PARSE_VARSCAN=$(get_status "$LINE" "parse_varscan")
PARSE_PINDEL=$(get_status "$LINE" "parse_pindel")
PARSE_STRELKA=$(get_status "$LINE" "parse_strelka")

MERGE_VCF=$(get_status "$LINE" "merge_vcf")

RUN_VEP=$(get_status "$LINE" "run_vep")

# the logic here is empirical.  There can be a lot of various error conditions which aren't being caught

# Runs are ready to start if status for all of them is 'unknown'
RUNS_READY=0
if [[ $RUN_VARSCAN == 'unknown' && $RUN_STRELKA == 'unknown' && $RUN_PINDEL == 'unknown' ]]; then
RUNS_READY=1
fi

# any run errors 
RUNS_HAD_ERROR=0
if [[ $RUN_VARSCAN == "error"* || $RUN_STRELKA == "error"* || $RUN_PINDEL == "error"* ]]; then
RUNS_HAD_ERROR=1
fi

# Runs are complete if all of them are completed
RUNS_COMPLETE=0
if [ $RUN_VARSCAN == 'completed' ] && [ $RUN_STRELKA == 'completed' ] && [ $RUN_PINDEL == 'completed' ]; then
RUNS_COMPLETE=1
fi

# Parsing  ready to start if status for all of them is 'unknown'
PARSE_READY=0
if [ $PARSE_VARSCAN == 'unknown' ] && [ $PARSE_STRELKA == 'unknown' ] && [ $PARSE_PINDEL == 'unknown' ]; then
PARSE_READY=1
fi

# Parsing is complete if status for all of them is 'completed'
PARSE_COMPLETE=0
if [ $PARSE_VARSCAN == 'completed' ] && [ $PARSE_STRELKA == 'completed' ] && [ $PARSE_PINDEL == 'completed' ]; then
PARSE_COMPLETE=1
fi

# Merge ready if status is 'unknown'
MERGE_READY=0
if [ $MERGE_VCF == 'unknown' ]; then
MERGE_READY=1
fi

# Merge complete if status is 'completed'
MERGE_COMPLETE=0
if [ $MERGE_VCF == 'completed' ]; then
MERGE_COMPLETE=1
fi

# VEP ready if status is 'completed'
VEP_READY=0
if [ $RUN_VEP == 'unknown' ]; then
VEP_READY=1
fi

# VEP complete if status is 'completed'
VEP_COMPLETE=0
if [ $RUN_VEP == 'completed' ]; then
VEP_COMPLETE=1
fi

if [ $RUNS_HAD_ERROR -eq 1 ]; then
    SS="runs_had_error"
elif [ $RUNS_READY -eq 1 ]; then
    SS="runs_ready_to_start"
elif [ ! $RUNS_READY -eq 1 ] && [ ! $RUNS_COMPLETE -eq 1 ]; then
    SS="runs_incomplete"
elif [ $RUNS_COMPLETE -eq 1 ] && [ $PARSE_READY -eq 1 ]; then
    SS="parsing_ready_to_start"
elif [ ! $PARSE_READY -eq 1 ] && [ ! $PARSE_COMPLETE -eq 1 ]; then
    SS="parsing_incomplete"
elif [ $PARSE_COMPLETE -eq 1 ] && [ $MERGE_READY -eq 1 ]; then
    SS="merge_ready_to_start"
elif [ ! $MERGE_READY -eq 1 ] && [ ! $MERGE_COMPLETE -eq 1 ]; then
    SS="merge_incomplete"
elif [ $MERGE_COMPLETE -eq 1 ] && [ $VEP_READY -eq 1 ]; then
    SS="vep_ready_to_start"
elif [ $VEP_COMPLETE -eq 1 ]; then
    SS="workflow_complete"
else
    SS="error"
fi

printf "$SAMPLE_NAME\t$SS\n"

}

# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts ":uf:D:S:g1e" opt; do
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
    g)  
      DEBUG=1
      ;;
    e)  
      SUMMARY=1
      ;;
    1)  
      QAO=1 # quot after one
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

if [ ! -e $DATD ]; then
    >&2 echo "Error: Data directory does not exist: $DATD"
    exit 1
fi

while read L; do
    # Skip comments and header
    [[ $P = \#* ]] && continue

    SN=$(echo "$L" | cut -f 2)   # sample name

    STATUS=$(get_job_status $SN )
    # Example Status line:
    # C3N-00734.WXS run_strelka:unknown run_varscan:unknown run_pindel:unknown  parse_strelka:unknown   parse_varscan:unknown   parse_pindel:unknown    merge_vcf:unknownrun_vep:unknown

    debug $STATUS 
    if [ $SUMMARY ]; then
        SUMMARY_STATUS=$(evaluate_start $SN "$STATUS")
        debug $SUMMARY_STATUS
        STATUS=$SUMMARY_STATUS
    fi

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

    if [ ! -z $QAO ]; then
        exit 
    fi

done <$BATCH

