;;; This code is adapted from the webkit example and with help 
;;; from Richard Cook and Gary Byers on the OpenMCL list.
;;; Things have changed since then, and it's hopefully easier
;;; to use add-on Cocoa frameworks than it once was.
;;; All this does is to try to make it possible to use AddressBook

(in-package ccl)


(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "COCOA"))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (objc:load-framework "AddressBook" :addressbook))

;;; Now, someone should write some code which tries to
;;; actually -use- AddessBook, perhaps via Bosco.  It's
;;; probably easier to experiment with AddressBook if
;;; the demo IDE is loaded.
