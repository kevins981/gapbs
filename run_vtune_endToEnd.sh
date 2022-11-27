#!/bin/bash

#TODO: run each GAP kernel for a fixed number of iterations, instead of killing vtunes

GRAPH_DIR="/ssd1/songxin8/thesis/graph/gapbs/benchmark/graphs"
RESULT_DIR="/ssd1/songxin8/thesis/graph/vtune/exp_tpp_large/"

NUM_THREADS=16
export OMP_NUM_THREADS=${NUM_THREADS}

declare -a GRAPH_LIST=("kron_g30_k32")
#declare -a EXE_LIST=("bfs" "pr" "bc" "cc")
declare -a EXE_LIST=("bfs")

export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/debug/libstdc++.so.6.0.28"
echo "LD_PRELOAD: $LD_PRELOAD"

clean_cache () { 
  echo "Clearing caches..."
  # clean CPU caches
  ./tools/clear_cpu_cache
  # clean page cache
  echo 3 > /proc/sys/vm/drop_caches
}

disable_autonuma() {
  # turn off both numa
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be not active)"
  echo 0 > /proc/sys/kernel/numa_balancing 
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  echo "numa_balancing is now $NUMA_BALANCING (should be 0)"
  echo 0 > /proc/sys/vm/zone_reclaim_mode
}

enable_autonuma() {
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be inactive)"
  
  echo 1 > /proc/sys/kernel/numa_balancing
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  echo "numa_balancing is now $NUMA_BALANCING (should be 1)"
}

run_vtune () {
  OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3

  export OMP_NUM_THREADS=${NUM_THREADS}
  echo "OMP_NUM_THREADS is $OMP_NUM_THREADS"

  VTUNE_MEMACC_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect memory-access -start-paused \
      -knob sampling-interval=10 -knob analyze-mem-objects=true -knob analyze-openmp=true \
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_memacc \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  VTUNE_HOTSPOT_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect hotspots -start-paused \
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_hotspot \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  VTUNE_UARCH_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect uarch-exploration -start-paused \
      -knob sampling-interval=10 -knob collect-memory-bandwidth=true
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_uarch \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  NUMACTL_COMMOM="/usr/bin/numactl --membind=0 --cpunodebind=0"

  case $EXE in
    "bfs")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n200 
      #clean_cache

      echo "${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360"
      #${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360 \
      #    &> ${RESULT_DIR}/${OUTFILE}_memacc_log
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n200
      ;;
    "pr")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n800000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n8 \
          &> ${RESULT_DIR}/${OUTFILE}_memacc_log
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n800000  &
      ;;
    "cc")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n18800000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n260 \
          &> ${RESULT_DIR}/${OUTFILE}_memacc_log
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n18800000  &
      ;;
    "bc")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n400000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n4 \
          &> ${RESULT_DIR}/${OUTFILE}_memacc_log
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n400000  &
      ;;
    "sssp")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n100000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n100000 &
      sleep 900
      /opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_memacc
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n100000 &
      #sleep 900
      #/opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_uarch
      ;;
    "tc")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n1000000 &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n100000 &
      sleep 900
      /opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_memacc
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n100000 &
      #sleep 900
      #/opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_uarch
      ;;

    *)
      echo -n "Unknown executable $EXE"
      ;;
  esac

}

run_vtune_autonuma () {
  OUTFILE=$1 #first argument
  GRAPH=$2
  EXE=$3

  export OMP_NUM_THREADS=${NUM_THREADS}
  echo "OMP_NUM_THREADS is $OMP_NUM_THREADS"

  VTUNE_MEMACC_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect memory-access -start-paused \
      -knob sampling-interval=10 -knob analyze-mem-objects=true -knob analyze-openmp=true \
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_memacc \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  #VTUNE_HOTSPOT_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect hotspots -start-paused \
  #    -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_hotspot \
  #    --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  VTUNE_UARCH_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect uarch-exploration -start-paused \
      -knob sampling-interval=10 -knob collect-memory-bandwidth=true
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_uarch \
      --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"

  # do not bind memory to node 0. Let AutoNUMA decide
  NUMACTL_COMMOM="/usr/bin/numactl --cpunodebind=0"

  case $EXE in
    "bfs")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n200
      #clean_cache

      ${VTUNE_MEMACC_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n360  \
          &> ${RESULT_DIR}/${OUTFILE}_memacc_log
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n200
      ;;
    "pr")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n800000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n800000  &
      sleep 900
      /opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_memacc
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i1000 -t1e-4 -n800000  &
      ;;
    "cc")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n18800000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n18800000  &
      sleep 900
      /opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_memacc
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -n18800000  &
      ;;
    "bc")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n400000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n400000  &
      sleep 900
      /opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_memacc
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.sg -i4 -n400000  &
      ;;
    "sssp")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n100000  &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n100000 &
      sleep 900
      /opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_memacc
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}.wsg -d2 -n100000 &
      #sleep 900
      #/opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_uarch
      ;;
    "tc")
      #${VTUNE_HOTSPOT_COMMON} -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n1000000 &
      #clean_cache

      ${VTUNE_MEMACC_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n100000 &
      sleep 900
      /opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_memacc
      clean_cache

      #${VTUNE_UARCH_COMMON}  -- ${NUMACTL_COMMOM} ./${EXE} -f ${GRAPH_DIR}/${GRAPH}U.sg -n100000 &
      #sleep 900
      #/opt/intel/oneapi/vtune/latest/bin64/vtune -command stop -r ${RESULT_DIR}/${OUTFILE}_uarch
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

mkdir -p $RESULT_DIR

## Everything on local node 0 DRAM
#make clean
#make -j
#disable_autonuma
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    run_vtune "${exe}_${graph}_${NUM_THREADS}threads_all_on_node0" $graph $exe
#  done
#done


## AutoNUMA
#make clean
#make -j
#enable_autonuma
#echo "Number of threads: ${OMP_NUM_THREADS}" 
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    run_vtune_autonuma "${exe}_${graph}_${NUM_THREADS}threads_autonuma" $graph $exe
#  done
#done

# Neighbors array on node 1
make clean
make neigh_on_numa1 -j
disable_autonuma
for graph in "${GRAPH_LIST[@]}"
do
  for exe in "${EXE_LIST[@]}"
  do
    clean_cache
    run_vtune "${exe}_${graph}_${NUM_THREADS}threads_neigh_on_numa1" $graph $exe
  done
done


## All data on node 0
#make clean
#make -j
#disable_autonuma
#for graph in "${GRAPH_LIST[@]}"
#do
#  for exe in "${EXE_LIST[@]}"
#  do
#    clean_cache
#    run_vtune "${exe}_${graph}_${NUM_THREADS}threads_all_on_node0" $graph $exe
#  done
#done

