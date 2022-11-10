#!/bin/bash

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
NUM_THREADS=4
export OMP_NUM_THREADS=${NUM_THREADS}
RESULT_DIR="exp/exp_damo" 
DAMO_EXE="/ssd1/songxin8/anaconda3/envs/py36_damo/bin/damo"

declare -a GRAPH_LIST=("kron_28")
declare -a EXE_LIST=("pr" "bfs")

clean_up () {
    echo "Cleaning up. Kernel PID is $EXE_PID"
    # Perform program exit housekeeping
    kill $EXE_PID
    exit
}

clean_cache () { 
  echo "Clearing caches..."
  # clean CPU caches
  ./tools/clear_cpu_cache
  # clean page cache
  echo 3 > /proc/sys/vm/drop_caches
}

run_gap () { 
  OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3
  NODE=$4
  echo "Start" > $OUTFILE
  #numastat -v &>> $OUTFILE
  
  # Number of trials (-n) set specifically for graphs with 2^28 nodes and avg deg 16,
  # running on 32 threads. These -n's will ensure a total execution time between 10-20 minutes.
  case $EXE in
    "bfs")
      # Setting a huge number of trials (-n) is ok, since we are kill the process after a fixed amount of time
      # measurement is complete.
      /usr/bin/time -v /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n100000 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "pr")
      /usr/bin/time -v /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n100000 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "cc")
      /usr/bin/time -v /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n100000 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "bc")
      /usr/bin/time -v /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n100000 &>> $OUTFILE &
      # PID of time command
      TIME_PID=$! 
      # get PID of actual GAP kernel, which is a child of time. 
      # This PID is needed for the numastat command
      EXE_PID=$(pgrep -P $TIME_PID)
      ;; 
    *)
      echo -n "Unknown executable $EXE"
      ;;
  esac

  # wait until the graph is loaded into memory and the algorithm starts. 
  # this takes roughly 38 seconds for the kron_28 graph
  echo "sleeping for 60s to wait for the graph to load into memory"
  sleep 60

  echo "Running damo."
  ${DAMO_EXE} record $EXE_PID --out ${OUTFILE}_damo.data &
  DAMO_PID=$! 

  echo "running DAMO for 10 minutes. DAMO data trace file is ${OUTFILE}_damo.data"
  sleep 600

  kill $EXE_PID
  echo "DAMO measurement done."
}

collect_damo() {
  OUTFILE=$1 
  ${DAMO_EXE} report wss --input ${OUTFILE}_damo.data --range 0 101 1 --sortby time --plot ${OUTFILE}_wss.png
  ${DAMO_EXE} report heats --input ${OUTFILE}_damo.data --heatmap ${OUTFILE}_access_heatmap.png
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

./setup.sh

mkdir -p $RESULT_DIR

# All allocations on node 0
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_gap "${RESULT_DIR}/${exe}_${graph}_allnode0_${NUM_THREADS}threads" $graph $exe 0
    sleep 5
    collect_damo "${RESULT_DIR}/${exe}_${graph}_allnode0_${NUM_THREADS}threads" 
  done
done

