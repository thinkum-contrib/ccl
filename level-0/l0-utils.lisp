; -*- Mode: Lisp;  Package: CCL; -*-
;;;
;;;   Copyright (C) 1994-2001 Digitool, Inc
;;;   This file is part of OpenMCL.  
;;;
;;;   OpenMCL is licensed under the terms of the Lisp Lesser GNU Public
;;;   License , known as the LLGPL and distributed with OpenMCL as the
;;;   file "LICENSE".  The LLGPL consists of a preamble and the LGPL,
;;;   which is distributed with OpenMCL as the file "LGPL".  Where these
;;;   conflict, the preamble takes precedence.  
;;;
;;;   OpenMCL is referenced in the preamble as the "LIBRARY."
;;;
;;;   The LLGPL is also available online at
;;;   http://opensource.franz.com/preamble.html



; l0-utils.lisp


(in-package "CCL")

(defun %proclaim-notspecial (sym)
  (%symbol-bits sym (logandc2 (%symbol-bits sym) (ash 1 $sym_bit_special))))



;;; We MAY need a scheme for finding all of the areas in a lisp library.
(defun %map-areas (function &optional (maxcode area-dynamic) (mincode area-readonly))
  (declare (fixnum maxcode mincode))
  (do* ((a (%normalize-areas) (%lisp-word-ref a (ash target::area.succ (- target::fixnumshift))))
        (code area-dynamic (%lisp-word-ref a (ash target::area.code (- target::fixnumshift))))
        (dynamic t nil))
       ((= code area-void))
    (declare (fixnum code))
    (if (and (<= code maxcode)
             (>= code mincode))
      (if dynamic 
        (walk-dynamic-area a function)
        (unless (= code area-dynamic)        ; ignore egc areas, 'cause walk-dynamic-area sees them.
          (walk-static-area a function))))))


;;; there'll be functions in static lib areas.
;;; (Well, there would be if there were really static lib areas.)

(defun %map-lfuns (f)
  (let* ((filter #'(lambda (obj) (when (= (the fixnum (typecode obj))
                                          target::subtag-function)
                                   (funcall f (lfun-vector-lfun obj))))))
    (declare (dynamic-extent filter))
    (%map-areas filter area-dynamic area-managed-static)))


(defun ensure-simple-string (s)
  (cond ((simple-string-p s) s)
        ((stringp s)
         (let* ((len (length s))
                (new (make-string len :element-type 'base-char)))
           (declare (fixnum len)(optimize (speed 3)(safety 0)))
           (multiple-value-bind (ss offset) (array-data-and-offset s)
             (%copy-ivector-to-ivector ss (ash offset 2) new 0 (ash len 2)))
           new))
        (t (report-bad-arg s 'string))))

(defun nremove (elt list)
  (let* ((handle (cons nil list))
         (splice handle))
    (declare (dynamic-extent handle))
    (loop
      (if (eq elt (car (%cdr splice)))
        (unless (setf (%cdr splice) (%cddr splice)) (return))
        (unless (cdr (setq splice (%cdr splice)))
          (return))))
    (%cdr handle)))


(eval-when (:compile-toplevel :execute)
  #+32-bit-target
  (defmacro need-use-eql-macro (key)
    `(let* ((typecode (typecode ,key)))
       (declare (fixnum typecode))
       (or (= typecode target::subtag-macptr)
           (and (>= typecode target::min-numeric-subtag)
                (<= typecode target::max-numeric-subtag)))))
  #+64-bit-target
  (defmacro need-use-eql-macro (key)
    `(let* ((typecode (typecode ,key)))
       (declare (fixnum typecode))
      (cond ((= typecode target::tag-fixnum) t)
            ((= typecode target::subtag-single-float) t)
            ((= typecode target::subtag-bignum) t)
            ((= typecode target::subtag-double-float) t)
            ((= typecode target::subtag-ratio) t)
            ((= typecode target::subtag-complex) t)
            ((= typecode target::subtag-macptr) t))))

)

(defun asseql (item list)
  (if (need-use-eql-macro item)
    (dolist (pair list)
      (if pair
	(if (eql item (car pair))
	  (return pair))))
    (assq item list)))

(defun assequal (item list)
  (dolist (pair list)
    (if pair
      (if (equal item (car pair))
        (return pair)))))


;;; (memeql item list) <=> (member item list :test #'eql :key #'identity)
(defun memeql (item list)
  (if (need-use-eql-macro item)
    (do* ((l list (%cdr l)))
         ((endp l))
      (when (eql (%car l) item) (return l)))
    (memq item list)))

(defun memequal (item list)
  (do* ((l list (%cdr l)))
       ((endp l))
    (when (equal (%car l) item) (return l))))


; (member-test item list test-fn) 
;   <=> 
;     (member item list :test test-fn :key #'identity)
(defun member-test (item list test-fn)
  (if (or (eq test-fn 'eq)(eq test-fn  #'eq)
          (and (or (eq test-fn 'eql)(eq test-fn  #'eql))
               (not (need-use-eql-macro item))))
    (do* ((l list (cdr l)))
         ((null l))
      (when (eq item (car l))(return l)))
    (if (or (eq test-fn 'eql)(eq test-fn  #'eql))
      (do* ((l list (cdr l)))
           ((null l))
        (when (eql item (car l))(return l)))    
      (do* ((l list (cdr l)))
           ((null l))
        (when (funcall test-fn item (car l)) (return l))))))

(defun s32->u32 (s32)
  (%stack-block ((buf 4))
    (setf (%get-signed-long buf) s32)
    (%get-unsigned-long buf)))

(defun u32->s32 (u32)
  (%stack-block ((buf 4))
    (setf (%get-unsigned-long buf) u32)
    (%get-signed-long buf)))


; end