#!/bin/bash

export OMP_PROC_BIND=false
#export OMP_PROC_BIND=true
export OMP_NUM_THREADS=32
#export OMP_PLACES=“{0}:8:1,{32}:8:1”
export OMP_PLACES=""

### Twitter + PR

/opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect performance-snapshot -data-limit=5000 --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_pr_twitter/pr_twitter_perfsnap -- /usr/bin/numactl --membind=0 --cpunodebind=0 /ssd1/songxin8/thesis/graph/gapbs/pr -f benchmark/graphs/twitter.sg -i1000 -t1e-4 -n16

/opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect hotspots -data-limit=5000 --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_pr_twitter/pr_twitter_hotspot -- /usr/bin/numactl --membind=0 --cpunodebind=0 /ssd1/songxin8/thesis/graph/gapbs/pr -f benchmark/graphs/twitter.sg -i1000 -t1e-4 -n16

/opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-access -knob sampling-interval=10 -knob analyze-mem-objects=true -knob analyze-openmp=true -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_pr_twitter/pr_twitter_memacc --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 /ssd1/songxin8/thesis/graph/gapbs/pr -f benchmark/graphs/twitter.sg -i1000 -t1e-4 -n16

/opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect memory-consumption -knob mem-object-size-min-thres=1024 -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_pr_twitter/pr_twitter_memconsump --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 /ssd1/songxin8/thesis/graph/gapbs/pr -f benchmark/graphs/twitter.sg -i1000 -t1e-4 -n16

/opt/intel/oneapi/vtune/2022.3.0/bin64/vtune -collect io -data-limit=5000 -result-dir /ssd1/songxin8/thesis/graph/vtune/gap_pr_twitter/pr_twitter_io --app-working-dir=/ssd1/songxin8/thesis/graph/gapbs -- /usr/bin/numactl --membind=0 --cpunodebind=0 /ssd1/songxin8/thesis/graph/gapbs/pr -f benchmark/graphs/twitter.sg -i1000 -t1e-4 -n16

