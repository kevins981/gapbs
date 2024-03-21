# See LICENSE.txt for license details.

CXX_FLAGS += -std=c++14 -O3 -Wall -g
#CXX_FLAGS += -std=c++11 -O0 -Wall -g
PAR_FLAG = -fopenmp
LIBS = -lnuma

VTUNE_HOME= /opt/intel/oneapi/vtune/latest
#INCLUDES += -I${BIGMEMBENCH_COMMON_PATH}/tinylfu

ifneq ($(VTUNE_HOME),)
  CXX_FLAGS +=  -DVTUNE_ANALYSIS=1
  INCLUDES += -I${VTUNE_HOME}/include
  LIBS +=-L${VTUNE_HOME}/lib64 -littnotify
  LIBS +=-ldl
endif

ifneq (,$(findstring icpc,$(CXX)))
	PAR_FLAG = -openmp
endif

ifneq (,$(findstring sunCC,$(CXX)))
	CXX_FLAGS = -std=c++11 -xO3 -m64 -xtarget=native
	PAR_FLAG = -xopenmp
endif

ifneq ($(SERIAL), 1)
	CXX_FLAGS += $(PAR_FLAG)
endif

KERNELS = bc bfs cc cc_sv pr pr_spmv sssp tc
SUITE = $(KERNELS) converter

.PHONY: all
all: $(SUITE)

.PHONY: neigh_on_numa1
neigh_on_numa1: CXX_FLAGS += -DNEIGH_ON_NUMA1
neigh_on_numa1: all

.PHONY: tinylfu
tinylfu: CXX_FLAGS += -DTINYLFU
tinylfu: all

.PHONY: neigh_on_nvm
neigh_on_nvm: CXX_FLAGS += -DNEIGH_ON_NVM
neigh_on_nvm: LIBS += -lmemkind
neigh_on_nvm: all

% : src/%.cc src/*.h
	$(CXX) $(CXX_FLAGS) $(INCLUDES) $< -o $@ $(LIBS)

# Testing
include test/test.mk

# Benchmark Automation
include benchmark/bench.mk


.PHONY: clean
clean:
	rm -f $(SUITE) test/out/*
