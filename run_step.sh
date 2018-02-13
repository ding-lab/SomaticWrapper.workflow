#!/bin/bash
# author: Matthew Wyczalkowski m.wyczalkowski@wustl.edu

# Usage: start_step.sh [options] SN [SN2 ...]
#
# Start processing sample name(s) step.  Run on host computer

# Key Directories, [H] and [C] indicate whether paths relative to host machine or container
# * DATAD - mount point of container's /data on host machine [H]
# * SWW_HOME - path to SomaticWrapper.workflow [H]
# * SW_HOME_C - path to somaticwrapper core relative to container
# * SCRIPTD - location of LSF logs and launch scripts [H]
# * CONFIGD - location of config files, visible from container [C]
# * SWDATA - base directory of SomaticWrapper data output [C].  This is passed via configuation file
#
# The above are set with the following arguments
# -D DATAD: path to base of data directory, which maps to /data in container. Required
# -s SCRIPTD: Logs and scripts will be written to $SCRIPTD/logs and /launch, respectively.  Required
# -p SWW_HOME: Must be set with -p or SWW_HOME environment variable.
# -w SW_HOME_C: default [/usr/local/somaticwrapper]
# -c CONFIGD: default [/data/config].  Configuration file is $CONFIGD/$SN.config
#
# Other arguments
# -S: step.  Must be one of "run", "parse", "merge", "vep", or a step number \(e.g. "1"\).  Required
# -d: dry run.  This may be repeated (e.g., -dd or -d -d) to pass the -d argument to called functions instead, 
#     with each called function called in dry run mode if it gets one -d, and popping off one and passing rest otherwise
# -g LSF_GROUP: LSF group to use starting job
# -M: MGI environment.  Non-MGI environment currently not implemented
# -h DOCKERHOST - define a LSF host to execute the image.  MGI only
# -B: Run BASH in Docker instead of gdc-client
# -m mGb: requested memory in Gb (requires numeric step, e.g. '1')
#
# If argument SN is - then read SN from STDIN


function submit-MGI {
SN=$1
mSTEP=$2
LSFMEM=$3  # Mem request in Gb, may be empty

ARGS=$XARGS  # XARGS is a global, don't want to modify it here

>&2 echo Starting step $mSTEP for $SN 

# If DRYRUN is 'd' then we're in dry run mode (only print the called function),
# otherwise call the function as normal with one less -d argument than we got
if [ -z $DRYRUN ]; then   # DRYRUN not set
    BASH="/bin/bash"
elif [ $DRYRUN == "d" ]; then  # DRYRUN is -d: echo the command rather than executing it
    BASH="echo /bin/bash"
    >&2 echo "Dry run in $0"
else    # DRYRUN has multiple d's: strip one d off the argument and pass it to function
    BASH="/bin/bash"
    DRYRUN=${DRYRUN%?}
    ARGS="$ARGS -$DRYRUN"
fi

ARGS="$ARGS -D $DATAD -s $SCRIPTD -c $CONFIGD"
if [ ! -z $LSFMEM ]; then
    ARGS="$ARGS -m $LSFMEM"
fi

$BASH $SWW_HOME/src/submit-MGI.sh $ARGS $SN $mSTEP 
}

function launch_run {
    mSN=$1
    submit-MGI $mSN 1 # run_strelka
    submit-MGI $mSN 2 # run_varscan
    submit-MGI $mSN 5 32 # run_pindel  - run with 30 Gb of memory
}

function launch_parse {
    mSN=$1
    submit-MGI $mSN 3 # parse_strelka
    submit-MGI $mSN 4 # parse_varscan
    submit-MGI $mSN 7 # parse_pindel  
}

function launch_merge {
    mSN=$1
    submit-MGI $mSN 8 # merge_vcf
}

# from BRCA77
function launch_step {
    mSN=$1
    STEP=$2
    submit-MGI $mSN $STEP $MEMGB
}

CONFIGD="/data/config"

while getopts ":D:s:p:c:S:dg:MBm:w:h:" opt; do
  case $opt in
    D) # set DATAD
      DATAD="$OPTARG"
      >&2 echo "Data Dir: $DATAD"
      ;;
    s)  
      SCRIPTD="$OPTARG"
      >&2 echo "Log/script dir: $SCRIPTD" 
      ;;
    p)  
      SWW_HOME="$OPTARG"
      >&2 echo "SomaticWrapper.workflow dir: $SWW_HOME" 
      ;;
    c)
      CONFIGD="$OPTARG"
      >&2 echo "Configuration dir: $CONFIGD" 
      ;;
    S) 
      STEP="$OPTARG"
      ;;
    d)  # -d is a stack of parameters, each script popping one off until get to -d
      DRYRUN="d$DRYRUN"
      ;;
    g) # define LSF_GROUP
      XARGS="$XARGS -g $OPTARG"
      ;;
    M)  
      MGI=1
      ;;
    B) # run BASH
      XARGS="$XARGS -B"
      ;;
    m)
      MEMGB="$OPTARG"
      >&2 echo "Setting memory $MEMGB Gb"
      ;;
    w)  # SW_HOME_C
      XARGS="$XARGS -w $OPTARG"
      ;;
    h)  # DOCKERHOST
      XARGS="$XARGS -h $OPTARG"
      ;;
    \?)
      >&2 echo "Invalid option: -$OPTARG"
      exit 1
      ;;
    :)
      >&2 echo "Option -$OPTARG requires an argument."
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

if [ "$#" -lt 1 ]; then
    >&2 echo Error: Wrong number of arguments
    >&2 echo Usage: start_step.sh [options] SN [SN2 ...]
    exit 1
fi

if [ -z $DATAD ]; then
    >&2 echo Error: Data directory not defined \[-D DATAD\]
    exit 1
fi

if [ -z $CONFIGD ]; then
    >&2 echo Error: configuration directory not defined \[-c CONFIGD\]
    exit 1
fi

if [ -z $SWW_HOME ]; then
    >&2 echo Error: SomaticWrapper.workflow not defined: either -p SWW_HOME or set env var with \`export SWW_HOME=/path/to/SWW\' 
    exit 1
fi

if [ -z $SCRIPTD ]; then
    >&2 echo Error: Logs and scripts base dir not defined \[-s SCRIPTD\]
    exit 1
fi

if [ -z $STEP ]; then
    >&2 echo Error: Step not defined \[-S STEP\]
    exit 1
fi

# this allows us to get SNs in one of two ways:
# 1: start_step.sh ... SN1 SN2 SN3
# 2: cat SNs.dat | start_step.sh ... -
if [ $1 == "-" ]; then
    SNS=$(cat - )
else
    SNS="$@"
fi

# Loop over all remaining arguments
for SN in $SNS
do
   if [ $STEP == 'run' ]; then
       launch_run $SN
   elif [ $STEP == 'parse' ]; then
       launch_parse $SN
   elif [ $STEP == 'merge' ]; then
       launch_merge $SN
   elif [ $STEP == 'vep' ]; then
       launch_step $SN '10'
   elif [[ $STEP == '1' || $STEP == '2' || $STEP == '3' || $STEP == '4' || $STEP == '5' || $STEP == '7' || $STEP == '8' || $STEP == '10' ]]; then
       launch_step $SN $STEP 
   else 
       >&2 echo Unknown step $STEP
       >&2 echo Must be one of "run", "parse", "merge", "vep", or a step number \(e.g. "1"\)
   fi
done
