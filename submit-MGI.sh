#!/bin/bash

# run a given SomaticWrapper step (or set of steps) via LSF scheduler on MGI
# Usage: submit-MGI.sh [options] SN STEP 
#   SN is SampleName, unique identifier of this run
#   STEP is the step number in SomaticWrapper.pl.  Names (e.g., "parse_pindel") can also be used (untested)

# Options:
# -D DATAD_H - path to container's /data mounted on host.  Required.  
# -T IMPORTD_H - path to container's /import mounted on host.  Required.  
# -I IMAGED_H - path to container's /image mounted on host.  Required.  
# -s SCRIPTD_H - Script run base directory, where bsub output and scripts will be written.  Required.  Path relative to host
# -c CONFIGD_C - configuration file direcotry; config file is $CONFIGD_C/$SN.config.  Default [/data/config]
#   (content of such files described in SomaticWrapper.pl).  
# -w SW_HOME_C - path to SomaticWrapper in container.  Default [/usr/local/somaticwrapper]
# -m MEMGb - integer indicating number of gigabytes to allocate.  Default value (set by MGI) is possibly 8
# -h DOCKERHOST - define a host to execute the image
# -d: dry run - print out run command but do not execute (for debugging)
#     This may be repeated (e.g., -dd or -d -d) to pass the -d argument to called functions instead,
#     with each called function called in dry run mode if it gets one -d, and popping off one and passing rest otherwise
# -g LSF_GROUP: LSF group to start in.  MGI-specific
# -B: run bash instead of starting SomaticWrapper

# Writes LSF logs to $SCRIPTD/logs
# Writes container run scripts to $SCRIPTD/launch/

if [ "$#" -lt 2 ]
then
    >&2 echo "Error - invalid number of arguments"
    >&2 echo "Usage: $0 [options] STEP CONFIG_C "
    exit 1
fi

DOCKER_IMAGE="mwyczalkowski/somatic-wrapper:mgi"

# Old defaults.  now all of these required to be passed
# Where container's /data is mounted on host
#DATAD_H="/gscmnt/gc2521/dinglab/mwyczalk/somatic-wrapper-data"
#SW_HOME_C="/gscuser/mwyczalk/projects/SomaticWrapper/somaticwrapper"
#SCRIPTD_BASE="/gscuser/mwyczalk/projects/SomaticWrapper/runtime_bsub"

# SW_HOME_C is path relative to container to SomaticWrapper project.
# We SomaticWrapper is installed in image at /usr/local/SomaticWrapper
# This default can be overridden with -w to use some other copy
SW_HOME_C="/usr/local/somaticwrapper"

LSF_ARGS=""

# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts "D:s:c:w:m:h:dg:BT:I:" opt; do
  case $opt in
    D)
      DATAD_H=$OPTARG
      ;;
    T)
      IMPORTD_H=$OPTARG
      ;;
    I)
      IMAGED_H=$OPTARG
      ;;
    s)
      SCRIPTD_H=$OPTARG
      >&2 echo "Setting script directory $SCRIPTD_H" 
      ;;
    c)
      CONFIGD_C=$OPTARG
      >&2 echo "Setting config directory $CONFIGD_C" 
      ;;
    w)
      SW_HOME_C=$OPTARG
      >&2 echo "Setting SomaticWrapper directory $SW_HOME_C" 
      ;;
    m)
      MEMGB=$OPTARG  
      >&2 echo "Setting memory $MEMGB Gb" 
      MEM="-R \"rusage[mem=${MEMGB}000]\" -M ${MEMGB}000000"
      LSF_ARGS="$LSF_ARGS $MEM"
      ;;
    h)
    # User may define a specific host to avoid downloading image each run
    # This option will be undefined if not set here
      LSF_ARGS="$LSF_ARGS -m $OPTARG"
      >&2 echo "Setting host $OPTARG" 
      ;;
    d)  # -d is a stack of parameters, each script popping one off until get to -d
      DRYRUN="d$DRYRUN"  # Here, add a 'd' to DRYRUN stack every time it is seen ("-dd" behaves same as "-d -d")
      ;;
    g)
      LSF_ARGS="$LSF_ARGS -g $OPTARG"
      >&2 echo LSF Group: $OPTARG
      ;;
    B)
      RUNBASH=1
      >&2 echo Run bash
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

if [ -z $DATAD_H ]; then
    >&2 echo Data directory not defined \(-D DATAD_H\)
    exit 1
