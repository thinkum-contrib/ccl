;;;
;;; Copyright 2009 Clozure Associates
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(in-package "GUI")

(defclass xapropos-window-controller (ns:ns-window-controller)
  ((row-objects :foreign-type :id :reader row-objects)
   (search-category :initform :all :accessor search-category)
   (matched-symbols :initform (make-array 100 :fill-pointer 0 :adjustable t)
                    :accessor matched-symbols)
   (external-only-p :initform nil :accessor external-only-p)
   ;; outlets
   (action-menu :foreign-type :id :accessor action-menu)
   (action-popup-button :foreign-type :id :accessor action-popup-button)
   (search-field :foreign-type :id :accessor search-field)
   (search-field-toolbar-item :foreign-type :id :accessor search-field-toolbar-item)
   (all-symbols-button :foreign-type :id :accessor all-symbols-button)
   (external-symbols-button :foreign-type :id :accessor external-symbols-button)
   (table-view :foreign-type :id :accessor table-view)
   (contextual-menu :foreign-type :id :accessor contextual-menu))
  (:metaclass ns:+ns-object))

(defclass scope-bar-view (ns:ns-view)
  ()
  (:metaclass ns:+ns-object))

(defconstant $scope-bar-border-width 1)

;;; This should use a gradient, but we don't have NSGradient on Tiger.

