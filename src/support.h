#ifndef SUPPORT_H_
#define SUPPORT_H_
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

/// The support header file contains procedures
/// that are used by the output of the LOL compiler.

typedef int64_t i64;
typedef uint64_t u64;

const char *crash_message = 0;
const char **program_args = 0;
i64 program_args_count = 0;

static inline void fatalError(const char *message) {
    crash_message = message;
#ifndef SUPPORT_IGNORE_FATAL_ERRORS
    fprintf(stderr, "error: %s\n", message);
    exit(1);
#endif
}


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

static const char *call_string_error = "attempted to invoke a string";
static void callStringError() {
    fatalError(call_string_error);
}
struct ManagedType type_string = {
    "string", (const void*)callStringError
};

struct ManagedVariable {
    struct ManagedType *type;
    union ManagedVariableValue {
        i64 number;
        char *string;
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

static inline void supPushString(const char *src) {
    supStackDup();
    top.type = &type_string;
    top.v.string = strdup(src);
}

static inline void supPushLambda(struct ManagedType *lambda_type) {
    supStackDup();
    top.type = lambda_type;
    top.v.context = context_stack;
}

static inline void supBind() {
    binds_index++;
    binds[binds_index] = top;
    supStackDrop();
}

static inline void supBindCaptured() {
    struct HeapVariable *previous_context = context_stack;
    context_stack = gcAlloc(sizeof(struct HeapVariable));
    context_stack->previous = previous_context;
    context_stack->v = top;
    supStackDrop();
}

static inline void supSet(int n) {
    binds[binds_index - n] = top;
    supStackDrop();
}

static inline void supSetCaptured(int n) {
    struct HeapVariable *context = context_stack;
    for(int i = 0; i < n; i++) {
        context = context->previous;
    }
    context->v = top;
    supStackDrop();
}

static inline void supGet(int n) {
    supStackDup();
    top = binds[binds_index - n];
}


static inline void supGetCaptured(int n) {
    struct HeapVariable *context = context_stack;
    for(int i = 0; i < n; i++) {
        context = context->previous;
    }
    supStackDup();
    top = context->v;
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

static inline void supSubtractBuiltin() {
    stack_index--;
    i64 a = stack[stack_index].v.number;
    stack_index--;
    top.type = &type_number;
    top.v.number = stack[stack_index].v.number - a;
}

struct ManagedType sup_builtin_subtract = {
    "subtract", (const void*)supSubtractBuiltin
};

static inline void supEqualsBuiltin() {
    stack_index--;
    i64 a = stack[stack_index].v.number;
    stack_index--;
    top.type = &type_number;
    top.v.number = stack[stack_index].v.number == a;
}

struct ManagedType sup_builtin_equals = {
    "equals", (const void*)supEqualsBuiltin
};

static inline void supBitwiseOrBuiltin() {
    stack_index--;
    i64 a = stack[stack_index].v.number;
    stack_index--;
    top.type = &type_number;
    top.v.number = stack[stack_index].v.number | a;
}

struct ManagedType sup_builtin_bitwise_or = {
    "bitwise_or", (const void*)supBitwiseOrBuiltin
};

static inline void supBitwiseAndBuiltin() {
    stack_index--;
    i64 a = stack[stack_index].v.number;
    stack_index--;
    top.type = &type_number;
    top.v.number = stack[stack_index].v.number & a;
}

struct ManagedType sup_builtin_bitwise_and = {
    "bitwise_and", (const void*)supBitwiseAndBuiltin
};

static inline void supLessThanBuiltin() {
    stack_index--;
    i64 a = stack[stack_index].v.number;
    stack_index--;
    top.type = &type_number;
    top.v.number = stack[stack_index].v.number < a;
}

struct ManagedType sup_builtin_less_than = {
    "less_than", (const void*)supLessThanBuiltin
};

const char *too_few_arguments_error = "attempting to read more program arguments than provided";
static inline void supProgramArgumentBuiltin() {
    stack_index--;
    i64 index = stack[stack_index].v.number;
    supStackDrop();
    if (index < 0 || index >= program_args_count) {
        fatalError(too_few_arguments_error);
    }
    supPushString(program_args[index]);
}

struct ManagedType sup_builtin_program_argument = {
    "program_argument", (const void*)supProgramArgumentBuiltin
};

const char *string_to_number_error = "could not convert string to number";
static inline void supStringToNumberBuiltin() {
    stack_index--;
    char *s = stack[stack_index].v.string;
    if (stack[stack_index].type != &type_string) {
        fatalError(string_to_number_error);
    }
    top.v.number = strtol(s, 0, 0);
    top.type = &type_number;
}

struct ManagedType sup_builtin_string_to_number = {
    "string_to_number", (const void*)supStringToNumberBuiltin
};


static inline void supNumberToStringBuiltin() {
    stack_index--;
    i64 n = stack[stack_index].v.number;
    char into[64];
    snprintf(into, sizeof(into), "%ld", n);
    top.v.string = strdup(into);
    top.type = &type_string;
}

struct ManagedType sup_builtin_number_to_string = {
    "number_to_string", (const void*)supNumberToStringBuiltin
};

static inline void supPutStringBuiltin() {
    stack_index--;
    char *s = stack[stack_index].v.string;
    if (stack[stack_index].type != &type_string) {
        fatalError(string_to_number_error);
    }
    puts(s);
    top.v.number = strlen(s);
    top.type = &type_number;
}

struct ManagedType sup_builtin_put_string = {
    "put_string", (const void*)supPutStringBuiltin
};

#endif
