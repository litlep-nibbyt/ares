#lang racket

(require rackunit)

(define (nock-noun subject formula gates err-k trace)
 (nock-noun-cps subject formula gates err-k trace empty-k))

(define (nock-noun-cps subject formula gates err-k trace k)
 (let*
  [(recur-on-noun (lambda (subject formula k)
    (nock-noun-cps subject formula gates err-k trace k)))
   (recur-on-noun-with-hint (lambda (subject formula hint k)
    (nock-noun-cps subject formula gates err-k (cons hint trace) k)))
   (recur-on-scry-gate (lambda (ref path k)
    (let*
     [(gate (car (car gates)))
      (err-k (car (cdr (car gates))))
      (trace (cdr (cdr (car gates))))
      (gates (cdr gates))
      (core (cons (car gate) (cons (cons ref path) (cdr (cdr gate)))))]
     (nock-noun-cps core (car core) gates err-k trace k))))]
  (match formula
   ([cons (cons (var b) (var c)) (var d)]
    (apply-3 recur-on-noun subject (cons b c)
     (lambda (u)
      (apply-3 recur-on-noun subject d
       (lambda (v)
        (apply-k k (cons u v)))))))
   ([cons 0 (var b)]
    (nock-tree-find-cps subject b err-k trace k))
   ([cons 1 (var b)]
    (apply-k k b))
   ([cons 2 (cons (var b) (var c))]
    (apply-3 recur-on-noun subject b
     (lambda (u)
      (apply-3 recur-on-noun subject c
       (lambda (v)
        (apply-3 recur-on-noun u v k))))))
   ([cons 3 (var b)]
    (apply-3 recur-on-noun subject b
     (lambda (u)
      (if (pair? u) (apply-k k 0) (apply-k k 1)))))
   ([cons 4 (var b)]
    (apply-3 recur-on-noun subject b
     (lambda (u)
      (apply-k k (+ 1 u)))))
   ([cons 5 (cons (var b) (var c))]
    (apply-3 recur-on-noun subject b
     (lambda (u)
      (apply-3 recur-on-noun subject c
       (lambda (v)
        (if (eqv? u v) (apply-k k 0) (apply-k k 1)))))))
   ([cons 6 (cons (var b) (cons (var c) (var d)))]
    (apply-3 recur-on-noun subject b
     (lambda (u)
      (if (= 0 u)
       (apply-3 recur-on-noun subject c k)
       (if (= 1 u)
        (apply-3 recur-on-noun subject d k)
        (err-k (cons 2 trace)))))))
   ([cons 7 (cons (var b) (var c))]
    (apply-3 recur-on-noun subject b
     (lambda (u)
      (apply-3 recur-on-noun u c k))))
   ([cons 8 (cons (var b) (var c))]
    (apply-3 recur-on-noun subject b
     (lambda (u)
      (apply-3 recur-on-noun (cons u subject) c k))))
   ([cons 9 (cons (var b) (var c))]
    (apply-3 recur-on-noun subject c
     (lambda (u)
      (nock-tree-find-cps u b err-k trace
       (lambda (v)
        (apply-3 recur-on-noun u v k))))))
   ([cons 10 (cons (cons (var b) (var c)) (var d))]
    (apply-3 recur-on-noun subject c
     (lambda (u)
      (apply-3 recur-on-noun subject d
       (lambda (v)
        (nock-tree-edit-cps u b v err-k trace k))))))
   ([cons 11 (cons (cons (var b) (var c)) (var d))]
    (apply-3 recur-on-noun subject c
     (lambda (v)
      (if (member b (list (tas "hunk") (tas "hand") (tas "lose") (tas "mean") (tas "spot")))
       (apply-4 recur-on-noun-with-hint subject d (cons b v) k)
       (apply-3 recur-on-noun subject d k)))))
   ([cons 11 (cons (var b) (var c))]
    (apply-3 recur-on-noun subject c k))
   ([cons 12 (cons (var ref) (var path))]
    (apply-3 recur-on-noun subject ref
     (lambda (u)
      (apply-3 recur-on-noun subject path
       (lambda (v)
        (apply-3 recur-on-scry-gate u v
         (lambda (w)
          (if (equal? 0 w)
           ; ~
           (err-k (cons 1 w))
           (if (equal? 0 (cdr v))
            ; [~ ~]
            (err-k (cons 2 (cons (cons (tas "hunk") (cons u v)) trace)))
            (apply-k k (cdr (cdr w)))))))))))))))

