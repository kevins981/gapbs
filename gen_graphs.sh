#!/bin/bash


##### urand graphs
./converter -u28 -k16 -m -b benchmark/graphs/urand_28.sg
#./converter -u29 -k16 -m -b benchmark/graphs/urand_29.sg
#./converter -u30 -k16 -m -b benchmark/graphs/urand_30.sg

### weighted for SSSP
./converter -u28 -k16 -wb benchmark/graphs/urand_28.wsg
#./converter -u29 -k16 -wb benchmark/graphs/urand_29.wsg
#./converter -u30 -k16 -wb benchmark/graphs/urand_30.wsg

##### kron graphs
#./converter -g28 -k16 -m -b benchmark/graphs/kron_28.sg
#./converter -g29 -k16 -m -b benchmark/graphs/kron_29.sg
#./converter -g30 -k16 -m -b benchmark/graphs/kron_30.sg

### weighted for SSSP
./converter -g28 -k16 -wb benchmark/graphs/kron_28.wsg
#./converter -g29 -k16 -wb benchmark/graphs/kron_29.wsg
#./converter -g30 -k16 -wb benchmark/graphs/kron_30.wsg

