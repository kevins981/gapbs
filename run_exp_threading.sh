#!/bin/bash

# Run experiments for performance vs. # of threads

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
RESULT_DIR="exp/exp_threading"

declare -a GRAPH_LIST=("kron_28")
declare -a EXE_LIST=("bfs")
declare -a THREAD_LIST=("32" "16" "8" "4" "2" "1")

clean_up () {
    echo "Cleaning up. Kernel PID is $EXE_PID, numastat PID is $LOG_PID."
    # Perform program exit housekeeping
    kill $LOG_PID
    kill $LOG2_PID
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

run_gap () { OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3
  NODE=$4
  THREADS=$5
  echo "Running $EXE with $THREADS threads..."
  echo "Start" > $OUTFILE
  #numastat -v &>> $OUTFILE
  
  # Number of trials (-n) set specifically for graphs with 2^28 nodes and avg deg 16,
  # running on 32 threads. These -n's will ensure a total execution time between 10-20 minutes.
  case $EXE in
    "bfs")
      # hand picked 90 trials, which should take ~15min for 1 thread
      /usr/bin/time -v /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n90 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    *)
      echo -n "Unknown executable $EXE"
      ;;
  esac

  echo "EXE PID is ${EXE_PID}"
  echo "start" > ${OUTFILE}_numastat
  while true; do numastat -p $EXE_PID >> ${OUTFILE}_numastat; sleep 2; done &
  LOG_PID=$!
  pcm-memory 2 -s -csv=${OUTFILE}_pcm_log.csv &
  LOG2_PID=$!

  echo "Waiting for GAP kernel to complete (PID is ${EXE_PID}). numastat is logged into ${OUTFILE}_numastat, PID is ${LOG_PID}" 
  wait $TIME_PID
  echo "GAP kernel complete."
  kill $LOG_PID
  kill $LOG2_PID
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

./setup.sh

mkdir -p $RESULT_DIR

make clean -j
make -j


for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    for threads in "${THREAD_LIST[@]}"
    do
      export OMP_NUM_THREADS=${threads}
      clean_cache
      run_gap "${RESULT_DIR}/${exe}_${graph}_allnode0_${threads}threads" $graph $exe 0 $threads
      clean_cache
      run_gap "${RESULT_DIR}/${exe}_${graph}_allnode1_${threads}threads" $graph $exe 1 $threads
    done
  done
done

