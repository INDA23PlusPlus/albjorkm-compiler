#include <stdint.h>

void do_stuff(uint64_t *context_ptr) {
    uint64_t context[4];
    context[0] = 1;
    context[1] = (uint64_t)context_ptr;
    context[2] = 2;
    context[3] = 0;
    context_ptr = context;

    context_ptr = move_current_context_to_heap(context_ptr);
}

int main(int argc, const char *args) {
}
