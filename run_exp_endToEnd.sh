#!/bin/bash

# TODO: combine run_gap and run_gap_autonuma 

# import common functions
echo ${BIGMEMBENCH_COMMON_PATH}
source ${BIGMEMBENCH_COMMON_PATH}/run_exp_common.sh

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
NUM_THREADS=16
export OMP_NUM_THREADS=${NUM_THREADS}
#RESULT_DIR="exp/exp_endToEnd/" 
RESULT_DIR="exp/test/" 
MEMCONFIG="${NUM_THREADS}threads"

#declare -a GRAPH_LIST=("kron_g30_k32" "urand_g30_k32") 
#declare -a EXE_LIST=("bfs" "pr" "bc" "cc") 
declare -a GRAPH_LIST=("kron_27") 
declare -a EXE_LIST=("bfs")

clean_up () {
  echo "Cleaning up. Kernel PID is $EXE_PID, numastat PID is $NUMASTAT_PID, top PID is $TOP_PID."
  # Perform program exit housekeeping 
  kill $NUMASTAT_PID
  kill $TOP_PID
  kill $EXE_PID
  exit
}

run_gap () { 
  OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3
  CONFIG=$4

  if [[ "$CONFIG" == "ALL_LOCAL" ]]; then
    # All local config: place both data and compute on node 1
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=1 --cpunodebind=1"
  elif [[ "$CONFIG" == "EDGES_ON_REMOTE" ]]; then
    # place edges array on node 1, rest on node 0
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=0 --cpunodebind=0"
  elif [[ "$CONFIG" == "TPP" ]]; then
    # only use node 0 CPUs and let TPP decide how memory is placed
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "AUTONUMA" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  else
    echo "Error! Undefined configuration $CONFIG"
    exit 1
  fi

  echo "Start" > $OUTFILE
  echo "NUMA hardware config is: "
  NUMACTL_OUT=$(numactl -H)
  echo "$NUMACTL_OUT"

  case $EXE in
    "bfs")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "pr")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n8 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "cc")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n260 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "bc")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n4 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;; 
    "sssp")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n1 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "tc")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n1 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    *)
      echo -n "Unknown executable $EXE"
      ;;
  esac

  echo "EXE PID is ${EXE_PID}"
  echo "start" > ${OUTFILE}_numastat
  while true; do numastat -p $EXE_PID >> ${OUTFILE}_numastat; sleep 5; done &
  NUMASTAT_PID=$!
  top -b -d 10 -1 -p $EXE_PID > ${OUTFILE}_top_log &
  TOP_PID=$!

  echo "Waiting for GAP kernel to complete (PID is ${EXE_PID}). numastat is logged into ${OUTFILE}_numastat, PID is ${NUMASTAT_PID}. Top log PID is ${TOP_PID}" 
  wait $TIME_PID
  echo "GAP kernel complete."
  kill $NUMASTAT_PID
  kill $TOP_PID
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

mkdir -p $RESULT_DIR

## TPP
make clean -j
make -j
enable_tpp 
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    export OMP_NUM_THREADS=${NUM_THREADS}
    echo "NUM thread: $OMP_NUM_THREADS"
    run_gap "${RESULT_DIR}/${exe}_${graph}_${NUM_THREADS}threads_tpp" $graph $exe "TPP"
  done
done

# AutoNUMA. not specifying where to allocate. Let AutoNUMA decide 
make clean -j
make -j
enable_autonuma 

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_gap "${RESULT_DIR}/${exe}-${graph}-${MEMCONFIG}_autonuma" $graph $exe "AUTONUMA"
  done
done

# allocate neighbors array on node 1
make clean -j
make neigh_on_numa1 -j
disable_numa 

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_gap "${RESULT_DIR}/${exe}_${graph}_${NUM_THREADS}threads_edgesonremote" $graph $exe "EDGES_ON_REMOTE"
  done
done

# allocate all data on local memory
make clean -j
make -j
disable_numa 

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_gap "${RESULT_DIR}/${exe}-${graph}-${MEMCONFIG}_allLocal" $graph $exe "ALL_LOCAL"
  done
done
