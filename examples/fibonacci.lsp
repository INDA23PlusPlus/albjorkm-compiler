; run using: cat examples/fibonacci.lsp | zig build run | gcc -g3 -I src -xc -
(lambda (N)
  (let (fib (lambda (n) (if (< n 2) (if (= n 0) 0 1) (+ (fib (- n 1)) (fib (- n 2))))))
   (put-str (num-to-str (fib (str-to-num (prog-arg 1)))))))
