// Copyright (c) 2015, The Regents of the University of California (Regents)
// See LICENSE.txt for license details

#ifndef PVECTOR_H_
#define PVECTOR_H_

#include <algorithm>
#include <numa.h>
#include <memkind.h>


/*
GAP Benchmark Suite
Class:  pvector
Author: Scott Beamer

Vector class with ability to not initialize or do initialize in parallel
 - std::vector (when resizing) will always initialize, and does it serially
 - When pvector is resized, new elements are uninitialized
 - Resizing is not thread-safe
*/
enum MEM_TYPE {REGULAR_DRAM, CXL_DRAM, PMEM};

template <typename T_>
class pvector {
 public:
  typedef T_* iterator;

  pvector() : start_(nullptr), end_size_(nullptr), end_capacity_(nullptr) {}

  explicit pvector(size_t num_elements) {
    start_ = new T_[num_elements];
    end_size_ = start_ + num_elements;
    end_capacity_ = end_size_;
  }

//#ifdef NEIGH_ON_NUMA1 
  pvector(size_t num_elements, MEM_TYPE mem_type, memkind *pmem_kind = NULL) {
    if (mem_type == CXL_DRAM) {
      void *numa_blob = numa_alloc_onnode(num_elements * sizeof(T_), 1);
      std::cout << "[INFO] Allocating pvector on NUMA node 1." << std::endl;
      start_ = new(numa_blob) T_[num_elements];
      end_size_ = start_ + num_elements;
      end_capacity_ = end_size_;
      this->memtype = CXL_DRAM;
    //} else if (mem_type == PMEM) { //  std::cout << "[INFO] Allocating pvector on NUMA node 1." << std::endl;
    //  if (pmem_kind == NULL) {
    //    fprintf(stderr, "memkind pmem_kind is null.\n");
    //    exit(EXIT_FAILURE);
    //  }
    //  this->pmem_kind = pmem_kind;
    //  int memkind_err = memkind_posix_memalign(pmem_kind, (void **)&start_, 64, num_elements * sizeof(T_));
    //  if (memkind_err) {
    //    fprintf(stderr, "ERROR! unable to allocated pvector in pmem\n");
    //    exit(EXIT_FAILURE);
    //  }
    //  printf("[DEBUG] Neighbor array allocation on pmem successful.\n");
    } else {
      std::cout << "[ERROR] pvector memory type " << mem_type << " not supported." << std::endl;
    }
  }
//#endif

  pvector(size_t num_elements, T_ init_val) : pvector(num_elements) {
    fill(init_val);
  }

  pvector(iterator copy_begin, iterator copy_end)
      : pvector(copy_end - copy_begin) {
    #pragma omp parallel for
    for (size_t i=0; i < capacity(); i++)
      start_[i] = copy_begin[i];
  }

  // don't want this to be copied, too much data to move
  pvector(const pvector &other) = delete;

  // prefer move because too much data to copy
  pvector(pvector &&other)
      : start_(other.start_), end_size_(other.end_size_),
        end_capacity_(other.end_capacity_) {
    other.start_ = nullptr;
    other.end_size_ = nullptr;
    other.end_capacity_ = nullptr;
  }

  // want move assignment
  pvector& operator= (pvector &&other) {
    if (this != &other) {
      ReleaseResources();
      start_ = other.start_;
      end_size_ = other.end_size_;
      end_capacity_ = other.end_capacity_;
      other.start_ = nullptr;
      other.end_size_ = nullptr;
      other.end_capacity_ = nullptr;
    }
    return *this;
  }

  void ReleaseResources(){
    if (start_ != nullptr) {
//#if defined(NEIGH_ON_NUMA1)
//      numa_free(start_, this->size() * sizeof(T_));
//#elif defined(NEIGH_ON_NVM)
//      memkind_free(pmem_kind, start_);
//#else 
    if (memtype == REGULAR_DRAM){
      delete[] start_;
    } else if (memtype == CXL_DRAM) {
      std::cout << "[INFO] Freeing pvector allocated on CXL DRAM." << std::endl;
      numa_free(start_, this->size() * sizeof(T_));
    }
//#endif
    }
  }

  ~pvector() {
    ReleaseResources();
  }

  // not thread-safe
  void reserve(size_t num_elements) {
    if (num_elements > capacity()) {
      T_ *new_range = new T_[num_elements];
      #pragma omp parallel for
      for (size_t i=0; i < size(); i++)
        new_range[i] = start_[i];
      end_size_ = new_range + size();
      delete[] start_;
      start_ = new_range;
      end_capacity_ = start_ + num_elements;
    }
  }

  // prevents internal storage from being freed when this pvector is desctructed
  // - used by Builder to reuse an EdgeList's space for in-place graph building
  void leak() {
    start_ = nullptr;
  }

  bool empty() {
    return end_size_ == start_;
  }

  void clear() {
    end_size_ = start_;
  }

  void resize(size_t num_elements) {
    reserve(num_elements);
    end_size_ = start_ + num_elements;
  }

  T_& operator[](size_t n) {
    return start_[n];
  }

  const T_& operator[](size_t n) const {
    return start_[n];
  }

  void push_back(T_ val) {
    if (size() == capacity()) {
      size_t new_size = capacity() == 0 ? 1 : capacity() * growth_factor;
      reserve(new_size);
    }
    *end_size_ = val;
    end_size_++;
  }

  void fill(T_ init_val) {
    #pragma omp parallel for
    for (T_* ptr=start_; ptr < end_size_; ptr++)
      *ptr = init_val;
  }

  size_t capacity() const {
    return end_capacity_ - start_;
  }

  size_t size() const {
    return end_size_ - start_;
  }

  iterator begin() const {
    return start_;
  }

  iterator end() const {
    return end_size_;
  }

  T_* data() const {
    return start_;
  }

  void swap(pvector &other) {
    std::swap(start_, other.start_);
    std::swap(end_size_, other.end_size_);
    std::swap(end_capacity_, other.end_capacity_);
  }


 private:
  T_* start_;
  T_* end_size_;
  T_* end_capacity_;
  static const size_t growth_factor = 2;
  struct memkind *pmem_kind;
  MEM_TYPE memtype = REGULAR_DRAM;
};

#endif  // PVECTOR_H_
