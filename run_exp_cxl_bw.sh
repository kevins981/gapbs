#!/bin/bash

# TODO: check numa_balancing value when running TPP (should be 2)
# TODO: check kernel version for each config.

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
NUM_THREADS=16
export OMP_NUM_THREADS=${NUM_THREADS}
RESULT_DIR="exp/exp_tpp_large2/" 
declare -a GRAPH_LIST=("kron_g30_k32") 
declare -a EXE_LIST=("bfs" "pr" "bc" "cc") 

clean_up () {
    echo "Cleaning up. Kernel PID is $EXE_PID, numastat PID is $NUMASTAT_PID, top PID is $TOP_PID."
    # Perform program exit housekeeping 
    kill $NUMASTAT_PID
    kill $TOP_PID
    kill $EXE_PID
    exit
}

enable_tpp () {
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be inactive)"
  
  echo 15 > /proc/sys/vm/zone_reclaim_mode
  ZONE_RECLAIM_MODE=$(cat /proc/sys/vm/zone_reclaim_mode)
  echo 2 > /proc/sys/kernel/numa_balancing
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  echo 1 > /sys/kernel/mm/numa/demotion_enabled
  DEMOTION_ENABLED=$(cat /sys/kernel/mm/numa/demotion_enabled)
  echo 200 > /proc/sys/vm/demote_scale_factor
  DEMOTE_SCALE_FACTOR=$(cat /proc/sys/vm/demote_scale_factor)
  echo "Kernel parameters: "
  echo "ZONE_RECLAIM_MODE $ZONE_RECLAIM_MODE (15)"
  echo "NUMA_BALANCING $NUMA_BALANCING (2)"
  echo "DEMOTION_ENABLED $DEMOTION_ENABLED (1)"
  echo "DEMOTE_SCALE_FACTOR $DEMOTE_SCALE_FACTOR (200)"
}

enable_autonuma () {
  # numad will override autoNUMA, so stop it
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be inactive)"
  
  echo 1 > /proc/sys/kernel/numa_balancing
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  echo "numa_balancing is now $NUMA_BALANCING (should be 1)"
}

disable_autonuma () {
  # turn off both numa
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be not active)"
  
  echo 0 > /proc/sys/vm/zone_reclaim_mode
  echo 0 > /proc/sys/kernel/numa_balancing
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  echo "numa_balancing is now $NUMA_BALANCING (should be 0)"
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
  CONFIG=$4

  if [[ "$CONFIG" == "ALL_LOCAL" ]]; then
    # All local config: place both data and compute on node 1
    CPUNODEBIND=1
    MEMBIND=1
  elif [[ "$CONFIG" == "EDGES_ON_REMOTE" ]]; then
    # place edges array on node 1, rest on node 0
    CPUNODEBIND=0
    MEMBIND=0
  else
    echo "Error! Undefined configuration $CONFIG"
    exit 1
  fi

  echo "Start" > $OUTFILE

  COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=${MEMBIND} --cpunodebind=${CPUNODEBIND}"
  
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
      # PID of time command
      TIME_PID=$! 
      # get PID of actual GAP kernel, which is a child of time. 
      # This PID is needed for the numastat command
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


run_gap_autonuma () { 
  OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3

  echo "Start" > $OUTFILE
  #numastat -v &>> $OUTFILE
  
  case $EXE in
    "pr")
      # not setting --membind=0. Let AutoNUMA decide where to allocate memory.
      # however the processors have to stay on node 0.
      /usr/bin/time -v /usr/bin/numactl --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n2 &>> $OUTFILE &
          #./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n10 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "bfs")
      /usr/bin/time -v /usr/bin/numactl --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "pr")
      /usr/bin/time -v /usr/bin/numactl --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n2 &>> $OUTFILE &
          #./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n10 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "cc")
      /usr/bin/time -v /usr/bin/numactl --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n2 &>> $OUTFILE &
          #./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n100 &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "bc")
      /usr/bin/time -v /usr/bin/numactl --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n2 &>> $OUTFILE &
          #./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n8 &>> $OUTFILE &
      # PID of time command
      TIME_PID=$! 
      # get PID of actual GAP kernel, which is a child of time. 
      # This PID is needed for the numastat command
      EXE_PID=$(pgrep -P $TIME_PID)
      ;; 
    "tc")
      /usr/bin/time -v /usr/bin/numactl --cpunodebind=0 \
          ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n2 &>> $OUTFILE &
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

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

./setup.sh

mkdir -p $RESULT_DIR

## TPP
#make clean -j
#make -j
#enable_tpp 
#
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    export OMP_NUM_THREADS=${NUM_THREADS}
#    echo "NUM thread: $OMP_NUM_THREADS"
#    run_gap_autonuma "${RESULT_DIR}/${exe}_${graph}_${NUM_THREADS}threads_tpp" $graph $exe
#  done
#done

## AutoNUMA. not specifying where to allocate. Let AutoNUMA decide 
#make clean -j
#make -j
#enable_autonuma 
#
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    run_gap_autonuma "${RESULT_DIR}/${exe}_${graph}_${NUM_THREADS}threads_autonuma" $graph $exe
#  done
#done

# allocate neighbors array on node 1
make clean -j
make neigh_on_numa1 -j
disable_autonuma 

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_gap "${RESULT_DIR}/${exe}_${graph}_${NUM_THREADS}threads_edgesonremote" $graph $exe "EDGES_ON_REMOTE"
  done
done

# allocate all data on node 0
make clean -j
make -j
disable_autonuma 

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_gap "${RESULT_DIR}/${exe}_${graph}_${NUM_THREADS}threads_alllocal" $graph $exe "ALL_LOCAL"
  done
done
