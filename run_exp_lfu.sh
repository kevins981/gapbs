#!/bin/bash

# TODO: since the number of trials required is different for each graph/threads/config, should prob pass
#       it into run_gap
# TODO: probably should not just top a sinlge process. What if there are other processes?

# import common functions
if [ "$BIGMEMBENCH_COMMON_PATH" = "" ] ; then
  echo "ERROR: bigmembench_common script not found. BIGMEMBENCH_COMMON_PATH is $BIGMEMBENCH_COMMON_PATH"
  echo "Have you set BIGMEMBENCH_COMMON_PATH correctly? Are you using sudo -E instead of just sudo?"
  exit 1
fi
source ${BIGMEMBENCH_COMMON_PATH}/run_exp_common.sh

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
NUM_THREADS=16
export OMP_NUM_THREADS=${NUM_THREADS}
RESULT_DIR="exp/exp_lfu/" 
MEMCONFIG="${NUM_THREADS}threads_16GB"
NUM_ITERS=1


#declare -a GRAPH_LIST=("kron_g30_k32" "urand_g30_k32") 
declare -a GRAPH_LIST=("kron_g30_k32")
declare -a EXE_LIST=("bc" "bfs" "pr" "cc") 

run_gap () { 
  OUTFILE_NAME=$1 #first argument
  GRAPH=$2
  EXE=$3
  CONFIG=$4

  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"

  if [[ "$CONFIG" == "ALL_LOCAL" ]]; then
    # All local config: place both data and compute on node 1
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=0 --cpunodebind=0"
  elif [[ "$CONFIG" == "EDGES_ON_REMOTE" ]]; then
    # place edges array on node 1, rest on node 0
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=0 --cpunodebind=0"
  elif [[ "$CONFIG" == "TPP" ]]; then
    # only use node 0 CPUs and let TPP decide how memory is placed
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "AUTONUMA" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "LFU" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "MULTICLOCK" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  else
    echo "Error! Undefined configuration $CONFIG"
    exit 1
  fi

  echo "Start" > $OUTFILE_PATH

  echo "=======================" >> $OUTFILE_PATH
  echo "NUMA hardware configs" >> $OUTFILE_PATH
  NUMACTL_OUT=$(numactl -H)
  echo "$NUMACTL_OUT" >> $OUTFILE_PATH

  echo "=======================" >> $OUTFILE_PATH
  echo "Migration counters before" >> $OUTFILE_PATH
  MIGRATION_STAT=$(grep -E "pgdemote|pgpromote|pgmigrate" /proc/vmstat)
  echo "$MIGRATION_STAT" >> $OUTFILE_PATH

  echo "=======================" >> $OUTFILE_PATH
  echo "NUMA statistics before" >> $OUTFILE_PATH
  NUMA_STAT=$(numastat)
  echo "$NUMA_STAT" >> $OUTFILE_PATH

  case $EXE in
    "bfs")
      echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360" >> $OUTFILE_PATH 
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360 &>> $OUTFILE_PATH 
      ;;
    "pr")
      echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n6" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n6 &>> $OUTFILE_PATH 
      ;;
    "bc")
      echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n6" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n6 &>> $OUTFILE_PATH 
      ;; 
    "cc")
      echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n260" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n260 &>> $OUTFILE_PATH 
      ;;
    "sssp")
      echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n30" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n30 &>> $OUTFILE_PATH 
      ;;
    "tc")
      echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n1" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n1 &>> $OUTFILE_PATH 
      ;;
    *)
      echo -n "ERROR: Unknown executable $EXE"
      exit 1
      ;;
  esac
  echo "GAP kernel complete."

  echo "=======================" >> $OUTFILE_PATH
  echo "Migration counters after" >> $OUTFILE_PATH
  MIGRATION_STAT=$(grep -E "pgdemote|pgpromote|pgmigrate" /proc/vmstat)
  echo "$MIGRATION_STAT" >> $OUTFILE_PATH

  echo "=======================" >> $OUTFILE_PATH
  echo "NUMA statistics after" >> $OUTFILE_PATH
  NUMA_STAT=$(numastat)
  echo "$NUMA_STAT" >> $OUTFILE_PATH
}


##############
# Script start
##############
mkdir -p $RESULT_DIR


## AutoNUMA. not specifying where to allocate. Let AutoNUMA decide 
#make clean -j
#make -j
#BUILD_RET=$?
#echo "Build return: $BUILD_RET"
#if [ $BUILD_RET -ne 0 ]; then
#  echo "ERROR: Failed to build GAP"
#  exit 1
#fi
#
#enable_autonuma "MGLRU"
#for ((i=0;i<$NUM_ITERS;i++));
#do
#  for graph in "${GRAPH_LIST[@]}"
#  do
#    for exe in "${EXE_LIST[@]}"
#    do
#      clean_cache
#      LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_autonuma" "iter$i")
#      run_gap $LOGFILE_NAME $graph $exe "AUTONUMA"
#    done
#  done
#done

# TinyLFU
make clean -j
make -j tinylfu
BUILD_RET=$?
echo "Build return: $BUILD_RET"
if [ $BUILD_RET -ne 0 ]; then
  echo "ERROR: Failed to build GAP"
  exit 1
fi

enable_lfu 
for ((i=0;i<$NUM_ITERS;i++));
do
  for graph in "${GRAPH_LIST[@]}"
  do
    for exe in "${EXE_LIST[@]}"
    do
      clean_cache
      LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_lfu" "iter$i")
      run_gap $LOGFILE_NAME $graph $exe "LFU"
    done
  done
done


## TPP
#make clean -j
#make -j
#BUILD_RET=$?
#echo "Build return: $BUILD_RET"
#if [ $BUILD_RET -ne 0 ]; then
#  echo "ERROR: Failed to build GAP"
#  exit 1
#fi

#enable_tpp 
#
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_tpp")
#    run_gap $LOGFILE_NAME $graph $exe "TPP"
#  done
#done 


## allocate neighbors array on node 1
#make clean -j
#make neigh_on_numa1 -j
#disable_numa 
#
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_edgesOnRemote")
#    run_gap $LOGFILE_NAME $graph $exe "EDGES_ON_REMOTE"
#  done
#done

## allocate all data on local memory
#make clean -j
#make -j
#BUILD_RET=$?
#echo "Build return: $BUILD_RET"
#if [ $BUILD_RET -ne 0 ]; then
#  echo "ERROR: Failed to build GAP"
#  exit 1
#fi

#disable_numa 
#
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_allLocal")
#    run_gap $LOGFILE_NAME $graph $exe "ALL_LOCAL"
#  done
#done

## Multi-clock
#make clean -j
#make -j
#enable_multiclock 
#
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_multiclock")
#    run_gap $LOGFILE_NAME $graph $exe "MULTICLOCK"
#  done
#done
