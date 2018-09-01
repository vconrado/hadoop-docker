#!/bin/bash

HADDOP_SLAVE_NAME="hadoop-slave"
HADDOP_MASTER_NAME="hadoop-master"

if [ $# -lt 3 ]; then
  echo "usage: $0 CLUSTER_NAME HDFS_BASE_PATH N_NODES"
  exit 1
fi

CLUSTER_NAME=$1
HDFS_BASE_PATH=$2
N_NODES=$3

function create_folder() {
    FOLDER=$1
    mkdir -p $FOLDER
    if [ $? -ne 0 ]; then
        echo "ERROR: Was not possible to create the folder '$FOLDER'."
        exit 1
    fi
}

# check if N_NODES is a valid integer
re='^[0-9]+$'
if ! [[ $N_NODES =~ $re ]] ; then
   echo "ERROR: '$N_NODES' is not a valid number"
   exit 1
fi

# check if CLUSTER_NAME is a valid world
re='^[a-zA-Z][a-zA-Z0-9]+$'
if ! [[ $CLUSTER_NAME =~ $re ]] ; then
   echo "ERROR: '$CLUSTER_NAME' is not CLUSTER NAME"
   exit 1
fi


#echo "Using: "
#echo " N_NODES=$N_NODES"
#echo " CLUSTER_NAME=$CLUSTER_NAME"
#echo " HDFS_BASE_PATH=$HDFS_BASE_PATH"

if [ ! -d $HDFS_BASE_PATH ]; then
    echo "'$HDFS_BASE_PATH' not found."
    exit 1
fi

CLUSTER_PATH=$HDFS_BASE_PATH/$CLUSTER_NAME
WORKERS_FILE="$CLUSTER_PATH/config/workers"

if [ -d "$CLUSTER_PATH" ]; then
    echo "Folder '$CLUSTER_PATH' already exists. Using it."
else
    echo "Creating cluster data and configuration folder '$CLUSTER_PATH'"
    create_folder $CLUSTER_PATH
    create_folder "$CLUSTER_PATH/config"

    echo "Creating a folder for namenode ..."
    create_folder "$CLUSTER_PATH/namenode/${CLUSTER_NAME}-${HADDOP_MASTER_NAME}"

    echo "Creating a folder for each datanode ..."
    create_folder "$CLUSTER_PATH/datanode/${CLUSTER_NAME}-${HADDOP_MASTER_NAME}"
    for i in $(seq 1 $N_NODES); do
        create_folder "$CLUSTER_PATH/datanode/${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i/"
    done

    echo "Creating workers file"
    
    rm -rf $WORKERS_FILE
    echo "${CLUSTER_NAME}-${HADDOP_MASTER_NAME}" >> $WORKERS_FILE
    for i in $(seq 1 $N_NODES); do
        NAME="${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i"
        echo $NAME >> $WORKERS_FILE
    done


    echo "Creating core-site.xml file"
    cp config/core-site.xml $CLUSTER_PATH/config
    sed -i "s/hadoop-master/${CLUSTER_NAME}-hadoop-master/g" $CLUSTER_PATH/config/core-site.xml

    echo "Creating mapred-site.xml file"
    cp config/mapred-site.xml $CLUSTER_PATH/config
    sed -i "s/hadoop-master/${CLUSTER_NAME}-hadoop-master/g" $CLUSTER_PATH/config/mapred-site.xml

fi

NETWORK="${CLUSTER_NAME}-hadoop-net"
echo "Creating network $NETWORK"
docker network create $NETWORK

echo "Starting ${CLUSTER_NAME}-${HADDOP_MASTER_NAME}"
docker run -itd \
    --name "${CLUSTER_NAME}-${HADDOP_MASTER_NAME}" \
    --hostname "${CLUSTER_NAME}-${HADDOP_MASTER_NAME}" \
    --volume "$CLUSTER_PATH/datanode/${CLUSTER_NAME}-${HADDOP_MASTER_NAME}":/home/hadoopuser/hdfs/datanode \
    --volume "$CLUSTER_PATH/namenode/${CLUSTER_NAME}-${HADDOP_MASTER_NAME}":/home/hadoopuser/hdfs/namenode \
    --net=$NETWORK \
    vconrado/hadoop_cluster:3.1.1
    
docker cp $WORKERS_FILE ${CLUSTER_NAME}-${HADDOP_MASTER_NAME}:/usr/local/hadoop/etc/hadoop/
docker cp $CLUSTER_PATH/config/core-site.xml ${CLUSTER_NAME}-${HADDOP_MASTER_NAME}:/usr/local/hadoop/etc/hadoop/
docker cp $CLUSTER_PATH/config/mapred-site.xml ${CLUSTER_NAME}-${HADDOP_MASTER_NAME}:/usr/local/hadoop/etc/hadoop/

docker exec ${CLUSTER_NAME}-${HADDOP_MASTER_NAME} hdfs namenode -format

for i in $(seq 1 $N_NODES); do
    echo "Starting ${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i"
    docker run -itd \
        --name "${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i" \
        --hostname "${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i" \
        --volume "$CLUSTER_PATH/datanode/${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i":/home/hadoopuser/hdfs/datanode \
        --net=$NETWORK \
        vconrado/hadoop_cluster:3.1.1

    docker cp $WORKERS_FILE ${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i:/usr/local/hadoop/etc/hadoop/
    docker cp $CLUSTER_PATH/config/core-site.xml ${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i:/usr/local/hadoop/etc/hadoop/
    docker cp $CLUSTER_PATH/config/mapred-site.xml ${CLUSTER_NAME}-${HADDOP_SLAVE_NAME}-$i:/usr/local/hadoop/etc/hadoop/
    
done

            
