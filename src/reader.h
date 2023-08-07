// Copyright (c) 2015, The Regents of the University of California (Regents)
// See LICENSE.txt for license details

#ifndef READER_H_
#define READER_H_

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <type_traits>
#include <numa.h>
#include <memkind.h>
#include <fcntl.h>
#include <unistd.h>

#include "pvector.h"
#include "util.h"


/*
GAP Benchmark Suite
Class:  Reader
Author: Scott Beamer

Given filename, returns an edgelist or the entire graph (if serialized)
 - Intended to be called from Builder
 - Determines file format from the filename's suffix
 - If the input graph is serialized (.sg or .wsg), reads the graph
   directly into the returned graph instance
 - Otherwise, reads the file and returns an edgelist
*/


#define PMEM_MAX_SIZE (1024L * 1024L * 1024L * 100L) // 100GB


template <typename NodeID_, typename DestID_ = NodeID_,
          typename WeightT_ = NodeID_, bool invert = true>
class Reader {
  typedef EdgePair<NodeID_, DestID_> Edge;
  typedef pvector<Edge> EdgeList;
  std::string filename_;

 public:
  explicit Reader(std::string filename) : filename_(filename) {}

  std::string GetSuffix() {
    std::size_t suff_pos = filename_.rfind('.');
    if (suff_pos == std::string::npos) {
      std::cout << "Could't find suffix of " << filename_ << std::endl;
      std::exit(-1);
    }
    return filename_.substr(suff_pos);
  }

  EdgeList ReadInEL(std::ifstream &in) {
    EdgeList el;
    NodeID_ u, v;
    while (in >> u >> v) {
      el.push_back(Edge(u, v));
    }
    return el;
  }

  EdgeList ReadInWEL(std::ifstream &in) {
    EdgeList el;
    NodeID_ u;
    NodeWeight<NodeID_, WeightT_> v;
    while (in >> u >> v) {
      el.push_back(Edge(u, v));
    }
    return el;
  }

  // Note: converts vertex numbering from 1..N to 0..N-1
  EdgeList ReadInGR(std::ifstream &in) {
    EdgeList el;
    char c;
    NodeID_ u;
    NodeWeight<NodeID_, WeightT_> v;
    while (!in.eof()) {
      c = in.peek();
      if (c == 'a') {
        in >> c >> u >> v;
        el.push_back(Edge(u - 1, NodeWeight<NodeID_, WeightT_>(v.v-1, v.w)));
      } else {
        in.ignore(200, '\n');
      }
    }
    return el;
  }

  // Note: converts vertex numbering from 1..N to 0..N-1
  EdgeList ReadInMetis(std::ifstream &in, bool &needs_weights) {
    EdgeList el;
    NodeID_ num_nodes, num_edges;
    char c;
    std::string line;
    bool read_weights = false;
    while (true) {
      c = in.peek();
      if (c == '%') {
        in.ignore(200, '\n');
      } else {
        std::getline(in, line, '\n');
        std::istringstream header_stream(line);
        header_stream >> num_nodes >> num_edges;
        header_stream >> std::ws;
        if (!header_stream.eof()) {
          int32_t fmt;
          header_stream >> fmt;
          if (fmt == 1) {
            read_weights = true;
          } else if ((fmt != 0) && (fmt != 100)) {
            std::cout << "Do not support METIS fmt type: " << fmt << std::endl;
            std::exit(-20);
          }
        }
        break;
      }
    }
    NodeID_ u = 0;
    while (u < num_nodes) {
      c = in.peek();
      if (c == '%') {
        in.ignore(200, '\n');
      } else {
        std::getline(in, line);
        if (line != "") {
          std::istringstream edge_stream(line);
          if (read_weights) {
            NodeWeight<NodeID_, WeightT_> v;
            while (edge_stream >> v >> std::ws) {
              v.v -= 1;
              el.push_back(Edge(u, v));
            }
          } else {
            NodeID_ v;
            while (edge_stream >> v >> std::ws) {
              el.push_back(Edge(u, v - 1));
            }
          }
        }
        u++;
      }
    }
    needs_weights = !read_weights;
    return el;
  }

