(in-package "CCL")

(defx8632lapfunction %fixnum-signum ((number arg_z))
  (mov ($ '-1) (% temp0))
  (mov ($ '1) (% temp1))
  (test (% number) (% number))
  (cmovs (% temp0) (% arg_z))
  (cmovns (% temp1) (% arg_z))
  (single-value-return))

;;; see %logcount.
(defx86lapfunction %ilogcount ((number arg_z))
  (mark-as-imm temp0)
  (let ((rshift imm0)
        (temp temp0))
    (unbox-fixnum number rshift)
    (xor (% arg_z) (% arg_z))
    (test (% rshift) (% rshift))
    (jmp @test)
    @next
    (lea (@ -1 (% rshift)) (% temp))
    (and (% temp) (% rshift))		;sets flags
    (lea (@ '1 (% arg_z)) (% arg_z))    ;doesn't set flags
    @test
    (jne @next))
  (mark-as-node temp0)
  (single-value-return))

;;; might be able to get away with not marking ecx as imm.
(defx8632lapfunction %iash ((number arg_y) (count arg_z))
  (mark-as-imm ecx)			;aka temp0
  (unbox-fixnum count ecx)
  (test (% count) (% count))
  (jge @left)
  (negb (% cl))
  (unbox-fixnum number imm0)
  (sar (% cl) (% imm0))
  (box-fixnum imm0 arg_z)
  (mark-as-node ecx)
  (single-value-return)
  @left
  (shl (% cl) (% number))
  (movl (% number) (% arg_z))
  (mark-as-node ecx)
  (single-value-return))

(defparameter *double-float-zero* 0.0d0)
(defparameter *short-float-zero* 0.0s0)

(defx8632lapfunction %sfloat-hwords ((sfloat arg_z))
  (movl (% esp) (% temp0))
  (movzwl (@ (+ 2 x8632::misc-data-offset) (% sfloat)) (% imm0))
  (box-fixnum imm0 temp1)
  (pushl (% temp1))			;high
  (movzwl (@ x8632::misc-data-offset (% sfloat)) (% imm0))
  (box-fixnum imm0 temp1)
  (pushl (% temp1))			;low
  (set-nargs 2)
  (jmp-subprim .SPvalues))

(defx8632lapfunction %fixnum-intlen ((number arg_z))
  (mark-as-imm temp0)
  (let ((imm1 temp0))
    (unbox-fixnum arg_z imm0)
    (mov (% imm0) (% imm1))
    (not (% imm1))
    (test (% imm0) (% imm0))
    (cmovs (% imm1) (% imm0))
    (bsrl (% imm0) (% imm0))
    (setne (%b imm1))
    (addb (%b imm1) (%b imm0))
    (box-fixnum imm0 arg_z))
  (mark-as-node temp0)
  (single-value-return))

;;; Caller guarantees that result fits in a fixnum.
(defx8632lapfunction %truncate-double-float->fixnum ((arg arg_z))
  (get-double-float arg fp1)
  (cvttsd2si (% fp1) (% imm0))
  (box-fixnum imm0 arg_z)  
  (single-value-return))

(defx8632lapfunction %truncate-short-float->fixnum ((arg arg_z))
  (get-single-float arg fp1)
  (cvttss2si (% fp1) (% imm0))
  (box-fixnum imm0 arg_z)  
  (single-value-return))

;;; DOES round to even
(defx8632lapfunction %round-nearest-double-float->fixnum ((arg arg_z))
  (get-double-float arg fp1)
  (cvtsd2si (% fp1) (% imm0))
  (box-fixnum imm0 arg_z)  
  (single-value-return))

(defx8632lapfunction %round-nearest-short-float->fixnum ((arg arg_z))
  (get-single-float arg fp1)
  (cvtss2si (% fp1) (% imm0))
  (box-fixnum imm0 arg_z)  
  (single-value-return))

;;; We'll get a SIGFPE if divisor is 0.
(defx8632lapfunction %fixnum-truncate ((dividend arg_y) (divisor arg_z))
  (mark-as-imm temp0)
  (mark-as-imm temp1)
  (let ((imm2 temp0)
	(imm1 temp1))			;edx
    (unbox-fixnum dividend imm0)
    (unbox-fixnum divisor imm2)
    (cltd)				;edx:eax = sign_extend(eax)
    (idivl (% imm2))
    (box-fixnum imm0 arg_z)		;quotient
    (box-fixnum imm1 arg_y))		;remainder
  (mark-as-node temp0)
  (mark-as-node temp1)
  (movl (% esp) (% temp0))
  (push (% arg_z))
  (push (% arg_y))
  (set-nargs 2)
  (jmp-subprim .SPvalues))

(defx8632lapfunction called-for-mv-p ()
  (movl (@ x8632::lisp-frame.return-address (% ebp)) (% imm0))
  (cmpl (% imm0) (@ (+ (target-nil-value) (x8632::kernel-global ret1valaddr))))
  (movl ($ (target-t-value)) (% imm0))
  (movl ($ (target-nil-value)) (% arg_z))
  (cmove (% imm0) (% arg_z))
  (single-value-return))

(defx8632lapfunction %next-random-pair ((high arg_y) (low arg_z))
  ;; high: (unsigned-byte 15)
  ;; low: (unsigned-byte 16)
  (unbox-fixnum low imm0)
  ;; clear most significant bit
  (shll ($ (1+ (- 16 x8632::fixnumshift))) (% high))
  (shrl ($ 1) (% high))
  (orl (% high) (% imm0))
  (mark-as-imm edx)
  (movl ($ 48271) (% edx))
  (mul (% edx))
  (mark-as-node edx)
  (movl ($ (- #x10000)) (% high))	;#xffff0000
  (andl (% imm0) (% high))
  (shrl ($ (- 16 x8632::fixnumshift)) (% high))
  (shll ($ 16) (% imm0))
  (shrl ($ (- 16 x8632::fixnumshift)) (% imm0))
  (movl (% imm0) (% low))
  (movl (% esp) (% temp0))
  (push (% high))
  (push (% low))
  (set-nargs 2)
  (jmp-subprim .SPvalues))
	
;;; n1 and n2 must be positive (esp non zero)
(defx86lapfunction %fixnum-gcd ((boxed-u arg_y) (boxed-v arg_z))
  (mark-as-imm temp0)
  (mark-as-imm temp1)
  (let ((u imm0)
	(v temp1)
	(k temp0))			;temp0 = ecx
    (xorl (% k) (% k))
    (bsfl (% boxed-u) (% u))
    (bsfl (% boxed-v) (% v))
    (rcmp (% u) (% v))
    (cmovlel (%l u) (%l k))
    (cmovgl (%l v) (%l k))
    (unbox-fixnum boxed-u u)
    (unbox-fixnum boxed-v v)
    (subb ($ x8632::fixnumshift) (%b k))
    (jz @start)
    (shrl (% cl) (% u))
    (shrl (% cl) (% v))
    @start
    ;; At least one of u or v is odd at this point
    @loop
    ;; if u is even, shift it right one bit
    (testb ($ 1) (%b u))
    (jne @u-odd)
    (shrl ($ 1) (% u))
    (jmp @test)
    @u-odd
    ;; if v is even, shift it right one bit
    (testb ($ 1) (%b v))
    (jne @both-odd)
    (shrl ($ 1) (% v))
    (jmp @test-u)
    @both-odd
    (cmpl (% v) (% u))
    (jb @v>u)
    (subl (% v) (% u))
    (shrl ($ 1) (% u))
    (jmp @test)
    @v>u
    (subl (% u) (% v))
    (shrl ($ 1) (% v))
    @test-u
    (testl (% u) (% u))
    @test
    (ja @loop)
    (shll (% cl) (% v))
    (movb ($ 0) (% cl))
    (box-fixnum v arg_z))
  (mark-as-node temp0)
  (mark-as-node temp1)
  (single-value-return))