(define nock-tree-find-cps
  (lambda (tree address err-k trace k)
    (if (= address 0)
     (err-k (cons 2 trace))
     (if (= address 1)
      (apply-k k tree)
      (if (even? address)
       (nock-tree-find-cps tree (quotient address 2) err-k trace
        (lambda (u)
         (apply-k k (car u))))
       (nock-tree-find-cps tree (quotient address 2) err-k trace
        (lambda (u)
         (apply-k k (cdr u)))))))))

; # operator in nock spec: tree editing
(define nock-tree-edit-cps
  (lambda (subtree address tree err-k trace k)
    (if (= address 0)
     (err-k (cons 2 trace))
     (reverse-address-cps address (lambda (u)
      (nock-tree-edit-reversed-cps subtree u tree k)))))) 

; Transform a nock address into a bitwise reversed address and a depth
; Note that the MSB of the address is always 1, and is *not* a head/tail bit.
; So we discard that one and do not count it in the depth.
; Editing on our representation is then a matter of
; editing the car or cdr of the tree based on whether the LSB is 1 or 0,
; shifting, decrementing the depth, and going around again *until the depth is 0*
;
; note that with several car bits at the bottom of the path (LSB in address, MSB reversed)
; the reversed address will be 0 for several iteraitons at the end, thus we test the depth
; and not the reversed address
(define (reverse-address-cps address k)
 (reverse-address-acc-cps address 0 0 k))

(define (reverse-address-acc-cps address reversed depth k)
 (if (= address 0)
  ; The most-significant bit in the address is a marker for the depth of
  ; the address, not a head/tail flag. We are instead storing the depth separately
  ; in the reversed representation, so we discard it.
  (apply-k k (cons (arithmetic-shift reversed -1) (- depth 1)))
  (let*
   [(top-bit (bitwise-and address 1))
    (reversed (bitwise-ior (arithmetic-shift reversed 1) top-bit))
    (address (arithmetic-shift address -1))
    (depth (+ depth 1))]
   (reverse-address-acc-cps address reversed depth k))))

(define nock-tree-edit-reversed-cps
 (lambda (subtree reversed-depth tree k)
  (let*
   [(reversed (car reversed-depth))
    (depth (cdr reversed-depth))
    (reversed-depth (cons (arithmetic-shift reversed -1) (- depth 1)))]
    (if (= depth 0)
     (apply-k k subtree)
     (if (even? reversed)
      (nock-tree-edit-reversed-cps subtree reversed-depth (car tree)
       (lambda (u)
        (apply-k k (cons u (cdr tree)))))
      (nock-tree-edit-reversed-cps subtree reversed-depth (cdr tree)
       (lambda (u)
        (apply-k k (cons (car tree) u)))))))))

(define (empty-k u) u)

(define (apply-k k^ v) (k^ v))
(define (apply-3 k^ u v w) (k^ u v w))
(define (apply-4 k^ u v w x) (k^ u v w x))

