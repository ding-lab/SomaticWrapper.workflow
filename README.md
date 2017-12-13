Simple workflow implementation for SomaticWrapper on MGI and standard Docker environments

* Initialize, launch, and track analysis jobs
* Works on MGI and standard Docker environments

## Note on MGI environment

MGI environment is unique and requires different procedures than standard Docker implementations.  Specifically,
* Docker environment has MGI volumes mounted
    * Both Docker and MGI data available
        * Container data in e.g. /data not visible from outside container
        * Container still sees user home directory and other MGI partitions, e.g. /gscmnt/gc3025/dinglab
        * Take care to avoid MGI-specific paths with an image
    * Path issues arise when MGI user configuration files (e.g. .bashrc) are automatically evaluated.
        * We install in image a configuration file /home/bps/mgi-bps.bashrc which sets paths.  It is evaluated upon
          startup by script /home/bps/mgi-bps_start.sh
* User is same uid as at MGI, and cannot run anything as root
    * As a consequence, files installed as part of Dockerfile (by 'root') cannot be edited from within
      container (no write privileges)
    * It is more convenient during development to use MGI user directory than e.g. /usr/local/somaticwrapper,
      since the latter can be modified while the former cannot
* There is no `docker` command.  Docker container is launched using bsub
    * Cannot build an image at MGI
    * Cannot exec into a running container
    * Will execute on an arbitrary machine
        * Container data in e.g. /data is lost when job exits unless shared volume mounted during initialization

