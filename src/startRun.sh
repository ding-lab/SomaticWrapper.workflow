# Start various stages (run, parse, merge) for one or more samples

# Usage: startRuns.sh [-m memgb][-d] STAGE SN1 [SN2 ...]

# -m requested memory in Gb when specific step number (e.g., '1', not 'run', 'parse', or 'merge') specified
# -d specifies "dry" run, where commands printed but not executed
# -c config file directory.  ./run_config by default
# STAGE is one of run, parse, merge, or a step number
# will start all sample names SN1, SN2, ...

function launch_run {

CONFIG_FN=$1
SAMPLE_NAME=$2

STEP=1  # run_strelka
echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME $STEP $CONFIG_FN 

STEP=2 # run_varscan
echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME $STEP $CONFIG_FN 

STEP=5 # run_pindel  - run with 30 Gb of memory
echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME -m 32 $STEP $CONFIG_FN 

}

function launch_parse {

CONFIG_FN=$1
SAMPLE_NAME=$2

STEP=3  # parse_strelka
echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME $STEP $CONFIG_FN 

STEP=4 # parse_varscan
echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME $STEP $CONFIG_FN 

STEP=7 # parse_pindel  
echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME $STEP $CONFIG_FN 
}

function launch_merge {

CONFIG_FN=$1
SAMPLE_NAME=$2

STEP=8  # merge_vcf
echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME $STEP $CONFIG_FN 

}

function launch_step {

CONFIG_FN=$1
SAMPLE_NAME=$2
STEP=$3
MEMGB=$4

if [ ! -z $MEMGB ]; then
echo memgb defined
M="-m $MEMGB"
fi

echo Starting step $STEP for $SAMPLE_NAME \($CONFIG_FN\)
$SUBMIT -S $SAMPLE_NAME $M $STEP $CONFIG_FN 

}

CMD="bash"


if [ "$#" -lt 2 ]
then
    echo "Error - invalid number of arguments"
    echo "Usage: $0 STAGE SAMPLE_NAME1 [SAMPLE_NAME2 ...]"
    echo "  where STAGE is one of run, parse, merge, vep"
    exit 1
fi

# Default values.  Note this will never really work because need absolute paths
CONFIGD="./run_config"

# http://wiki.bash-hackers.org/howto/getopts_tutorial
while getopts ":m:dc:" opt; do
  case $opt in
    d)
      echo "Dry run" >&2
      CMD="echo"
      ;;
    m)
      MEMGB="$OPTARG"
      echo "Setting memory $MEMGB Gb" >&2
      ;;
    c)
      CONFIGD="$OPTARG"
      echo "Configuration dir: $CONFIGD" >&2
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

MGI="/gscuser/mwyczalk/projects/SomaticWrapper/somaticwrapper/MGI"
SUBMIT="$CMD $MGI/submit_SomaticWrapper_MGI.sh"

shift $((OPTIND-1))

STAGE=$1; shift

echo Stage $STAGE

# Loop over all remaining arguments
for SAMPLE_NAME in "$@"
do

   CONFIG_FN="$CONFIGD/$SAMPLE_NAME.config"
   if [ $STAGE == 'run' ]; then
       launch_run $CONFIG_FN $SAMPLE_NAME
   elif [ $STAGE == 'parse' ]; then
       launch_parse $CONFIG_FN $SAMPLE_NAME
   elif [ $STAGE == 'merge' ]; then
       launch_merge $CONFIG_FN $SAMPLE_NAME
   elif [ $STAGE == 'vep' ]; then
       launch_step $CONFIG_FN $SAMPLE_NAME '10'
   elif [[ $STAGE == '1' || $STAGE == '2' || $STAGE == '3' || $STAGE == '4' || $STAGE == '5' || $STAGE == '7' || $STAGE == '8' || $STAGE == '10' ]]; then
       launch_step $CONFIG_FN $SAMPLE_NAME $STAGE $MEMGB
   else 
       echo Unknown stage $STAGE
       echo Must be one of "run", "parse", "merge", or a step number \(e.g. "1"\)
   fi

done