  // Note: converts vertex numbering from 1..N to 0..N-1
  // Note: weights casted to type WeightT_
  EdgeList ReadInMTX(std::ifstream &in, bool &needs_weights) {
    EdgeList el;
    std::string start, object, format, field, symmetry, line;
    in >> start >> object >> format >> field >> symmetry >> std::ws;
    if (start != "%%MatrixMarket") {
      std::cout << ".mtx file did not start with %%MatrixMarket" << std::endl;
      std::exit(-21);
    }
    if ((object != "matrix") || (format != "coordinate")) {
      std::cout << "only allow matrix coordinate format for .mtx" << std::endl;
      std::exit(-22);
    }
    if (field == "complex") {
      std::cout << "do not support complex weights for .mtx" << std::endl;
      std::exit(-23);
    }
    bool read_weights;
    if (field == "pattern") {
      read_weights = false;
    } else if ((field == "real") || (field == "double") ||
               (field == "integer")) {
      read_weights = true;
    } else {
      std::cout << "unrecognized field type for .mtx" << std::endl;
      std::exit(-24);
    }
    bool undirected;
    if (symmetry == "symmetric") {
      undirected = true;
    } else if ((symmetry == "general") || (symmetry == "skew-symmetric")) {
      undirected = false;
    } else {
      std::cout << "unsupported symmetry type for .mtx" << std::endl;
      std::exit(-25);
    }
    while (true) {
      char c = in.peek();
      if (c == '%') {
        in.ignore(200, '\n');
      } else {
        break;
      }
    }
    int64_t m, n, nonzeros;
    in >> m >> n >> nonzeros >> std::ws;
    if (m != n) {
      std::cout << m << " " << n << " " << nonzeros << std::endl;
      std::cout << "matrix must be square for .mtx" << std::endl;
      std::exit(-26);
    }
    while (std::getline(in, line)) {
      if (line.empty())
        continue;
      std::istringstream edge_stream(line);
      NodeID_ u;
      edge_stream >> u;
      if (read_weights) {
        NodeWeight<NodeID_, WeightT_> v;
        edge_stream >> v;
        v.v -= 1;
        el.push_back(Edge(u - 1, v));
        if (undirected)
          el.push_back(Edge(v.v, NodeWeight<NodeID_, WeightT_>(u - 1, v.w)));
      } else {
        NodeID_ v;
        edge_stream >> v;
        el.push_back(Edge(u - 1, v - 1));
        if (undirected)
          el.push_back(Edge(v - 1, u - 1));
      }
    }
    needs_weights = !read_weights;
    return el;
  }

  EdgeList ReadFile(bool &needs_weights) {
    Timer t;
    t.Start();
    EdgeList el;
    std::string suffix = GetSuffix();
    std::ifstream file(filename_);
    if (!file.is_open()) {
      std::cout << "Couldn't open file " << filename_ << std::endl;
      std::exit(-2);
    }
    if (suffix == ".el") {
      el = ReadInEL(file);
    } else if (suffix == ".wel") {
      needs_weights = false;
      el = ReadInWEL(file);
    } else if (suffix == ".gr") {
      needs_weights = false;
      el = ReadInGR(file);
    } else if (suffix == ".graph") {
      el = ReadInMetis(file, needs_weights);
    } else if (suffix == ".mtx") {
      el = ReadInMTX(file, needs_weights);
    } else {
      std::cout << "Unrecognized suffix: " << suffix << std::endl;
      std::exit(-3);
    }
    file.close();
    t.Stop();
    PrintTime("Read Time", t.Seconds());
    return el;
  }

