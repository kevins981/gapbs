#!/bin/bash

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs_nvm/benchmark/graphs"
ITERS=8
#declare -a GRAPH_LIST=("kron_28")
declare -a GRAPH_LIST=("twitter")
#declare -a EXE_LIST=("bc" "pr")
declare -a EXE_LIST=("sssp")
#export OMP_PLACES="{0:15},{32:15}"
#export OMP_PROC_BIND=spread

run_gap () { 
  OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3
  echo "Start" > $OUTFILE
  #numastat -v &>> $OUTFILE
  
  case $EXE in
    "bc")
      /usr/bin/time -v /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n${ITERS} &>> $OUTFILE &
      # PID of time command
      TIME_PID=$! 
      # get PID of actual GAP kernel, which is a child of time. 
      # This PID is needed for the numastat command
      EXE_PID=$(pgrep -P $TIME_PID)
      ;; 
    "pr")
      /usr/bin/time -v /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n${ITERS} &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;
    "sssp")
      /usr/bin/time -v /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n${ITERS} &>> $OUTFILE &
      TIME_PID=$! 
      EXE_PID=$(pgrep -P $TIME_PID)
      ;;

    *)
      echo -n "Unknown executable $EXE"
      ;;
  esac

  echo "start" > ${OUTFILE}_numastat
  while true; do numastat -p $EXE_PID >> ${OUTFILE}_numastat; sleep 2; done &
  LOG_PID=$!

  echo "Waiting for GAP kernel to complete. numastat is logged into ${OUTFILE}_numastat, PID is ${LOG_PID}" 
  wait $TIME_PID
  echo "GAP kernel complete."
  kill $LOG_PID
  
  #echo "After running"  &>> $OUTFILE
  #numastat -v  &>> $OUTFILE
}

# All allocations on node 0
make clean -j
make -j

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    run_gap "exp/${exe}_${graph}_allnode0" $graph $exe
  done
done

# Allocate neigh array on node 1
make clean -j
make neigh_on_numa1 -j

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    run_gap "exp/${exe}_${graph}_neighonnode1" $graph $exe

  done
done

