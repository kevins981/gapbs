#!/bin/bash

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
NUM_THREADS=32
export OMP_NUM_THREADS=${NUM_THREADS}
RESULT_DIR="/ssd1/songxin8/thesis/graph/vtune/all_sweep_exp1/"

declare -a GRAPH_LIST=("kron_28" "urand_28")
#declare -a EXE_LIST=("cc" "bc" "pr" "sssp" "bfs" "tc")
declare -a EXE_LIST=("cc" "bc" "pr" "bfs")

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
  NODE=$4

  VTUNE_MEMACC_COMMON="/opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-access -start-paused \
      -knob sampling-interval=10 -knob analyze-mem-objects=true -knob analyze-openmp=true \
      -data-limit=5000 -result-dir ${RESULT_DIR}/${OUTFILE}_memacc \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  VTUNE_HOTSPOT_COMMON="/opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect hotspots -start-paused \
      -data-limit=5000 -result-dir ${RESULT_DIR}/${OUTFILE}_hotspot \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  case $EXE in
    "bfs")
      ${VTUNE_HOTSPOT_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n800
      ${VTUNE_MEMACC_COMMON}  -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n800
      ;;
    "pr")
      ${VTUNE_HOTSPOT_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n28
      ${VTUNE_MEMACC_COMMON}  -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n28
      ;;
    "cc")
      ${VTUNE_HOTSPOT_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n800
      ${VTUNE_MEMACC_COMMON}  -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n800
      ;;
    "bc")
      ${VTUNE_HOTSPOT_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n16
      ${VTUNE_MEMACC_COMMON}  -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n16
      ;;
    #"tc")
    #  ${VTUNE_HOTSPOT_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n3
    #  ${VTUNE_MEMACC_COMMON}  -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n3
    #  ;;
    #"sssp")
    #  ${VTUNE_HOTSPOT_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -n32 -d2
    #  ${VTUNE_MEMACC_COMMON}  -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -n32 -d2
    #  ;;
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

for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_vtune "${exe}_${graph}_allnode0_${NUM_THREADS}threads" $graph $exe 0
    clean_cache
    run_vtune "${exe}_${graph}_allnode1_${NUM_THREADS}threads" $graph $exe 1
  done
done

