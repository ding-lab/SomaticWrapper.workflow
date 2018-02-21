#!/bin/bash
# author: Matthew Wyczalkowski m.wyczalkowski@wustl.edu

# Usage: start_step.sh [options] SN [SN2 ...]
#
# Start processing sample name(s) step.  Run on host computer

# Key Directories, [H] and [C] indicate whether paths relative to host machine or container
# * DATAD_H - mount point of container's /data on host machine [H]
# * IMPORTD_H - mount point of containers /import.  Alternatively, this may be a TSV file (importd.dat) with
#       run name as first column, IMPORTD_H directory mapping in second, to allow for dynamic mapping
# * IMAGED_H - mount point of container's /image [H]
# * SWW_HOME_H - path to SomaticWrapper.workflow [H]
# * SW_HOME_C - path to somaticwrapper core relative to container
# * SCRIPTD_H - location of LSF logs and launch scripts [H]
# * CONFIGD_C - location of config files, visible from container [C]
#
# The above are set with the following arguments
# -D DATAD_H: path to base of data directory, which maps to /data in container. Required
# -T IMPORTD_H - path to container's /import mounted on host.  Required.  
# -I IMAGED_H - path to container's /image mounted on host.  Required.  
# -s SCRIPTD_H: Logs and scripts will be written to $SCRIPTD_H/logs and /launch, respectively.  Required
# -p SWW_HOME_H: Must be set with -p or SWW_HOME_H environment variable.
# -w SW_HOME_C: default [/usr/local/somaticwrapper]
# -c CONFIGD_C: default [/data/config].  Configuration file is $CONFIGD_C/$SN.config
#
# Other arguments
# -S: step.  Must be one of "run", "parse", "merge", "vep", or a step number \(e.g. "1"\).  Required
# -d: dry run.  This may be repeated (e.g., -dd or -d -d) to pass the -d argument to called functions instead, 
#     with each called function called in dry run mode if it gets one -d, and popping off one and passing rest otherwise
# -g LSF_GROUP: LSF group to use starting job
# -M: MGI environment.  
# -h DOCKERHOST - define a LSF host to execute the image.  MGI only
# -B: Run BASH in Docker instead of gdc-client
# -m mGb: requested memory in Gb (requires numeric step, e.g. '1')
# -W: Mount all volumes rw (default is to mount /image and /import as ro (read only))
#
# If argument SN is - then read SN from STDIN

# dual MGI/docker functionality based on /Users/mwyczalk/Data/CPTAC3/importGDC.CPTAC3.b1/importGDC/GDC_import.sh
# function below is analogous to launch_import() in :
#   /Users/mwyczalk/Data/CPTAC3/importGDC.CPTAC3.b1/importGDC/start_step.sh
function submit_step {
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

    ARGS="$ARGS -s $SCRIPTD_H -c $CONFIGD_C -T $IMPORTD_H"
    if [ ! -z $LSFMEM ]; then
        ARGS="$ARGS -m $LSFMEM"
    fi

    $BASH $SWW_HOME_H/launch_somaticwrapper.sh $ARGS $SN $mSTEP 
}

function launch_run {
    mSN=$1
    submit_step $mSN 1 # run_strelka
    submit_step $mSN 2 # run_varscan
    submit_step $mSN 5 32 # run_pindel  - run with 30 Gb of memory
}

function launch_parse {
    mSN=$1
    submit_step $mSN 3 # parse_strelka
    submit_step $mSN 4 # parse_varscan
    submit_step $mSN 7 # parse_pindel  
}

function launch_merge {
    mSN=$1
    submit_step $mSN 8 # merge_vcf
}

# from BRCA77
function launch_step {
    mSN=$1
    STEP=$2
    submit_step $mSN $STEP $MEMGB
}

CONFIGD_C="/data/config"

while getopts ":D:T:I:s:p:c:S:dg:MBm:w:h:W" opt; do
  case $opt in
    D) # set DATAD_H
      XARGS="$XARGS -D $OPTARG"
      ;;
    T)  # IMPORTD_H
      IMPORTD_H="$OPTARG"
      ;;
    I)  # IMAGED_H
      XARGS="$XARGS -I $OPTARG"
      ;;
    s)  
      SCRIPTD_H="$OPTARG"
      >&2 echo "Log/script dir [H]: $SCRIPTD_H" 
      ;;
    p)  
      SWW_HOME_H="$OPTARG"
      >&2 echo "SomaticWrapper.workflow dir [H]: $SWW_HOME_H" 
      ;;
    c)
      CONFIGD_C="$OPTARG"
      >&2 echo "Configuration dir [C]: $CONFIGD_C" 
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
    W)  # MOUNTRW
      XARGS="$XARGS -W"
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

# Confirm that IMPORTD_H is passed.  Then, check to see if it is a file or a directory.
# If its a file, then will need to look up IMPORTD_H for every run
if [ -z $IMPORTD_H ]; then
    >&2 echo Error: Import directory not defined \[-T IMPORTD_H\]
    exit 1
fi

if [ -d $IMPORTD_H ]; then
    >&2 echo /import directly mapped to $IMPORTD_H
elif [ -f $IMPORTD_H ]; then
    >&2 echo /import mapped according to $IMPORTD_H
    IMPORTDAT_H=$IMPORTD_H
else
    >&2 echo Error: -T IMPORTD_H = $IMPORTD_H not found.  Quitting
    exit 1
fi


if [ -z $CONFIGD_C ]; then
    >&2 echo Error: configuration directory not defined \[-c CONFIGD_C\]
    exit 1
fi

if [ -z $SWW_HOME_H ]; then
    >&2 echo Error: SomaticWrapper.workflow not defined: either -p SWW_HOME_H or set env var with \`export SWW_HOME_H=/path/to/SWW\' 
    exit 1
fi

if [ -z $SCRIPTD_H ]; then
    >&2 echo Error: Logs and scripts base dir not defined \[-s SCRIPTD_H\]
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
    # Lookup IMPORTD_H for each SN if necessary
    if [ $IMPORTDAT_H ]; then
        IMPORTD_H=$(grep $SN $IMPORTDAT_H | cut -f 2 )
        >&2 echo Got IMPORTD_H = $IMPORTD_H
        if [ -z $IMPORTD_H ]; then
            >&2 echo Cannot find /import mapping $SN in $IMPORTDAT_H.  Quitting.
            exit 1
        fi        
    fi
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
