#!/usr/bin/env bash
################################################################################
# myhadoop-cleanup.sh - clean up all of the directories created by running a
#   Hadoop cluster via myHadoop.
#
#   Glenn K. Lockwood, San Diego Supercomputer Center            February 2014
################################################################################

### Make sure SPARK_CONF_DIR is set
if [ "z$SPARK_CONF_DIR " == "z" ]; then
    echo 'You must set $SPARK_CONF_DIR so we know what to shut down.' >&2
    exit 1
fi

#if [ -f $SPARK_CONF_DIR/myhadoop.conf ]; then
#    source $SPARK_CONF_DIR/myhadoop.conf || exit 1
#else
#    echo "myhadoop.conf not found in \$SPARK_CONF_DIR.  Aborting." >&2
#    exit 1
#fi

### Copy the logs from the Hadoop cluster back for post-mortem
#echo "Copying Hadoop logs back to $SPARK_CONF_DIR/logs..."
#cp -Lvr ${config_subs[SPARK_LOG_DIR]} $SPARK_CONF_DIR/logs

### Clean up all the garbage from the Hadoop job
for node in $(cat $SPARK_CONF_DIR/slaves $SPARK_CONF_DIR/masters | sort -u | head -n $NODES)
do
    rmdirs=""
    rmlinks=""
    for key in "${!config_subs[@]}"; do
        if [[ $key =~ _DIR$ ]]; then
            ### If a dir is a symlink, that means it's pointing to a persistent
            ### state that should NOT be deleted.
            if [ -h ${config_subs[$key]} ]; then
                rmlinks="${config_subs[$key]} $rmlinks"
            else
                rmdirs="${config_subs[$key]} $rmdirs"
            fi
        fi
    done
    ssh $node "rm -rvf $rmdirs; rm -vf $rmlinks"
done

### Jetty also leaves garbage on the master node
find /tmp -maxdepth 1 -user $USER -name Jetty\* -type d | xargs rm -rvf