  CSRGraph<NodeID_, DestID_, invert> ReadSerializedGraph() {
    bool weighted = GetSuffix() == ".wsg";
    if (!std::is_same<NodeID_, SGID>::value) {
      std::cout << "serialized graphs only allowed for 32bit" << std::endl;
      std::exit(-5);
    }
    if (!weighted && !std::is_same<NodeID_, DestID_>::value) {
      std::cout << ".sg not allowed for weighted graphs" << std::endl;
      std::exit(-5);
    }
    if (weighted && std::is_same<NodeID_, DestID_>::value) {
      std::cout << ".wsg only allowed for weighted graphs" << std::endl;
      std::exit(-5); }
    if (weighted && !std::is_same<WeightT_, SGID>::value) {
      std::cout << ".wsg only allowed for int32_t weights" << std::endl;
      std::exit(-5);
    }
    std::ifstream file(filename_);
    if (!file.is_open()) {
      std::cout << "Couldn't open file " << filename_ << std::endl;
      std::exit(-6);
    }
#if defined(NEIGH_ON_NVM)
    // Setup persistent memory (NVM)
    char pmem_path[100] = "/pmem0p1/";
    std::cout << "[DEBUG] Running memkind test" << std::endl;
    int status = memkind_check_dax_path(pmem_path);
    if (!status) {
        std::cout << pmem_path << " is on DAX-enabled file system." << std::endl;
    } else {
        std::cout << "ERORR: " << pmem_path << " is not on DAX-enabled file system." << std::endl;
        std::exit(-5);
    }

    int memkind_err = 0;
    struct memkind *pmem_kind = NULL;
    memkind_err = memkind_create_pmem(pmem_path, PMEM_MAX_SIZE, &pmem_kind);
    if (memkind_err) {
        char error_message[MEMKIND_ERROR_MESSAGE_SIZE];
        memkind_error_message(memkind_err, error_message, MEMKIND_ERROR_MESSAGE_SIZE);
        //fprintf(stderr, "%s\n", error_message);
        std::cout << "ERROR: Failed to create pmem pool: " << error_message << std::endl;
        std::exit(-5);
    }
#endif

    Timer t;
    t.Start();
    bool directed;
    SGOffset num_nodes, num_edges;
    DestID_ **index = nullptr, **inv_index = nullptr;
    DestID_ *neighs = nullptr, *inv_neighs = nullptr;
    file.read(reinterpret_cast<char*>(&directed), sizeof(bool));
    file.read(reinterpret_cast<char*>(&num_edges), sizeof(SGOffset));
    file.read(reinterpret_cast<char*>(&num_nodes), sizeof(SGOffset));
    pvector<SGOffset> offsets(num_nodes+1);
    
#if defined(NEIGH_ON_NUMA1)
    // Allocate on NUMA node 1
    std::cout << "[INFO] Allocating neighbors array on NUMA node 1." << std::endl;
    void *numa_blob_neighs = numa_alloc_onnode(num_edges * sizeof(DestID_), 1);
    neighs = new(numa_blob_neighs) DestID_[num_edges];
#elif defined(NEIGH_ON_NVM)
    // Allocate on NVM
    std::cout << "[INFO] Allocating neighbors array on NVM of size " << num_edges * sizeof(DestID_) << std::endl;
    //void *nvm_blob_neighs = memkind_malloc(pmem_kind, num_edges * sizeof(DestID_));
    //neighs = new(nvm_blob_neighs) DestID_[num_edges];
    //neighs = static_cast<DestID_ *>(memkind_malloc(pmem_kind, num_edges * sizeof(DestID_)));
    memkind_err = memkind_posix_memalign(pmem_kind, (void **)&neighs, 64, num_edges * sizeof(DestID_));
    //memkind_err = memkind_posix_memalign(MEMKIND_DEFAULT, (void **)&neighs, 64, num_edges * sizeof(DestID_));
    if (memkind_err) {
      fprintf(stderr, "ERROR! unable to allocated neigh memory in pmem\n");
      exit(EXIT_FAILURE);
    }
    printf("[DEBUG] Neighbor array allocation on pmem successful.\n");
#else
    neighs = new DestID_[num_edges];
#endif

    std::streamsize num_index_bytes = (num_nodes+1) * sizeof(SGOffset);
    std::streamsize num_neigh_bytes = num_edges * sizeof(DestID_);
    file.read(reinterpret_cast<char*>(offsets.data()), num_index_bytes);
    file.read(reinterpret_cast<char*>(neighs), num_neigh_bytes);
    index = CSRGraph<NodeID_, DestID_>::GenIndex(offsets, neighs);
    if (directed && invert) {
#if defined(NEIGH_ON_NUMA1)
      // Allocate on NUMA node 1
      std::cout << "[INFO] Allocating inv neighbors array on NUMA node 1." << std::endl;
      void *numa_blob_inv_neighs = numa_alloc_onnode(num_edges * sizeof(DestID_), 1);
      inv_neighs = new(numa_blob_inv_neighs) DestID_[num_edges];
#elif defined(NEIGH_ON_NVM)
      // Allocate on NVM
      std::cout << "[INFO] Allocating inv neighbors array on NVM." << std::endl;
      //void *nvm_blob_inv_neighs = memkind_malloc(pmem_kind, num_edges * sizeof(DestID_));
      //inv_neighs = new(nvm_blob_inv_neighs) DestID_[num_edges];
      //inv_neighs = static_cast<DestID_ *>(memkind_malloc(pmem_kind, num_edges * sizeof(DestID_)));
      memkind_err = memkind_posix_memalign(pmem_kind, (void **)&inv_neighs, 64, num_edges * sizeof(DestID_));
      //memkind_err = memkind_posix_memalign(MEMKIND_DEFAULT, (void **)&inv_neighs, 64, num_edges * sizeof(DestID_));
      if (memkind_err) {
        fprintf(stderr, "ERROR! unable to allocated inv_neigh memory in pmem\n");
        exit(EXIT_FAILURE);
      }
      printf("[DEBUG] Inv neighbor array allocation on pmem successful.\n");
#else
      inv_neighs = new DestID_[num_edges];
#endif
      file.read(reinterpret_cast<char*>(offsets.data()), num_index_bytes);
      file.read(reinterpret_cast<char*>(inv_neighs), num_neigh_bytes);
      inv_index = CSRGraph<NodeID_, DestID_>::GenIndex(offsets, inv_neighs);
    }
    file.close();
    t.Stop();
    PrintTime("Read Time", t.Seconds());

    //printf("Now that the graph is loaded into memory, clearing page cache... \n");
    //int drop_caches_fd = open("/proc/sys/vm/drop_caches", O_WRONLY);
    //write(drop_caches_fd, "1", 1);
    //close(drop_caches_fd);
    //printf("Clear page cache done. \n");

#if defined(NEIGH_ON_NVM)
    size_t stats_active;
    size_t stats_resident;
    size_t stats_allocated;
    memkind_update_cached_stats();
    memkind_get_stat(pmem_kind, MEMKIND_STAT_TYPE_RESIDENT, &stats_resident);
    memkind_get_stat(pmem_kind, MEMKIND_STAT_TYPE_ACTIVE, &stats_active);
    memkind_get_stat(pmem_kind, MEMKIND_STAT_TYPE_ALLOCATED, &stats_allocated);
    fprintf(stdout, "memkind stats: resident %zu ,active %zu, allocated %zu \n",
            stats_resident, stats_active, stats_allocated);

    if (directed)
      return CSRGraph<NodeID_, DestID_, invert>(num_nodes, index, neighs,
                                                inv_index, inv_neighs, pmem_kind);
    else
      return CSRGraph<NodeID_, DestID_, invert>(num_nodes, index, neighs, pmem_kind);
#else
    if (directed)
      return CSRGraph<NodeID_, DestID_, invert>(num_nodes, index, neighs,
                                                inv_index, inv_neighs);
    else
      return CSRGraph<NodeID_, DestID_, invert>(num_nodes, index, neighs);
#endif
  }
};

#endif  // READER_H_
