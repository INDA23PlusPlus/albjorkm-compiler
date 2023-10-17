#include <stdint.h>
#include <stdlib.h>

enum VariableTag {
    none,
    number,
    lambda,
};

struct ManagedVariable {
    enum VariableTag tag;
    union {
        int64_t num;
        
    } v;
};

struct HeapVariable {
    struct HeapVariable *previous;
    struct ManagedVariable v;
};

struct GC {
    void *mem;
    void *old_mem;
} gc;

static void *gcAlloc(uint64_t size) {
    // TODO: We leak right now. I will implement a copying gc later.
    return malloc(size);
}

struct ManagedVariable stack[1024];
struct ManagedVariable top;
uint64_t stack_index;

struct ManagedVariable binds[1024];
uint64_t binds_index;

static inline void supStackDup() {
    stack[stack_index] = top;
    stack_index++;
}

static inline void supStackDrop() {
    stack_index--;
    top = stack[stack_index];
}

static inline void supGet(int n) {
    supStackDup();
    top = binds[binds_index - n];
}

static inline void supBind() {
    binds_index++;
    binds[binds_index] = top;
}
