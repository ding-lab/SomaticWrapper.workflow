# Launch docker instance to import and index GDC data
# Usage: GDC_import.sh [options] UUID [UUID2 ...]
#
# -M: run in MGI environment
# -O: output directory on localhost.  Mandatory
# -t: token file path in container.  Mandatory
# -n: filename associated with UUID.  Mandatory
# -p: dataformat (BAM or FASTQ).  Mandatory
# -d: dry run - print out docker statement but do not execute (for debugging)
#     This may be repeated (e.g., -dd or -d -d) to pass the -d argument to called functions instead, 
#     with each called function called in dry run mode if it gets one -d, and popping off one and passing rest otherwise
# -B: run bash instead of process_GDC_uuid.sh
# -D: Download only, do not index
# -I: Index only, do not Download.  DT must be "BAM"
# -g LSF_GROUP: LSF group to start in.  MGI mode only
# -f: force overwrite of existing data files

# This is run from the host computer.  
# Executes script image.init/process_GDC_uuid.sh from within docker container

DOCKER_IMAGE="mwyczalkowski/importgdc"
PROCESS="/usr/local/importGDC/image.init/process_GDC_uuid.sh"

# start process_GDC_uuid.sh in vanilla docker environment
function processUUID {
UUID=$1
OUTD=$2
TOKEN=$3
FN=$4
DF=$5

# This starts mwyczalkowski/importgdc and maps directories:
# Container: /data
# Host: $OUTD

if [ $RUNBASH ]; then
>&2 echo RUNBASH not implemented for non-MGI docker
exit 1
fi


# If DRYRUN is 'd' then we're in dry run mode (only print the called function),
# otherwise call the function as normal with one less -d argument than we got
if [ -z $DRYRUN ]; then   # DRYRUN not set
    DOCKER="docker"
elif [ $DRYRUN == "d" ]; then  # DRYRUN is -d: echo the command rather than executing it
    DOCKER="echo docker"
    >&2 echo Dry run in $0
else    # DRYRUN has multiple d's: pop one d off the argument and pass it to function
    DOCKER="docker"
    DRYRUN=${DRYRUN%?}
    XARGS="$XARGS -$DRYRUN"
fi

# This is the command that will execute on docker
CMD="/bin/bash $PROCESS $XARGS $UUID $TOKEN $FN $DF"

#$DOCKER run -v $OUTD:/data -it $DOCKER_IMAGE $CMD >&2
$DOCKER run -v $OUTD:/data $DOCKER_IMAGE $CMD >&2

}

# start docker in MGI environment
function processUUID_MGI {
UUID=$1
OUTD=$2
TOKEN=$3
FN=$4
DF=$5

# logs will be written to $SCRIPTD/bsub_run-step_$STEP.err, .out
LOGD="bsub-logs"
mkdir -p $LOGD
ERRLOG="$LOGD/$UUID.err"
OUTLOG="$LOGD/$UUID.out"
LOGS="-e $ERRLOG -o $OUTLOG"
rm -f $ERRLOG $OUTLOG
echo Writing bsub logs to $OUTLOG and $ERRLOG

BSUB="bsub"

if [ -z $DRYRUN ]; then   # DRYRUN not set
    : # do nothing
elif [ $DRYRUN == "d" ]; then  # DRYRUN is -d: echo the command rather than executing it
    BSUB="echo $BSUB"
    >&2 echo Dry run $0
else    # DRYRUN has multiple d's: pop one d off the argument and pass it to function
    DRYRUN=${DRYRUN%?}
    XARGS="$XARGS -$DRYRUN"
fi

# Where container's /data is mounted on host
echo Mapping /data to $OUTD
export LSF_DOCKER_VOLUMES="$OUTD:/data"

# for testing, so that it goes faster, do this on blade18-2-11.gsc.wustl.edu
#DOCKERHOST="-m blade18-2-11.gsc.wustl.edu"

if [ -z $RUNBASH ]; then

    PROCESS="$IMPORTGDC_HOME/image.init/process_GDC_uuid.sh"

    CMD="/bin/bash $PROCESS $XARGS $UUID $TOKEN $FN $DF"
    $BSUB -q research-hpc $DOCKERHOST $LSF_ARGS $LOGS -a "docker($DOCKER_IMAGE)" "$CMD"
else
    $BSUB -q research-hpc $DOCKERHOST $LSF_ARGS -Is -a "docker($DOCKER_IMAGE)" "/bin/bash"
fi
}

XARGS=""
LSF_ARGS=""
# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts ":Mt:O:p:n:dBIDg:f" opt; do
  case $opt in
    M)  # example of binary argument
      MGI=1
      >&2 echo MGI Mode
      ;;
    t)
      TOKEN=$OPTARG
      >&2 echo Token file: $TOKEN
      ;;
    O)  # Note, this used to be O
      OUTD=$OPTARG
      >&2 echo Host data dir: $OUTD
      ;;
    p)
      DF=$OPTARG
      >&2 echo Data Format: $DF
      ;;
    n)
      FN=$OPTARG
      >&2 echo Filename: $FN
      ;;
    d) 
      DRYRUN="d$DRYRUN" # -d is a stack of parameters, each script popping one off until get to -d
      ;;
    B)  
      RUNBASH=1
      >&2 echo Run bash
      ;;
    I)  
      XARGS="$XARGS -I"
      ;;
    D)  
      XARGS="$XARGS -D"
      ;;
    f)  
      XARGS="$XARGS -f"
      ;;
    g)  
      LSF_ARGS="$LSF_ARGS -g $OPTARG"
      >&2 echo LSF Group: $OPTARG
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

if [ -z $TOKEN ]; then
    >&2 echo Error: token not defined \[-t\]
    exit 1
fi
if [ -z $OUTD ]; then
    >&2 echo Error: output directory not defined \[-o\]
    exit 1
fi

for UUID in "$@"
do

if [ $MGI ]; then
processUUID_MGI $UUID $OUTD $TOKEN $FN $DF
else
processUUID $UUID $OUTD $TOKEN $FN $DF
fi

done