fi
if [ -z $SCRIPTD_H ]; then
    >&2 echo Script directory not defined \(-s SCRIPTD_H\)
    exit 1
fi
if [ -z $IMPORTD_H ]; then
    >&2 echo /import directory not defined \(-M IMPORTD_H\)
    exit 1
fi
if [ -z $IMAGED_H ]; then
    >&2 echo /image directory not defined \(-I IMAGED_H\)
    exit 1
fi

shift $((OPTIND-1))

SN=$1; shift
STEP=$1; shift

>&2 echo Sample Name $SN, step $STEP

# Config file is assumed to be in CONFIGD_C, filename SN.config
CONFIG_C="$CONFIGD_C/$SN.config"
>&2 echo Using configuration file $CONFIG_C

# MGI allows multiple volumes to be mounted
# https://confluence.gsc.wustl.edu/pages/viewpage.action?pageId=31491896
# There are 3 mount points:
# /data maps to $DATAD_H
# /import maps to $IMPORTD_H
# /image maps to $IMAGED_H
>&2 echo "/data mounts to $DATAD_H "
>&2 echo "/import mounts to $IMPORTD_H "
>&2 echo "/image mounts to $IMAGED_H "
# TODO: confirm this is the correct syntax
export LSF_DOCKER_VOLUMES="$DATAD_H:/data $IMPORTD_H:/import $IMAGED_H:/image"

# Here we're generating a script which will be run in new container to launch a job after sourcing environment variables
LAUNCHD_H="$SCRIPTD_H/launch"; mkdir -p $LAUNCHD_H
LOGD_H="$SCRIPTD_H/logs"; mkdir -p $LOGD_H
>&2 echo bsub run output directory is $LOGD_H

SCRIPT_H="$LAUNCHD_H/$SN.step_$STEP.sh"
>&2 echo Generating run script $SCRIPT_H

# logs will be written to $SCRIPTD_H/bsub_run-step_$STEP.err, .out
ERRLOG="$LOGD_H/$SN.STEP-${STEP}.err"
OUTLOG="$LOGD_H/$SN.STEP-${STEP}.out"
LOGS="-e $ERRLOG -o $OUTLOG"
rm -f $ERRLOG $OUTLOG
>&2 echo Writing bsub logs to $OUTLOG and $ERRLOG

# this script below is icky but for some reason `source /home/sw/.bashrc` does not make
# variables "stick" - echo $PATH returns MGI environment.  Worth investigating more
cat << EOF > $SCRIPT_H
#!/bin/bash

# This is an automatically generated script for executing SomaticWrapper within MGI docker container
# environment variables are generally same as those in /home/sw/.bashrc
export TERM=xterm
export LD_LIBRARY_PATH=/usr/local/htslib
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/home/sw
export PERL5LIB=$SW_HOME_C
export LANG=""
export PYTHONPATH="" 

cd $SW_HOME_C
perl $SW_HOME_C/SomaticWrapper.pl $STEP $CONFIG_C
EOF

# If DRYRUN is 'd' then we're in dry run mode (only print the called function),
# otherwise call the function as normal with one less -d argument than we got
if [ -z $DRYRUN ]; then   # DRYRUN not set
    BSUB="bsub"
elif [ $DRYRUN == "d" ]; then  # DRYRUN is -d: echo the command rather than executing it
    BSUB="echo bsub"
    >&2 echo Dry run in $0
else    # DRYRUN has multiple d's: pop one d off the argument and pass it to function
    BSUB="bsub"
    DRYRUN=${DRYRUN%?}
    XARGS="$XARGS -$DRYRUN"
fi 

# XARGS is a generic way to pass arguments to the run script.  They are not used here, but
# more sophisticated versions of SCRIPT_H may read them.  

if [ -z $RUNBASH ]; then
    CMD="/bin/bash --rcfile /home/sw/.bashrc $SCRIPT_H $XARGS" 
    $BSUB -q research-hpc $LSF_ARGS $LOGS -a "docker ($DOCKER_IMAGE)"  "$CMD"
else
    # Start script simply sources the environment variables to make MGI behave reasonably
    $BSUB -q research-hpc $LSF_ARGS -Is -a "docker($DOCKER_IMAGE)" "/bin/bash --rcfile /home/sw/.bashrc"
    #$BSUB -q research-hpc $LSF_ARGS -Is -a "docker($DOCKER_IMAGE)" "/bin/bash $START"
fi
