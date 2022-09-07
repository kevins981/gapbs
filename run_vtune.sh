#!/bin/bash

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs_nvm/benchmark/graphs"
ITERS=64
NUM_THREADS=32
export OMP_NUM_THREADS=${NUM_THREADS}

declare -a GRAPH_LIST=("twitter")
#declare -a EXE_LIST=("cc" "bc" "pr")
declare -a EXE_LIST=("bfs")

clean_cache () { 
  echo "Clearing caches..."
  # clean CPU caches
  ./tools/clear_cpu_cache
  # clean page cache
  echo 3 > /proc/sys/vm/drop_caches
}

run_vtune () {
  OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3

  case $EXE in
    "bc")
      /opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-access -knob sampling-interval=5 -knob analyze-mem-objects=true -knob analyze-openmp=true -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_bc/${OUTFILE} --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n${ITERS}
      ;;
    "pr")
      /opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-access -knob sampling-interval=5 -knob analyze-mem-objects=true -knob analyze-openmp=true -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_pr/${OUTFILE} --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n${ITERS}
      ;;
    "cc")
      /opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-access -knob sampling-interval=5 -knob analyze-mem-objects=true -knob analyze-openmp=true -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_cc/${OUTFILE} --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n${ITERS}
      ;;
    "tc")
      /opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-access -knob sampling-interval=10 -knob analyze-mem-objects=true -knob analyze-openmp=true -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_tc/${OUTFILE} --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n${ITERS}
      ;;
    "bfs")
      /opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-access -knob sampling-interval=5 -knob analyze-mem-objects=true -knob analyze-openmp=true -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_bfs/${OUTFILE} --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n${ITERS}
      ;;
    *)
      echo -n "Unknown executable $EXE"
      ;;
  esac



}

##############
# Script start
##############

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

./setup.sh

# All allocations on node 0
make clean -j
make -j
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_vtune "${exe}_${graph}_allnode0_${NUM_THREADS}threads_x${ITERS}" $graph $exe
  done
done

# Allocate neigh array on node 1
make clean -j
make neigh_on_numa1 -j
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_vtune "${exe}_${graph}_neighonnode1_${NUM_THREADS}threads_x${ITERS}" $graph $exe
  done
done

# Allocate neigh array on NVM
make clean -j
make neigh_on_nvm -j
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_gap "${exe}_${graph}_neighonnvm_${NUM_THREADS}threads_x${ITERS}" $graph $exe
  done
done

