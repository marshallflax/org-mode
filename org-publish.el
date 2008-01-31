;;; org-publish.el --- publish related org-mode files as a website

;; Copyright (C) 2006  David O'Toole

;; Author: David O'Toole <dto@gnu.org>
;; Keywords: hypermedia, outlines
;; Version: 

;; $Id: org-publish.el,v 1.61 2006/05/19 12:03:51 dto Exp $

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; This file is NOT part of GNU Emacs. 

;;; Commentary:

;; Requires at least version 4.27 of org.el
;;
;; The official org-mode website:
;; http://staff.science.uva.nl/~dominik/Tools/org/
;;
;; Home page for org-publish.el:
;; http://dto.freeshell.org/notebook/OrgMode.html

;; This program extends the HTML publishing support of Emacs Org-mode
;; to allow configurable publishing of related sets of files as a
;; complete website.
;;
;; org-publish.el can do the following: 
;;
;; + Publish all one's org-files to html
;; + Upload html, images, attachments and other files to a web server
;; + Exclude selected private pages from publishing
;; + Publish a clickable index of pages
;; + Manage local timestamps, for publishing only changed files
;; + Accept plugin functions to extend range of publishable content
;;
;; Special thanks to the org-mode maintainer Carsten Dominik for his
;; ideas, enthusiasm, and cooperation.

;;; Installation: 

;; Put org-publish.el in your load path, byte-compile it, and then add
;; the following lines to your emacs initialization file:

;; (autoload 'org-publish "org-publish" nil t)
;; (autoload 'org-publish "org-publish-all" nil t)
;; (autoload 'org-publish "org-publish-current-file" nil t)
;; (autoload 'org-publish "org-publish-current-project" nil t)

;;; Usage: 
;;
;; The program's main configuration variable is
;; `org-publish-project-alist'. See below for example configurations
;; with commentary.

;; The main interactive functions are: 
;;
;; M-x org-publish
;; M-x org-publish-all
;; M-x org-publish-current-file
;; M-x org-publish-current-project

;;;; Simple example configuration:

;; (setq org-publish-project-alist
;;       (list 
;;        '("org" . (:base-directory "~/org/"
;; 		     :base-extension "org"
;; 		     :publishing-directory "~/public_html"
;;                   :with-section-numbers nil
;; 		     :table-of-contents nil
;; 		     :style "<link rel=stylesheet href=\"../other/mystyle.css\" type=\"text/css\">")))

;;;; More complex example configuration:

;; Imagine your *.org files are kept in ~/org, your images in
;; ~/images, and stylesheets in ~/other. Now imagine you want to
;; publish the files through an ssh connection to a remote host, via
;; Tramp-mode. To maintain relative links from *.org files to /images
;; and /other, we should replicate the same directory structure in
;; your web server account's designated html root (in this case,
;; assumed to be ~/html)

;; Once you've done created the proper directories, you can adapt the
;; following example configuration to your specific paths, run M-x
;; org-publish-all, and it should publish the files to the correct
;; directories on the web server, transforming the *.org files into
;; HTML, and leaving other files alone.  

;; (setq org-publish-project-alist
;;       (list 
;;        '("website" . 
;;            (("orgfiles" :base-directory "~/org/"
;; 		           :base-extension "org"
;; 		           :publishing-directory "/ssh:user@host:~/html/notebook/"
;; 		           :publishing-function org-publish-org-to-html
;; 		           :exclude "PrivatePage.org"   ;; regexp
;; 		           :headline-levels 3
;;                         :with-section-numbers nil
;; 		           :table-of-contents nil
;; 		           :style "<link rel=stylesheet href=\"../other/mystyle.css\" type=\"text/css\">"
;; 		           :auto-preamble t
;; 		           :auto-postamble nil)
;;      
;;            ("images" :base-directory "~/images/"
;; 		        :base-extension "jpg\\|gif\\|png"
;; 		        :publishing-directory "/ssh:user@host:~/html/images/"
;; 		        :publishing-function org-publish-attachment)
;;  
;;            ("other"  :base-directory "~/other/"
;; 	   	        :base-extension "css"
;; 		        :publishing-directory "/ssh:user@host:~/html/other/"
;; 		        :publishing-function org-publish-attachment)))))

;; For more information, see the documentation for the variable
;; `org-publish-project-alist'.

;; Of course, you don't have to publish to remote directories from
;; within emacs. You can always just publish to local folders, and
;; then use the synchronization/upload tool of your choice.


;;; List of user-visible changes since version 1.27

;; 1.57: Timestamps flag is now called "org-publish-use-timestamps-flag"
;; 1.52: Properly set default for :index-filename
;; 1.48: Composite projects allowed.
;;       :include keyword allowed.
;; 1.43: Index no longer includes itself in the index. 
;; 1.42: Fix "function definition is void" error
;;       when :publishing-function not set in org-publish-current-file.
;; 1.41: Fixed bug where index isn't published on first try.
;; 1.37: Added interactive function "org-publish". Prompts for particular
;;       project name to publish.
;; 1.34: Added force-publish option to all interactive functions.
;; 1.32: Fixed "index.org has changed on disk" error during index publishing.
;; 1.30: Fixed startup error caused by (require 'em-unix)

;;; Code:

;; these lines get code for function "eshell/cp" loaded
(require 'eshell) 
(require 'esh-maint)
(require 'em-unix)
(require 'org)

(defgroup org-publish nil
	"Options for publishing a set of Org-mode and related files."
   :tag "Org Publishing"
   :group 'org)


(defcustom org-publish-project-alist nil 
  "Association list to control publishing behavior.
Each element of the alist is a publishing 'project.'  The CAR of
each element is a string, uniquely identifying the project. The
CDR of each element is either a property list with configuration
options for the publishing process (see below), or a list of the
following form:

  ((\"component1\" :property value :property value ... )
   (\"component2\" :property value :property value ... ))

When the CDR of an element of org-publish-project-alist is in
this second form, the elements of this list are taken to be
components of the project, which group together files requiring
different publishing options.

When a property is given a value in org-publish-project-alist, its
setting overrides the value of the corresponding user variable
 (if any) during publishing. However, options set within a file
override everything.

Most properties are optional, but some should always be set:
  
    :base-directory        Directory containing publishing source files
    :base-extension        Extension (without the dot!) of source files.
                             This can be a regular expression.
    :publishing-directory  Directory (possibly remote) where output
                             files will be published

The :exclude property may be used to prevent certain files from
being published. Its value may be a string or regexp matching
file names you don't want to be published.

The :include property may be used to include extra files. Its
value may be a list of filenames to include. The filenames are
considered relative to the publishing directory.

When both :include and :exclude properties are given values, the
exclusion step happens first. 

One special property controls which back-end function to use for
publishing files in the project. This can be used to extend the
set of file types publishable by org-publish, as well as the set
of output formats.

    :publishing-function   Function to publish file. The default is
                             org-publish-org-to-html, but other
                             values are possible.

Some properties control details of the Org publishing process,
and are equivalent to the corresponding user variables listed in
the right column. See the documentation for those variables to
learn more about their use and default values.

    :language              org-export-default-language
    :headline-levels       org-export-headline-levels
    :section-numbers       org-export-with-section-numbers
    :table-of-contents     org-export-with-toc
    :emphasize             org-export-with-emphasize
    :sub-superscript       org-export-with-sub-superscripts
    :TeX-macros            org-export-with-TeX-macros
    :fixed-width           org-export-with-fixed-width
    :tables                org-export-with-tables
    :table-auto-headline   org-export-highlight-first-table-line
    :style                 org-export-html-style
    :convert-org-links     org-export-html-link-org-files-as-html
    :inline-images         org-export-html-inline-images
    :expand-quoted-html    org-export-html-expand
    :timestamp             org-export-html-with-timestamp
    :publishing-directory  org-export-publishing-directory
    :preamble              org-export-html-preamble
    :postamble             org-export-html-postamble
    :auto-preamble         org-export-html-auto-preamble
    :auto-postamble        org-export-html-auto-postamble
    :author                user-full-name
    :email                 user-mail-address

The following properties may be used to control publishing of an
index of files or summary page for a given project.

    :auto-index            Whether to publish an index during 
                           org-publish-current-project or org-publish-all.
    :index-filename        Filename for output of index. Defaults
                           to 'index.org' (which becomes 'index.html')
    :index-title           Title of index page. Defaults to name of file.
    :index-function        Plugin function to use for generation of index.
                           Defaults to 'org-publish-org-index', which 
                           generates a plain list of links to all files
                           in the project. 
"
  :group 'org-publish
  :type 'alist)


(defcustom org-publish-use-timestamps-flag t
  "When non-nil, use timestamp checking to publish only changed files. 
When nil, do no timestamp checking and always publish all
files."
  :group 'org-publish
  :type 'boolean)


(defcustom org-publish-timestamp-directory "~/.org-timestamps/" 
  "Name of directory in which to store publishing timestamps."
  :group 'org-publish
  :type 'string)


;;;; Timestamp-related functions


(defun org-publish-timestamp-filename (filename)
  "Return path to timestamp file for filename FILENAME."
  (while (string-match "~\\|/" filename)
    (setq filename (replace-match "_" nil t filename)))
  (concat org-publish-timestamp-directory filename ".timestamp"))


(defun org-publish-needed-p (filename) 
  "Check whether file should be published. 
If org-publish-use-timestamps-flag is set to nil, this function always
returns t. Otherwise, check the timestamps folder to determine
whether file should be published."
  (if org-publish-use-timestamps-flag
      (progn
	;;
	;; create folder if needed
	(if (not (file-exists-p org-publish-timestamp-directory))
	    (make-directory org-publish-timestamp-directory)
	  (if (not (file-directory-p org-publish-timestamp-directory))
	      (error "org-publish-timestamp-directory must be a directory.")))
	;;
	;; check timestamp. ok if timestamp file doesn't exist
	(let* ((timestamp (org-publish-timestamp-filename filename))
	       (rtn (file-newer-than-file-p filename timestamp)))
	  (if rtn 
	      ;; handle new timestamps
	      (if (not (file-exists-p timestamp))
		  ;; create file
		  (with-temp-buffer
		    (write-file timestamp)
		    (kill-buffer (current-buffer)))))
	  rtn))
    t))


(defun org-publish-update-timestamp (filename)
  "Update publishing timestamp for file FILENAME."
  (let ((timestamp (org-publish-timestamp-filename filename)))
    (set-file-times timestamp)))


;;;; Utilities


(defun org-publish-get-project (project-name)
  "Return project object for project PROJECT-NAME."
  (let ((project (assoc project-name org-publish-project-alist)))
    (if project
	(cdr project)
      nil)))


(defun org-publish-get-project-component (project-name component-name)
  "Return plist for project component COMPONENT-NAME within project PROJECT-NAME."
  (let* ((components (org-publish-get-project project-name))
	 (c nil)
	 (plist nil))
    (while (setq c (pop components))
      (when (and (stringp (car c)) (string= component-name (car c)))
	(setq plist (cdr c))))
    plist))


(defun org-publish-composite-project-p (element)
  "Tell whether an ELEMENT of org-publish-project-alist is composite."
  (listp (car (cdr element))))


(defun org-publish-iterate-project-plists (action &optional project-name)
  "Call function ACTION for each project component.
ACTION should accept two arguments: the name of the enclosing
project, and the property list associated with the project
component. If PROJECT-NAME is set, iterate only over components
of that project."
  (let ((alist (if project-name 
		   `((,project-name ,@(org-publish-get-project project-name)))
		 org-publish-project-alist))
	(project nil))
    (while (setq project (pop alist))
      (if (org-publish-composite-project-p project)
	  ;;
	  ;; handle composite project
	  (let ((components (cdr project))
		(c nil))
	    (while (setq c (pop components))
	      (let ((plist (cdr c)))
		(funcall action (car project) plist))))
	;;
	;; handle normal project
	(let ((plist (cdr project)))
	  (funcall action (car project) plist))))))

    	      

(defun org-publish-get-base-files (plist &optional exclude-regexp)
  "Return a list of all files in project defined by PLIST.
If EXCLUDE-REGEXP is set, this will be used to filter out
matching filenames."
  (let* ((dir (file-name-as-directory (plist-get plist :base-directory)))
	 (include-list (plist-get plist :include))
	 (extension (or (plist-get plist :base-extension) "org"))
	 (regexp (concat "^[^\\.].*\\.\\(" extension "\\)$"))
	 (allfiles (directory-files dir t regexp)))
    ;;
    ;; exclude files
    (setq allfiles
	  (if (not exclude-regexp)
	      allfiles
	    (delq nil
		  (mapcar (lambda (x)
			    (if (string-match exclude-regexp x) nil x))
			  allfiles))))
    ;;
    ;; include extra files
    (let ((inc nil))
      (while (setq inc (pop include-list))
	(setq allfiles (cons (concat dir inc) allfiles))))
    
    allfiles))


(defun org-publish-get-project-from-filename (filename)
  "Figure out which project a given FILENAME belongs to, if any.
Filename should contain full path. Returns name of project, or
nil if not found."
  (let ((found nil))
    (org-publish-iterate-project-plists 
     (lambda (project-name project-plist)
       (let ((files (org-publish-get-base-files project-plist)))
	 (if (member (expand-file-name filename) files)
	     (setq found project-name)))))
    found))


(defun org-publish-get-plist-from-filename (filename)
  "Return publishing configuration plist for file FILENAME."
  (let ((found nil))
    (org-publish-iterate-project-plists
     (lambda (project-name project-plist)
       (let ((files (org-publish-get-base-files project-plist)))
	 (if (member (expand-file-name filename) files)
             (setq found project-plist)))))
    found))


;;;; Pluggable publishing back-end functions


(defun org-publish-org-to-html (plist filename)
  "Publish an org file to HTML.  
PLIST is the property list for the given project. 
FILENAME is the filename of the org file to be published."
  (let* ((arg (plist-get plist :headline-levels)))
    (progn
      (find-file filename)
      (org-export-as-html arg nil plist)
      ;; get rid of HTML buffer
      (kill-buffer (current-buffer)))))
   

(defun org-publish-attachment (plist filename)
  "Publish a file with no transformation of any kind.
PLIST is the property list for the given project. 
FILENAME is the filename of the file to be published."
  (let ((destination (file-name-as-directory (plist-get plist :publishing-directory))))
    (eshell/cp filename destination)))


;;;; Publishing files, projects, and indices


(defun org-publish-file (filename)
  "Publish file FILENAME."
  (let* ((project-name (org-publish-get-project-from-filename filename))
	 (plist (org-publish-get-plist-from-filename filename))
	 (publishing-function (or (plist-get plist :publishing-function) 'org-publish-org-to-html)))
    (if (not project-name)
	(error (format "File %s is not part of any known project." filename)))
    (when (org-publish-needed-p filename)
      (funcall publishing-function plist filename)
      (org-publish-update-timestamp filename))))


(defun org-publish-project-plist (plist)
  "Publish all base files in project defined by PLIST.
 If :auto-index is set, publish the index too."
  (let* ((exclude-regexp (plist-get plist :exclude))
	 (publishing-function (or (plist-get plist :publishing-function) 'org-publish-org-to-html))
	 (buf (current-buffer))
	 (index-p (plist-get plist :auto-index))
         (index-filename (or (plist-get plist :index-filename) "index.org"))
	 (index-function (or (plist-get plist :index-function) 'org-publish-org-index))
	 (f nil))
    ;;
    (if index-p
	(funcall index-function plist index-filename))
    (let ((files (org-publish-get-base-files plist exclude-regexp)))
      (while (setq f (pop files))
	;; check timestamps
	(when (org-publish-needed-p f)
	  (funcall publishing-function plist f)
	  (org-publish-update-timestamp f))))
    ;; back to original buffer
    (switch-to-buffer buf)))


(defun org-publish-org-index (plist &optional index-filename)
  "Create an index of pages in project PLIST.  
Optionally set the filename of the index with INDEX-FILENAME; 
default is 'index.org'."
  (let* ((dir (file-name-as-directory (plist-get plist :base-directory)))
	 (exclude-regexp (plist-get plist :exclude))
	 (files (org-publish-get-base-files plist exclude-regexp))
	 (index-filename (concat dir (or index-filename "index.org")))
	 (index-buffer (find-buffer-visiting index-filename))
	 (ifn (file-name-nondirectory index-filename))
	 (f nil))
    ;;
    ;; if buffer is already open, kill it to prevent error message
    (if index-buffer
	(kill-buffer index-buffer))
    (with-temp-buffer 
      (while (setq f (pop files))
	(let ((fn (file-name-nondirectory f)))
	  (unless (string= fn ifn) ;; index shouldn't index itself
	    (insert (concat " + [[file:" fn "]["
			    (file-name-sans-extension fn)
			    "]]\n")))))
      (write-file index-filename)
      (kill-buffer (current-buffer)))))
      
 
;;;; Interactive publishing functions


;;;###autoload
(defun org-publish (project-name &optional force)
  "Publish the project PROJECT-NAME."
  (interactive "sProject name: \nP")
  (let ((org-publish-use-timestamps-flag (if force nil t)))
    (org-publish-iterate-project-plists 
     (lambda (ignore project-plist)
       (org-publish-project-plist project-plist))
     project-name)))
       

;;;###autoload
(defun org-publish-current-project (&optional force)
  "Publish the project associated with the current file.
With prefix argument, force publishing all files in project."
  (interactive "P")
  (let* ((project-name (org-publish-get-project-from-filename (buffer-file-name)))
	 (org-publish-use-timestamps-flag (if force nil t)))
    (if (not project-name)
	(error (format "File %s is not part of any known project." (buffer-file-name))))
    (org-publish project-name)))
	

;;;###autoload		      
(defun org-publish-current-file (&optional force)
  "Publish the current file.
With prefix argument, force publish the file."
  (interactive "P")
  (let ((org-publish-use-timestamps-flag 
	 (if force nil t)))
    (org-publish-file (buffer-file-name))))


;;;###autoload
(defun org-publish-all (&optional force)
  "Publish all projects.
With prefix argument, force publish all files."
  (interactive "P")
  (let ((org-publish-use-timestamps-flag
	 (if force nil t)))
    (org-publish-iterate-project-plists
     (lambda (project-name project-plist)
       (org-publish-project-plist project-plist)))))




(provide 'org-publish)
;;; org-publish.el ends here
