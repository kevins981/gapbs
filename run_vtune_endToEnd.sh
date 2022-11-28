#!/bin/bash

#TODO: cannot build vtune drivers for kernel 6.1-rc6

# import common functions
if [ "$BIGMEMBENCH_COMMON_PATH" = "" ] ; then
  echo "ERROR: bigmembench_common script not found. BIGMEMBENCH_COMMON_PATH is $BIGMEMBENCH_COMMON_PATH"
  echo "Have you set BIGMEMBENCH_COMMON_PATH correctly? Are you using sudo -E instead of just sudo?"
  exit 1
fi
source ${BIGMEMBENCH_COMMON_PATH}/run_exp_common.sh

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
RESULT_DIR="/ssd1/songxin8/thesis/graph/vtune/test/"
#RESULT_DIR="/ssd1/songxin8/thesis/graph/vtune/exp_endToEnd/"

NUM_THREADS=16
export OMP_NUM_THREADS=${NUM_THREADS}
MEMCONFIG="${NUM_THREADS}threads"

VTUNE_EXE="/opt/intel/oneapi/vtune/latest/bin64/vtune"

declare -a GRAPH_LIST=("kron_g30_k32")
#declare -a EXE_LIST=("bfs" "pr" "bc" "cc")
declare -a EXE_LIST=("bfs")

export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/debug/libstdc++.so.6.0.28" 
echo "LD_PRELOAD: $LD_PRELOAD"

run_vtune () {
  OUTFILE_NAME=$1 #first argument
  GRAPH=$2
  EXE=$3
  CONFIG=$4

  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"

  export OMP_NUM_THREADS=${NUM_THREADS}
  echo "OMP_NUM_THREADS is $OMP_NUM_THREADS"

  VTUNE_MEMACC_COMMON="${VTUNE_EXE} -collect memory-access -start-paused \
      -knob sampling-interval=10 -knob analyze-mem-objects=true -knob analyze-openmp=true \
      -data-limit=10000 -result-dir ${OUTFILE_PATH}-memacc \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  VTUNE_HOTSPOT_COMMON="${VTUNE_EXE} -collect hotspots -start-paused \
      -data-limit=10000 -result-dir ${OUTFILE_PATH}-hotspot \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  VTUNE_UARCH_COMMON="${VTUNE_EXE} -collect uarch-exploration -start-paused \
      -knob sampling-interval=10 -knob collect-memory-bandwidth=true
      -data-limit=10000 -result-dir ${OUTFILE_PATH}-uarch \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  if [[ "$CONFIG" == "ALL_LOCAL" ]]; then
    # All local config: place both data and compute on node 1
    COMMAND_COMMON="/usr/bin/numactl --membind=1 --cpunodebind=1"
  elif [[ "$CONFIG" == "EDGES_ON_REMOTE" ]]; then
    # place edges array on node 1, rest on node 0
    COMMAND_COMMON="/usr/bin/numactl --membind=0 --cpunodebind=0"
  elif [[ "$CONFIG" == "TPP" ]]; then
    # only use node 0 CPUs and let TPP decide how memory is placed
    COMMAND_COMMON="/usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "AUTONUMA" ]]; then
    COMMAND_COMMON="/usr/bin/numactl --cpunodebind=0"
  else
    echo "Error! Undefined configuration $CONFIG"
    exit 1
  fi

  case $EXE in
    "bfs")
      GAP_KERNEL_CMD="${COMMAND_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360"
      ;;
    "pr")
      GAP_KERNEL_CMD="${COMMAND_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n8"
      ;;
    "cc")
      GAP_KERNEL_CMD="${COMMAND_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n260"
      ;;
    "bc")
      GAP_KERNEL_CMD="${COMMAND_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n4"
      ;;
    "sssp")
      GAP_KERNEL_CMD="${COMMAND_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n1"
      ;;
    "tc")
      GAP_KERNEL_CMD="${COMMAND_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n1"
      ;;

    *)
      echo -n "ERROR: Unknown executable $EXE"
      exit 1
      ;;
  esac

  echo "Starting analysis. Log file is ${OUTFILE_PATH}_hotspot_log"
  ${VTUNE_HOTSPOT_COMMON} -- ${GAP_KERNEL_CMD} &> ${OUTFILE_PATH}_hotspot_log
  clean_cache
  echo "Starting analysis. Log file is ${OUTFILE_PATH}_memacc_log"
  ${VTUNE_MEMACC_COMMON} -- ${GAP_KERNEL_CMD} &> ${OUTFILE_PATH}_memacc_log
  clean_cache
  echo "Starting analysis. Log file is ${OUTFILE_PATH}_uarch_log"
  ${VTUNE_UARCH_COMMON} -- ${GAP_KERNEL_CMD} &> ${OUTFILE_PATH}_uarch_log

}

##############
# Script start
##############

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

mkdir -p $RESULT_DIR

setup_vtune

echo "NUMA hardware config is: "
NUMACTL_OUT=$(numactl -H)
echo "$NUMACTL_OUT"

# Everything on local node 0 DRAM
make clean
make -j
disable_numa
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_allLocal")
    run_vtune $LOGFILE_NAME $graph $exe "ALL_LOCAL"
    #run_vtune "${exe}_${graph}_${NUM_THREADS}threads_all_on_node0" $graph $exe
  done
done

# AutoNUMA
make clean
make -j
enable_autonuma
echo "Number of threads: ${OMP_NUM_THREADS}" 
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_autonuma")
    run_vtune $LOGFILE_NAME $graph $exe "AUTONUMA"
  done
done

# Neighbors array on node 1
make clean
make neigh_on_numa1 -j
disable_numa
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_edgeOnRemote")
    run_vtune $LOGFILE_NAME $graph $exe "EDGE_ON_REMOTE"
    #run_vtune "${exe}_${graph}_${NUM_THREADS}threads_neigh_on_numa1" $graph $exe
  done
done