(objc:defmethod (#/drawRect: :void) ((self scope-bar-view) (rect #>NSRect))
  (let* (;;(start-color (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.75 1.0))
         (end-color (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.90 1.0))
         (border-color (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.69 1.0))
         (bounds (#/bounds self)))
    (#/set end-color)
    (#_NSRectFill bounds)
    (ns:with-ns-rect (r 0 0 (ns:ns-rect-width bounds) $scope-bar-border-width)
      (#/set border-color)
      (#_NSRectFill r))))

(defconstant $all-symbols-item-tag 0)

(defvar *apropos-categories*
  '((0 . :all)
    (1 . :function)
    (2 . :variable)
    (3 . :class)
    (4 . :macro))
  "Associates search menu item tags with keywords.")

(objc:defmethod #/init ((wc xapropos-window-controller))
  (let ((self (#/initWithWindowNibName: wc #@"xapropos")))
    (unless (%null-ptr-p self)
      (setf (slot-value self 'row-objects) (make-instance 'ns:ns-mutable-array)))
    self))

(defun make-action-popup (menu)
  (ns:with-ns-rect (r 0 0 44 23)
    (let* ((button (make-instance 'ns:ns-pop-up-button :with-frame r :pulls-down t))
           (item (#/itemAtIndex: menu 0))
           (image-name (if (post-tiger-p) #@"NSActionTemplate" #@"gear")))
      (#/setBezelStyle: button #$NSTexturedRoundedBezelStyle)
      ;; This looks bad on Tiger: the arrow is in the bottom corner of the button.
      #-cocotron                        ; no setArrowPosition
      (#/setArrowPosition: (#/cell button) #$NSPopUpArrowAtBottom)
      (#/setImage: item (#/imageNamed: ns:ns-image image-name))
      (#/setMenu: button menu)
      (#/synchronizeTitleAndSelectedItem button)
      button)))

(objc:defmethod (#/windowDidLoad :void) ((wc xapropos-window-controller))
  (#/setDoubleAction: (table-view wc) (@selector #/inspect:))
  (setf (action-popup-button wc) (make-action-popup (action-menu wc)))
  (let* ((toolbar (make-instance 'ns:ns-toolbar :with-identifier #@"apropos toolbar")))
    (#/setDisplayMode: toolbar #$NSToolbarDisplayModeIconOnly)
    (#/setDelegate: toolbar wc)
    (#/setToolbar: (#/window wc) toolbar)
    (#/release toolbar)
    (#/search: wc (search-field wc))
    (#/makeFirstResponder: (#/window wc) (search-field wc))))

(objc:defmethod #/toolbarAllowedItemIdentifiers: ((wc xapropos-window-controller) toolbar)
  (declare (ignore toolbar))
  (#/arrayWithObjects: ns:ns-array #@"action-popup-button"
                       #&NSToolbarFlexibleSpaceItemIdentifier #@"search-field" +null-ptr+))

(objc:defmethod #/toolbarDefaultItemIdentifiers: ((wc xapropos-window-controller) toolbar)
  (declare (ignore toolbar))
  (#/arrayWithObjects: ns:ns-array #@"action-popup-button"
                       #&NSToolbarFlexibleSpaceItemIdentifier #@"search-field" +null-ptr+))

(objc:defmethod #/toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:
                ((wc xapropos-window-controller) toolbar identifier (flag #>BOOL))
  (declare (ignore toolbar))
  (let* ((toolbar-item (make-instance 'ns:ns-toolbar-item :with-item-identifier identifier)))
    (#/autorelease toolbar-item)
    (with-slots (action-popup-button search-field) wc
      (cond ((#/isEqualToString: identifier #@"action-popup-button")
             (#/setMinSize: toolbar-item (pref (#/frame action-popup-button) #>NSRect.size))
             (#/setMaxSize: toolbar-item (pref (#/frame action-popup-button) #>NSRect.size))
             (#/setView: toolbar-item action-popup-button))
            ((#/isEqualToString: identifier #@"search-field")
             (#/setMinSize: toolbar-item (pref (#/frame search-field) #>NSRect.size))
             (#/setMaxSize: toolbar-item (pref (#/frame search-field) #>NSRect.size))
             (#/setView: toolbar-item search-field))
          (t
           (setq toolbar-item +null-ptr+))))
    toolbar-item))

(objc:defmethod (#/dealloc :void) ((wc xapropos-window-controller))
  (#/release (slot-value wc 'row-objects))
  (call-next-method))

(objc:defmethod (#/search: :void) ((wc xapropos-window-controller) sender)
  (let* ((substring (#/stringValue sender)))
    ;;(#_NSLog #@"search for %@" :id substring)
    (apropos-search wc (lisp-string-from-nsstring substring))))

(defun apropos-search (wc substring)
  (with-accessors ((v matched-symbols)
                   (category search-category)
                   (array row-objects)) wc
    (setf (fill-pointer v) 0)
    (flet ((maybe-include-symbol (sym)
             (when (case category
                     (:function (fboundp sym))
                     (:variable (boundp sym))
                     (:macro (macro-function sym))
                     (:class (find-class sym nil))
                     (t t))
               (when (ccl::%apropos-substring-p substring (symbol-name sym))
                 (vector-push-extend sym v)))))
      (if (external-only-p wc)
        (dolist (p (list-all-packages))
          (do-external-symbols (sym p)
            (maybe-include-symbol sym)))
        (do-all-symbols (sym)
          (maybe-include-symbol sym))))
    (setf v (sort v #'string-lessp))
    (#/removeAllObjects array)
    (let ((n (#/null ns:ns-null)))
      (dotimes (i (length v))
        (#/addObject: array n))))
  (#/reloadData (table-view wc)))

(objc:defmethod (#/setSearchCategory: :void) ((wc xapropos-window-controller) sender)
  (let* ((tag (#/tag sender))
         (label (if (= tag $all-symbols-item-tag)
                  #@"Search"
                  (#/stringWithFormat: ns:ns-string #@"Search (%@)" (#/title sender))))
         (pair (assoc tag *apropos-categories*)))
    (when pair
      (let* ((items (#/itemArray (#/menu sender))))
        (dotimes (i (#/count items))
          (#/setState: (#/objectAtIndex: items i) #$NSOffState)))
      (#/setState: sender #$NSOnState)
      (#/setLabel: (search-field-toolbar-item wc) label)
      (setf (search-category wc) (cdr pair))
      (#/search: wc (search-field wc)))))

(objc:defmethod (#/toggleExternalOnly: :void) ((wc xapropos-window-controller) sender)
  (cond ((eql sender (all-symbols-button wc))
         (#/setState: (external-symbols-button wc) #$NSOffState)
         (setf (external-only-p wc) nil))
        ((eql sender (external-symbols-button wc))
         (#/setState: (all-symbols-button wc) #$NSOffState)
         (setf (external-only-p wc) t)))
  (#/search: wc (search-field wc)))
  
(objc:defmethod (#/inspect: :void) ((wc xapropos-window-controller) sender)
  (declare (ignore sender))
  (let* ((row (#/selectedRow (table-view wc)))
         (clicked-row (#/clickedRow (table-view wc))))
    (when (/= clicked-row -1)
      (setq row clicked-row))
    (inspect (aref (matched-symbols wc) row))))

(objc:defmethod (#/source: :void) ((wc xapropos-window-controller) sender)
  (declare (ignore sender))
  (let* ((row (#/selectedRow (table-view wc)))
         (clicked-row (#/clickedRow (table-view wc))))
    (when (/= clicked-row -1)
      (setq row clicked-row))
    (hemlock::edit-definition (aref (matched-symbols wc) row))))

(objc:defmethod (#/validateMenuItem: #>BOOL) ((wc xapropos-window-controller) menu-item)
  (cond ((or (eql (action-menu wc) (#/menu menu-item))
             (eql (contextual-menu wc) (#/menu menu-item)))
         (let ((row (#/selectedRow (table-view wc)))
               (clicked-row (#/clickedRow (table-view wc)))
               (tag (#/tag menu-item)))
           (when (/= clicked-row -1)
             (setq row clicked-row))
           (when (/= row -1)
             (cond ((= tag $inspect-item-tag) t)
                   ((= tag $source-item-tag)
                    (let ((sym (aref (matched-symbols wc) row)))
                      (edit-definition-p sym)))
                   (t nil)))))
        (t t)))

(objc:defmethod (#/numberOfRowsInTableView: #>NSInteger) ((wc xapropos-window-controller)
                                                          table-view)
  (declare (ignore table-view))
  (length (matched-symbols wc)))

(objc:defmethod #/tableView:objectValueForTableColumn:row: ((wc xapropos-window-controller)
                                                            table-view table-column
                                                            (row #>NSInteger))
  (declare (ignore table-view table-column))
  (with-accessors ((array row-objects)
                   (syms matched-symbols)) wc
    (when (eql (#/objectAtIndex: array row) (#/null ns:ns-null))
      (let ((name (%make-nsstring (prin1-to-string (aref syms row)))))
        (#/replaceObjectAtIndex:withObject: array row name)
        (#/release name)))
    (#/objectAtIndex: array row)))
