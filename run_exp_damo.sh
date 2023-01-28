#!/bin/bash

# import common functions
if [ "$BIGMEMBENCH_COMMON_PATH" = "" ] ; then
  echo "ERROR: bigmembench_common script not found. BIGMEMBENCH_COMMON_PATH is $BIGMEMBENCH_COMMON_PATH"
  echo "Have you set BIGMEMBENCH_COMMON_PATH correctly? Are you using sudo -E instead of just sudo?"
  exit 1
fi
source ${BIGMEMBENCH_COMMON_PATH}/run_exp_common.sh

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
NUM_THREADS=32
export OMP_NUM_THREADS=${NUM_THREADS}
#RESULT_DIR="exp/exp_damo/" 
RESULT_DIR="exp/test/" 
DAMO_EXE="/ssd1/songxin8/anaconda3/envs/py36_damo/bin/damo"

MEMCONFIG="${NUM_THREADS}threads"

#declare -a GRAPH_LIST=("kron_g30_k32" "urand_g30_k32")
declare -a GRAPH_LIST=("kron_g30_k32")
declare -a EXE_LIST=("bfs" "pr" "bc" "cc")
#declare -a EXE_LIST=("bfs")

clean_up () {
    echo "Cleaning up. Kernel PID is $EXE_PID"
    # Perform program exit housekeeping
    kill $EXE_PID
    exit
}

run_gap () { 
  OUTFILE_NAME=$1 #first argument
  GRAPH=$2
  EXE=$3
  CONFIG=$4

  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"

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

  echo "Start" > $OUTFILE_PATH

  echo "NUMA hardware config is: " >> $OUTFILE_PATH
  NUMACTL_OUT=$(numactl -H)
  echo "$NUMACTL_OUT" >> $OUTFILE_PATH

  PERF_CMD_MMAP="perf record -c 1 -g --call-graph dwarf -m 2M -e syscalls:sys_enter_mmap -e syscalls:sys_exit_mmap -o $OUTFILE_PATH-perf_mmap.data "
  COMMAND_COMMON="$PERF_CMD_MMAP $COMMAND_COMMON"

    case $EXE in
    "bfs")
      #$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360 &>> $OUTFILE_PATH &
      echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n100" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n100 &>> $OUTFILE_PATH &
      ;;
    "pr")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n16 &>> $OUTFILE_PATH &
      ;;
    "cc")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n260 &>> $OUTFILE_PATH &
      ;;
    "bc")
      $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n8 &>> $OUTFILE_PATH &
      ;;
    #"sssp")
    #  echo "$COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n15" >> $OUTFILE_PATH
    #  $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n30 &>> $OUTFILE_PATH &
    #  ;;
    #"tc")
    #  $COMMAND_COMMON ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n1 &>> $OUTFILE_PATH &
    #  ;;
    *)
      echo -n "ERROR: Unknown executable $EXE"
      exit 1
      ;;
  esac
  sleep 5 # give the command some time to show up
  # the PID of the background /usr/bin/time command
  TIME_PID=$(pidof '/usr/bin/time')
  echo "time pid $TIME_PID"
  # the PID of the kernel, which is a child of /usr/bin/time
  EXE_PID=$(pgrep -P $TIME_PID)
  echo "exe pid $EXE_PID"

  # wait until the graph is loaded into memory and the algorithm starts. 
  # this takes roughly 38 seconds for the kron_28 graph
  # < 400s for urand_g30_k32 and kron_g30_k32
  echo "sleeping for 500s to wait for the graph to load into memory"
  sleep 500

  echo "Running damo."
  ${DAMO_EXE} record $EXE_PID --out ${OUTFILE_PATH}-damo.data &
  DAMO_PID=$! 

  echo "running DAMO for 10 minutes. DAMO data trace file is ${OUTFILE_PATH}-damo.data"
  sleep 600

  kill $EXE_PID
  echo "DAMO measurement done."
}

collect_damo() {
  OUTFILE_NAME=$1 
  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"
  ${DAMO_EXE} report wss --input ${OUTFILE}-damo.data --range 0 101 1 --sortby time --plot ${OUTFILE}-wss.png
  ${DAMO_EXE} report heats --input ${OUTFILE}-damo.data --heatmap ${OUTFILE}-accessHeatmap.png
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

mkdir -p $RESULT_DIR

# allocate all data on local memory
make clean -j
make -j
enable_damo

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_allLocal")
    run_gap $LOGFILE_NAME $graph $exe "ALL_LOCAL"
    sleep 5
    #collect_damo $LOGFILE_NAME
  done
done
