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

GRAPH_DIR="/ssd1/songxin8/thesis/graph/graphs"
NUM_THREADS=16
export OMP_NUM_THREADS=${NUM_THREADS}
RESULT_DIR="exp/asplos25/regularpage_128GB/" 
#RESULT_DIR="exp/asplos25/onlyfreqcbf/" 


HOOK_DIR="$BIGMEMBENCH_COMMON_PATH/hook"
HOOK_SO="$BIGMEMBENCH_COMMON_PATH/hook/hook.so"

HOOK_HEMEM_DIR="/ssd1/songxin8/thesis/bigmembench_common_isca24_hemem/hook"
HOOK_HEMEM_SO="/ssd1/songxin8/thesis/bigmembench_common_isca24_hemem/hook/hook.so"
NUM_ITERS=1

PERF_STAT_INTERVAL=10000
MEMCONFIG="${NUM_THREADS}threads_128GB"

#declare -a GRAPH_LIST=("kron_g30_k32" "urand_g30_k32") 
#declare -a GRAPH_LIST=("kron_g31_k4_64bitnode")
declare -a GRAPH_LIST=("g31k4")
#declare -a EXE_LIST=("bfs" "cc") 
declare -a EXE_LIST=("bfs" "cc" "pr") 

run_gap () { 
  OUTFILE_NAME=$1 #first argument
  GRAPH=$2
  EXE=$3
  CONFIG=$4

  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"

  COMMAND_COMMON=$(get_cmd_prefix $CONFIG)

  write_frontmatter $OUTFILE_PATH

  start_perf_stat $PERF_STAT_INTERVAL $OUTFILE_PATH


  if [[ "$CONFIG" == "LFU" ]]; then
    pushd $HOOK_DIR
    echo "Recompiling hook with right exe name: hook.cpp.${EXE}"
    cp hook.cpp.${EXE} hook.cpp
    g++ -shared -fPIC hook.cpp -o hook.so -O3 -ldl -lpthread -lnuma
    popd
    export LD_PRELOAD=${HOOK_SO}
  elif [[ "$CONFIG" == "HEMEM" ]]; then
    pushd $HOOK_HEMEM_DIR
    echo "Recompiling hemem hook with right exe name: hook.cpp.${EXE}"
    cp hook.cpp.${EXE} hook.cpp
    g++ -shared -fPIC hook.cpp -o hook.so -O3 -ldl -lpthread -lnuma
    popd
    export LD_PRELOAD=${HOOK_HEMEM_SO}
    export HEMEM_HOT_THRESH=2
  else
    export LD_PRELOAD=
  fi

  echo "LD_PRELOAD is $LD_PRELOAD"

  case $EXE in
    "bfs")
      echo "$COMMAND_COMMON ./${EXE} -g 31 -k 4 -n256" >> $OUTFILE_PATH 
      $COMMAND_COMMON ./${EXE} -g 31 -k 4 -n256 &>> $OUTFILE_PATH 
      ;;
    "pr")
      echo "$COMMAND_COMMON ./${EXE} -g 31 -k 4 -i1000 -t1e-4 -n16" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -g 31 -k 4 -i1000 -t1e-4 -n16 &>> $OUTFILE_PATH 
      ;;
    "bc")
      echo "$COMMAND_COMMON ./${EXE} -g 31 -k 4 -i4 -n8" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -g 31 -k 4 -i4 -n8 &>> $OUTFILE_PATH 
      ;; 
    "cc")
      echo "$COMMAND_COMMON ./${EXE} -g 31 -k 4 -n256" >> $OUTFILE_PATH
      $COMMAND_COMMON ./${EXE} -g 31 -k 4 -n256 &>> $OUTFILE_PATH 
      ;;
    *)
      echo -n "ERROR: Unknown executable $EXE"
      exit 1
      ;;
  esac
  export LD_PRELOAD=

  write_backmatter $OUTFILE_PATH
  kill_perf_stat
}


##############
# Script start
##############
mkdir -p $RESULT_DIR


# AutoNUMA. not specifying where to allocate. Let AutoNUMA decide 
enable_autonuma "MGLRU"
huge_page_off
for ((i=0;i<$NUM_ITERS;i++));
do
  for graph in "${GRAPH_LIST[@]}"
  do
    for exe in "${EXE_LIST[@]}"
    do
      clean_cache
      LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_autonuma" "iter$i")
      run_gap $LOGFILE_NAME $graph $exe "AUTONUMA"
    done
  done
done

## TinyLFU
#enable_lfu 
#huge_page_off
#for ((i=0;i<$NUM_ITERS;i++));
#do
#  for graph in "${GRAPH_LIST[@]}"
#  do
#    for exe in "${EXE_LIST[@]}"
#    do
#      clean_cache
#      LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_lfu" "iter$i")
#      run_gap $LOGFILE_NAME $graph $exe "LFU"
#    done
#  done
#done

## Emulated HeMem
#enable_lfu 
#for ((i=0;i<$NUM_ITERS;i++));
#do
#  for graph in "${GRAPH_LIST[@]}"
#  do
#    for exe in "${EXE_LIST[@]}"
#    do
#      clean_cache
#      LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_hemem" "iter$i")
#      run_gap $LOGFILE_NAME $graph $exe "HEMEM"
#    done
#  done
#done

## All local
#disable_numa
#for ((i=0;i<$NUM_ITERS;i++));
#do
#  for graph in "${GRAPH_LIST[@]}"
#  do
#    for exe in "${EXE_LIST[@]}"
#    do
#      clean_cache
#      LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_alllocal" "iter$i")
#      run_gap $LOGFILE_NAME $graph $exe "ALL_LOCAL"
#    done
#  done
#done

## TPP
#enable_tpp 
#huge_page_off
#for ((i=0;i<$NUM_ITERS;i++));
#do
#  for graph in "${GRAPH_LIST[@]}"
#  do
#    for exe in "${EXE_LIST[@]}"
#    do
#      clean_cache
#      LOGFILE_NAME=$(gen_file_name "${exe}" "${graph}" "${MEMCONFIG}_tpp" "iter$i")
#      run_gap $LOGFILE_NAME $graph $exe "TPP"
#    done
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