;; macro for %tas literals:
;; converts input string into a numeric literal of that string represented as a %tas, i.e. an
;; atom with the ascii bytes of the string in sequence (first->LSB, last->MSB)
(define-syntax (tas str)
 (quasisyntax
  (unsyntax
   (foldr
    (lambda (char atom) (bitwise-ior (bitwise-and #xFF (char->integer char)) (arithmetic-shift atom 8)))
    0
    (string->list (car (cdr (syntax->datum str))))))))

(define nock-here 1)
(define (nock-car address) (* address 2))
(define (nock-cdr address) (+ 1 (* address 2)))
(define (get-0 x) (cons 0 x))
(define (literal-1 x) (cons 1 x))
(define (eval-2 x y) (cons 2 (cons x y)))
(define (cell?-3 x) (cons 3 x))
(define (inc-4 x) (cons 4 x))
(define (=-5 x y) (cons 5 (cons x y)))
(define (if-6 x y z) (cons 6 (cons x (cons y z))))
(define (compose-7 x y) (cons 7 (cons x y)))
(define (declare-8 x y) (cons 8 (cons x y)))
(define (call-9 x y) (cons 9 (cons x y)))
(define (update-10 x y z) (cons 10 (cons (cons x y) z)))
(define (hint-11 x y) (cons 11 (cons x y)))
(define lootru 0)
(define loofal 1)

(define test-tree (cons (cons 4 5) 3))
(define decrement-4-core
  (cons
   (if-6 (=-5 (get-0 (nock-car (nock-cdr nock-here))) (inc-4 (get-0 (nock-cdr (nock-cdr nock-here)))))
    (get-0 (nock-cdr (nock-cdr nock-here)))
    (call-9 (nock-car nock-here) (update-10 (nock-cdr (nock-cdr nock-here)) (inc-4 (get-0 (nock-cdr (nock-cdr nock-here)))) (get-0 nock-here))))
   (cons 4 0)))

(define (nock-test subject formula) (nock-noun subject formula '() test-err-k '()))

(define (test-err-k err)
 (printf "Error: ~v" err)
 (error 'nock-err))

(check-equal? (nock-test test-tree (get-0 nock-here) ) test-tree "tree address 1")
(check-equal? (nock-test test-tree (get-0 (nock-car nock-here))) (car test-tree) "tree address 2")
(check-equal? (nock-test test-tree (get-0 (nock-cdr nock-here))) (cdr test-tree) "tree address 3")
(check-equal? (nock-test test-tree (get-0 (nock-car (nock-car nock-here)))) (car (car test-tree)) "tree address 4")
(check-equal? (nock-test test-tree (get-0 (nock-cdr (nock-car nock-here)))) (cdr (car test-tree)) "tree address 5")
(check-equal? (nock-test 0 (literal-1 test-tree)) test-tree "literal")
(check-equal? (nock-test 0 (eval-2 (literal-1 test-tree) (literal-1 (get-0 2)))) (car test-tree) "eval")
(check-equal? (nock-test test-tree (cell?-3 (get-0 1))) lootru "test cell true")
(check-equal? (nock-test test-tree (cell?-3 (get-0 3))) loofal "test cell false")
(check-equal? (nock-test 0 (inc-4 (literal-1 0))) 1 "increment")
(check-equal? (nock-test test-tree (=-5 (literal-1 test-tree) (get-0 1))) lootru "test equals true")
(check-equal? (nock-test test-tree (=-5 (literal-1 test-tree) (get-0 2))) loofal "test equals false")
(check-equal? (nock-test test-tree (if-6 (literal-1 lootru) (literal-1 5) (get-0 100))) 5 "test if tru")
(check-equal? (nock-test test-tree (if-6 (literal-1 loofal) (get-0 100) (literal-1 5))) 5 "test if false")
(check-equal? (nock-test 0 (compose-7 (literal-1 test-tree) (get-0 2))) (car test-tree) "test compose")
(check-equal? (nock-test 0 (declare-8 (literal-1 test-tree) (get-0 2))) test-tree "test declare")
(check-equal? (nock-test 0 (call-9 (nock-car nock-here) (literal-1 decrement-4-core))) 3 "test call")
(check-equal? (nock-test 0 (update-10 (nock-cdr nock-here) (literal-1 (cons 6 7)) (literal-1 test-tree))) (cons (cons 4 5) (cons 6 7)) "test update")
(check-equal? (nock-test 0 (call-9 (nock-car nock-here) (update-10 (nock-car (nock-cdr nock-here)) (literal-1 8) (literal-1 decrement-4-core)))) 7 "test slam i.e. update sample and call")
; test 11 static and dynamic