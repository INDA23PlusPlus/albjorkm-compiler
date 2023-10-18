#ifndef SUPPORT_H_
#define SUPPORT_H_
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

/// The support header file contains procedures
/// that are used by the output of the LOL compiler.

const char *crash_message = 0;

static inline void fatalError(const char *message) {
    crash_message = message;
#ifndef SUPPORT_IGNORE_FATAL_ERRORS
    fprintf(stderr, "error: %s\n", message);
    exit(1);
#endif
}

typedef int64_t i64;
typedef uint64_t u64;

struct ManagedType {
    const char *name;
    void const (*func)();
};


static const char *call_number_error = "attempted to invoke a number";
static void callNumberError() {
    fatalError(call_number_error);
}
struct ManagedType type_number = {
    "number", (const void*)callNumberError
};

struct ManagedVariable {
    struct ManagedType *type;
    union ManagedVariableValue {
        i64 number;
        void *context;
    } v;
};

struct HeapVariable {
    struct HeapVariable *previous;
    struct ManagedVariable v;
};
struct HeapVariable *context_stack = 0;

struct GC {
    void *mem;
    void *old_mem;
} gc;

static void *gcAlloc(u64 size) {
    // TODO: We leak right now. I will implement a copying gc later.
    return malloc(size);
}

struct ManagedVariable stack[1024];
struct ManagedVariable top;
unsigned int stack_index = 0;

struct ManagedVariable binds[1024];
typedef unsigned int BindsIndex;
BindsIndex binds_index = 0;


static inline void supStackDup() {
    stack[stack_index] = top;
    stack_index++;
}

static inline void supStackDrop() {
    stack_index--;
    top = stack[stack_index];
}

static inline void supPushNumber(i64 n) {
    supStackDup();
    top.type = &type_number;
    top.v.number = n;
}

static inline void supPushLambda(struct ManagedType *lambda_type) {
    supStackDup();
    top.type = lambda_type;
    top.v.context = context_stack;
}

static inline void supGet(int n) {
    supStackDup();
    top = binds[binds_index - n];
}

static inline void supBind() {
    binds_index++;
    binds[binds_index] = top;
    supStackDrop();
}

static inline void supGetCaptured(int n) {
    struct HeapVariable *context = context_stack;
    for(int i = 0; i < n; i++) {
        context = context->previous;
    }
    supStackDup();
    top = context->v;
}

static inline void supBindCaptured() {
    struct HeapVariable *previous_context = context_stack;
    context_stack = gcAlloc(sizeof(struct HeapVariable));
    context_stack->previous = previous_context;
    context_stack->v = top;
    supStackDrop();
}

static inline void supCall() {
    top.type->func();
}

static inline void supAddBuiltin() {
    stack_index--;
    i64 a = stack[stack_index].v.number;
    stack_index--;
    top.type = &type_number;
    top.v.number = a + stack[stack_index].v.number;
}

struct ManagedType sup_builtin_add = {
    "add", (const void*)supAddBuiltin
};

#endif
