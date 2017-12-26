#!/usr/bin/env bash
################################################################################
# myhadoop-configure.sh - establish a valid $HADOOP_CONF_DIR with all of the
#   configurations necessary to start a Hadoop cluster from within a HPC batch
#   environment.  Additionally format HDFS and leave everything in a state ready
#   for Hadoop to start up via start-all.sh.
#
#   Glenn K. Lockwood, San Diego Supercomputer Center
#   Sriram Krishnan, San Diego Supercomputer Center              Feburary 2014
#   tuning added by Hugo Meiland, Bull                           June 2014
################################################################################

### declare -A will not work on bash 3 (default on EL5); fail gracefully
if [ ${BASH_VERSINFO[0]} -lt 4 ]; then 
    echo "myHadoop requires bash version 4 but you have version ${BASH_VERSINFO[0]}.  Aborting." >&2
    exit 1
fi

#MH_HOME="$(dirname $(readlink -f $0))/.."
MH_HOME="$(dirname $0)/.."

function mh_print {
    echo "mySpark: $@"
}

if [ "z$1" == "z-?" ]; then
  exit 0
fi

function print_nodelist {
    if [ "z$RESOURCE_MGR" == "zpbs" ]; then
        cat $PBS_NODEFILE | sed -e "$MH_IPOIB_TRANSFORM"
    elif [ "z$RESOURCE_MGR" == "zsge" ]; then
        cat $PE_NODEFILE | sed -e "$MH_IPOIB_TRANSFORM"
    elif [ "z$RESOURCE_MGR" == "zslurm" ]; then
        scontrol show hostname $SLURM_NODELIST | sed -e "$MH_IPOIB_TRANSFORM"
    fi
}

### Detect our resource manager and populate necessary environment variables
if [ "z$PBS_JOBID" != "z" ]; then
    RESOURCE_MGR="pbs"
elif [ "z$PE_NODEFILE" != "z" ]; then
    RESOURCE_MGR="sge"
elif [ "z$SLURM_JOBID" != "z" ]; then
    RESOURCE_MGR="slurm"
else
    echo "No resource manager detected.  Aborting." >&2
    print_usage
    exit 1
fi

if [ "z$RESOURCE_MGR" == "zpbs" ]; then
    NODES=$PBS_NUM_NODES
    NUMPROCS=$PBS_NP
    JOBID=$PBS_JOBID
elif [ "z$RESOURCE_MGR" == "zsge" ]; then
    NODES=$NHOSTS
    NUMPROCS=$NSLOTS
    JOBID=$JOB_ID
elif [ "z$RESOURCE_MGR" == "zslurm" ]; then
    NODES=$SLURM_NNODES
    NUMPROCS=$SLURM_NPROCS
    JOBID=$SLURM_JOBID
fi

if [ "z$SPARK_SCRATCH_DIR" == "z" ]; then
    echo "You must specify the local disk filesystem location with -s.  Aborting." >&2
    print_usage
    exit 1
fi
mh_print "Using SPARK_SCRATCH_DIR=$SPARK_SCRATCH_DIR"

if [ "z$JAVA_HOME" == "z" ]; then
    echo "JAVA_HOME is not defined.  Aborting." >&2
    print_usage
    exit 1
fi
mh_print "Using JAVA_HOME=$JAVA_HOME"

if [ "z$SPARK_CONF_DIR" == "z" ]; then
    echo "SPARK_CONF_DIR is not defined.  Aborting." >&2
    print_usage
    exit 1
fi
mh_print "Using SPARK_CONF_DIR=$SPARK_CONF_DIR"

mkdir -p $SPARK_CONF_DIR

### Pick the master node as the first node in the nodefile
MASTER_NODE=$(print_nodelist | /usr/bin/head -n1)
mh_print "Designating $MASTER_NODE as master node (namenode, secondary namenode, and jobtracker)"
echo $MASTER_NODE > $SPARK_CONF_DIR/masters

### Make every node in the nodefile a slave
let NODES=$NODES-1
print_nodelist | awk '{print $1}' | sort -u | tail -n $NODES > $SPARK_CONF_DIR/slaves
mh_print "The following nodes will be slaves (datanode, tasktracer):"
cat $SPARK_CONF_DIR/slaves

### Enable Spark support if SPARK_HOME is defined
if [ "z$SPARK_HOME" != "z" ]; then
  mh_print " "
  mh_print "Enabling experimental Spark support"
  #if [ "z$SPARK_CONF_DIR" == "z" ]; then
  #  SPARK_CONF_DIR=$HADOOP_CONF_DIR/spark
  #fi
  mh_print "Using SPARK_CONF_DIR=$SPARK_CONF_DIR"
  mh_print " "

  mkdir -p $SPARK_CONF_DIR
  cp $SPARK_HOME/conf/* $SPARK_CONF_DIR/
  #cp $HADOOP_CONF_DIR/slaves $SPARK_CONF_DIR/slaves

  cat <<EOF >> $SPARK_CONF_DIR/spark-env.sh
export SPARK_CONF_DIR=$SPARK_CONF_DIR
export SPARK_MASTER_IP=$MASTER_NODE
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_DIR=$SPARK_SCRATCH_DIR/work
export SPARK_LOG_DIR=$SPARK_SCRATCH_DIR/logs

### pyspark shell requires this environment variable be set to work
export MASTER=spark://$MASTER_NODE:7077

### push out the local environment to all slaves so that any loaded modules
### from the user environment are honored by the execution environment
export PATH=$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH

### to prevent Spark from binding to the first address it can find
export SPARK_LOCAL_IP=\$(sed -e '$MH_IPOIB_TRANSFORM' <<< \$HOSTNAME)
EOF

cat <<EOF
To use Spark, you will want to type the following commands:"
  source $SPARK_CONF_DIR/spark-env.sh
  myspark start
EOF
fi
