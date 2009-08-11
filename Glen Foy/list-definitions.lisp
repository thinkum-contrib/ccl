;;;-*-Mode: LISP; Package: LIST-DEFINITIONS -*-;;; ----------------------------------------------------------------------------;;;;;;      list-definitions.lisp, version 0.1b1;;;;;;      copyright © 2009 Glen Foy;;;      (Permission is granted to Clozure, Inc. to distribute this file.);;;;;;      This code adds a dynamic contextual popup menu to Hemlock.;;;;;;      Control-Click produces an alphabetized listing of the file's definitions.  ;;;      Control-Command-Click produces a positional listing.;;;;;;      If you have a two button mouse, you would just use Right-Click and ;;;      Command-Right-Click, respectively.  (Option-Right-Click produces ;;;      the standard contextual menu.);;;;;;      The most recent version will be available at: www.clairvaux.org;;;;;;      This software is offered "as is", without warranty of any kind.;;;;;; ----------------------------------------------------------------------------(defpackage "LIST-DEFINITIONS" (:nicknames "LDefs") (:use :cl :ccl))(in-package "LIST-DEFINITIONS")(defParameter *objc-defmethod-search-pattern* (hi::new-search-pattern :string-insensitive :forward "(objc:defmethod"))(defParameter *def-search-pattern* (hi::new-search-pattern :string-insensitive :forward "(def"))(defParameter *left-paren-search-pattern* (hi::new-search-pattern :character :forward #\())(defParameter *colon-search-pattern* (hi::new-search-pattern :character :forward #\:))(defParameter *slash-search-pattern* (hi::new-search-pattern :character :forward #\/))(defmacro clone (mark) `(hi::copy-mark ,mark :temporary))(defun active-hemlock-window ()  (gui::first-window-satisfying-predicate    #'(lambda (w)       (and (typep w 'gui::hemlock-frame)            (not (typep w 'gui::hemlock-listener-frame))            (#/isKeyWindow w)))));;; ----------------------------------------------------------------------------;;;(defclass list-definitions-menu (ns:ns-menu)  ((menu-text-view :initarg :menu-text-view :reader menu-text-view))  (:metaclass ns:+ns-object))(objc:defmethod (#/listDefinitionsAction: :void) ((m list-definitions-menu) (sender :id))  (let* ((def-pos (hi::mark-absolute-position (definition-mark sender)))         (def-end-pos (let ((temp-mark (clone (definition-mark sender))))                        (when (hemlock::form-offset temp-mark 1)                          (hi::mark-absolute-position temp-mark)))))    (when (and def-pos def-end-pos)      (ns:with-ns-range (range def-pos (- def-end-pos def-pos))        (#/scrollRangeToVisible: (menu-text-view m) range))      (hi::move-mark (hi::buffer-point (gui::hemlock-buffer (menu-text-view m))) (definition-mark sender))      (gui::update-paren-highlight (menu-text-view m)))));;; ----------------------------------------------------------------------------;;;(defclass list-definitions-menu-item (ns:ns-menu-item)  ((definition-mark :accessor definition-mark))  (:metaclass ns:+ns-object));;; This is not retained -- assumming autorelease.(defun list-definitions-context-menu (view &optional alpha-p)  (let* ((menu (make-instance 'list-definitions-menu :menu-text-view view))         (window (active-hemlock-window))         (alist (when window (list-definitions window alpha-p)))         menu-item)    (dolist (entry alist)      (setq menu-item (#/initWithTitle:action:keyEquivalent:                        (#/alloc list-definitions-menu-item)                       (ccl::%make-nsstring (if (listp (car entry))                                              (second (car entry))                                              (car entry)))                       (ccl::@selector "listDefinitionsAction:")                       #@""))      (setf (definition-mark menu-item) (cdr entry))      (#/setTarget: menu-item  menu)      (#/addItem: menu menu-item))    menu))(objc:defmethod #/menuForEvent: ((view gui::hemlock-text-view) (event :id))  (if (logtest #$NSAlternateKeyMask (#/modifierFlags event))    (gui::text-view-context-menu)    (if (logtest #$NSCommandKeyMask (#/modifierFlags event))      (list-definitions-context-menu view nil)      (list-definitions-context-menu view t))));;; This includes definitions in sharp-stroke comments.  We'll claim it's a feature.(defun list-definitions (hemlock &optional alpha-p)  (labels ((compare-names (name-1 name-2) (string-lessp name-1 name-2))           (get-name (entry)             (let ((name (car entry)))               (if (listp name) (first name) name)))           (get-defs (mark pattern &optional objc-p)             (do ((def-found-p (hi::find-pattern mark pattern)                               (hi::find-pattern mark pattern))                  alist)                 ((not def-found-p) (when alist                                      (if alpha-p                                         (sort alist #'compare-names :key #'get-name)                                         (nreverse alist))))               (when (zerop (hi::mark-charpos mark))                  (let ((definition-signature (definition-signature (clone mark) objc-p)))                   (when definition-signature                     (push (cons definition-signature (hi::line-start (clone mark))) alist))))               (hi::line-end mark))))    (let* ((pane (slot-value hemlock 'gui::pane))           (text-view (gui::text-pane-text-view pane))           (buffer (gui::hemlock-buffer text-view))           (def-mark (clone (hi::buffer-start-mark buffer)))           (objc-mark (clone (hi::buffer-start-mark buffer)))           (def-alist (get-defs def-mark *def-search-pattern*))           (objc-alist (get-defs objc-mark *objc-defmethod-search-pattern* t)))      (when objc-alist        (setq def-alist              (if alpha-p                (merge 'list def-alist objc-alist #'compare-names :key #'get-name)                (merge 'list def-alist objc-alist #'hi::mark< :key #'cdr))))      def-alist)))(defun definition-signature (mark &optional objc-p)  (let* ((method-p (unless objc-p                     (string-equal "(defmethod"                                    (hi::region-to-string                                     (hi::region mark (hi::character-offset (clone mark) 10))))))         (end (let ((temp-mark (clone mark)))                (when (hemlock::form-offset (hi::mark-after temp-mark) 2)                  temp-mark)))         (start (when end                  (let ((temp-mark (clone end)))                    (when (hemlock::form-offset temp-mark -1)                      temp-mark)))))    (when (and start end)      (let ((name (hi::region-to-string (hi::region start end))))        (cond (method-p               (let ((qualifier-start-mark (clone end))                     (left-paren-mark (clone end))                     right-paren-mark qualifier-end-mark param-string qualifier-string)                 (when (hi::find-pattern left-paren-mark *left-paren-search-pattern*)                   (setq right-paren-mark (clone left-paren-mark))                   (when (hemlock::form-offset right-paren-mark 1)                     (setq param-string (parse-parameters (clone left-paren-mark) right-paren-mark))))                 (when (hi::find-pattern qualifier-start-mark *colon-search-pattern* left-paren-mark)                   (setq qualifier-end-mark (clone qualifier-start-mark))                   (when (hemlock::form-offset qualifier-end-mark 1)                     (setq qualifier-string                           (hi::region-to-string (hi::region qualifier-start-mark qualifier-end-mark)))))                 (if qualifier-string                   ;; Returning a list, with name in the car, to simplify alpha sort:                   (list name (format nil "(~A ~A ~A)" name qualifier-string param-string))                   (list name (format nil "(~A ~A)" name param-string)))))              (objc-p               (let* ((name-start-mark (let ((temp-mark (clone start)))                                         (when (hi::find-pattern temp-mark *slash-search-pattern*)                                           (hi::mark-after temp-mark))))                      (name-end-mark (when name-start-mark                                       (let ((temp-mark (clone name-start-mark)))                                         (when (hemlock::form-offset temp-mark 1)                                           temp-mark))))                      (objc-name (when (and name-start-mark name-end-mark)                                    (hi::region-to-string (hi::region name-start-mark name-end-mark))))                      (left-paren-mark (let ((temp-mark (clone end)))                                          (when (hi::find-pattern temp-mark *left-paren-search-pattern*)                                            temp-mark)))                      (right-paren-mark (when left-paren-mark                                           (let ((temp-mark (clone left-paren-mark)))                                            (when (hi::form-offset temp-mark 1)                                              temp-mark))))                      param-string)                 (when (and left-paren-mark right-paren-mark)                   (setq param-string (parse-parameters left-paren-mark right-paren-mark t))                   ;; Using curly braces to distinguish objc methods from Lisp methods:                   (list objc-name (format nil "{~A ~A}" objc-name param-string)))))              (t               name))))))(defun parse-parameters (start-mark end-mark &optional objc-p)  (let (specializers-processed-p)    (flet ((get-param (start end)             (let ((next-character (hi::next-character start)))               (when (char= next-character #\&) (setq specializers-processed-p t))               (cond ((and (char= next-character #\() (not specializers-processed-p))                      (let* ((specializer-end (when (hemlock::form-offset (hi::mark-after start) 2) start))                             (specializer-start (when specializer-end (clone specializer-end))))                        (when (and specializer-end specializer-start                                   (hemlock::form-offset specializer-start -1)                                   (hi::mark< specializer-end end))                          (when objc-p (setq specializers-processed-p t))                          (hi::region-to-string (hi::region specializer-start specializer-end)))))                     (t                       (unless (char= next-character #\&)                        (format nil "t")))))))      (do* ((sexp-end (let ((temp-mark (hi::mark-after (clone start-mark))))                        (when (hemlock::form-offset temp-mark 1) temp-mark))                      (when (hemlock::form-offset (hi::mark-after sexp-end) 1) sexp-end))            (sexp-start (when sexp-end                          (let ((temp-mark (clone sexp-end)))                            (when (hemlock::form-offset temp-mark -1) temp-mark)))                        (when sexp-end                          (let ((temp-mark (clone sexp-end)))                            (when (hemlock::form-offset temp-mark -1) temp-mark))))            (param-string (when (and sexp-start sexp-end) (get-param (clone sexp-start)                                                                      (clone sexp-end)))                          (when (and sexp-start sexp-end) (get-param (clone sexp-start)                                                                     (clone sexp-end))))            (first-param-p t)            parameters)           ((or (null sexp-start) (null sexp-end)                 (hi::mark> sexp-start end-mark)                ;; Empty body case:                (hi::mark< sexp-start start-mark))            (concatenate 'string parameters ")"))        (when param-string          (cond (first-param-p                 (setq parameters (concatenate 'string "(" param-string))                 (setq first-param-p nil))                (t                 (setq parameters (concatenate 'string parameters " " param-string)))))))))  #|(defun test-list-definitions ()  (let* ((window (active-hemlock-window))         (alist (when window (list-definitions window))))    (dolist (entry alist)      (format t "~%~%~S" (car entry))      (format t "~%~S" (cdr entry)))))(gui::execute-in-gui  'test-list-definitions)|#      