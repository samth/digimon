#lang typed/racket/base

(provide (all-defined-out))

(require racket/list)
(require racket/string)
(require racket/symbol)

(require "../../filesystem.rkt")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-type Archive-Entry-Config (List (Listof Symbol) (Listof Any) (Option String)))
(define-type Archive-Directory-Configure (-> Path Path Archive-Entry-Config (Option Archive-Entry-Config)))
(define-type Archive-Entries (Rec aes (Listof (U Archive-Entry aes))))
(define-type Archive-Path (U Bytes String Path))

(define-type Archive-Fragment (Pairof Natural Natural))
(define-type Archive-Fragments (Listof Archive-Fragment))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define archive-stdin-permission : Nonnegative-Fixnum #o000)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(struct archive-entry
  ([source : (U Path Bytes)]
   [alias : (Option Path-String)]
   [ascii? : Boolean]
   [methods : (Listof Symbol)]
   [options : (Listof Any)]
   [utc-time : (Option Integer)]
   [permission : Nonnegative-Fixnum]
   [comment : (Option String)])
  #:type-name Archive-Entry
  #:transparent)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; TODO: deal with link files
(define make-archive-file-entry : (->* (Archive-Path)
                                       ((Option Path-String) #:ascii? Boolean #:methods (Listof Symbol) #:options (Listof Any) #:comment (Option String))
                                       Archive-Entry)
  (lambda [src [name #false] #:ascii? [ascii? #false] #:methods [methods null] #:options [options null] #:comment [comment #false]]
    (define path : Path (archive-path->path src))

    (archive-entry path name ascii? methods options
                   (file-or-directory-modify-seconds path) (file-or-directory-permissions path 'bits)
                   comment)))

; TODO: deal with link files
(define make-archive-directory-entries : (->* (Archive-Path)
                                              ((Option Path-String) #:configure (Option Archive-Directory-Configure) #:keep-directory? Boolean
                                                                    #:methods (Listof Symbol) #:options (Listof Any) #:comment (Option String))
                                              Archive-Entries)
  (lambda [#:configure [configure #false] #:keep-directory? [mkdir? #true]
           #:methods [methods null] #:options [options null] #:comment [comment #false]
           srcdir [root #false]]
    (define rootdir : Path (archive-path->path srcdir))
    
    (if (directory-exists? rootdir)
        (let make-subentries ([parent : Path rootdir]
                              [sbnames : (Listof Path) (directory-list rootdir #:build? #false)]
                              [seirtne : (Listof (U Archive-Entry Archive-Entries)) null]
                              [pconfig : Archive-Entry-Config (list methods options comment)])
          (cond [(pair? sbnames)
                 (let*-values ([(self-name rest) (values (car sbnames) (cdr sbnames))]
                               [(self-path) (build-path parent self-name)]
                               [(config) (if (not configure) pconfig (configure self-path self-name pconfig))])
                   (cond [(or (not config) (link-exists? self-path))
                          (make-subentries parent rest seirtne pconfig)]
                         [(directory-exists? self-path)
                          (let ([es (make-subentries self-path (directory-list self-path #:build? #false) null config)])
                            (make-subentries parent rest (cons es seirtne) pconfig))]
                         [else ; regular file
                          (let* ([name (and root (archive-entry-reroot self-path root #false))]
                                 [e (make-archive-file-entry self-path name #:methods (car config) #:options (cadr config) #:comment (caddr config))])
                            (make-subentries parent rest (cons e seirtne) pconfig))]))]
                [(and mkdir?)
                 (let ([name (and root (archive-entry-reroot parent root #false))])
                   (cons (make-archive-file-entry (path->directory-path parent) name #:methods (car pconfig) #:options (cadr pconfig) #:comment (caddr pconfig))
                         (reverse seirtne)))]
                [else (reverse seirtne)]))

        (list (make-archive-file-entry #:methods methods #:options options #:comment comment
                                       rootdir (and root (archive-entry-reroot rootdir root #false)))))))

(define make-archive-ascii-entry : (->* ((U Bytes String))
                                        ((Option Path-String) #:methods (Listof Symbol) #:options (Listof Any)
                                                              #:utc-time (Option Integer) #:permission Nonnegative-Fixnum #:comment (Option String))
                                        Archive-Entry)
  (lambda [#:utc-time [mtime #false] #:permission [permission archive-stdin-permission] #:methods [methods null] #:options [options null] #:comment [comment #false]
           src [name #false]]
    (archive-entry (if (string? src) (string->bytes/utf-8 src) src)
                   (or name (symbol->immutable-string (gensym 'ascii)))
                   #true methods options mtime permission
                   comment)))

(define make-archive-binary-entry : (->* ((U Bytes String))
                                         ((Option Path-String) #:methods (Listof Symbol) #:options (Listof Any)
                                                               #:utc-time (Option Integer) #:permission Nonnegative-Fixnum #:comment (Option String))
                                         Archive-Entry)
  (lambda [#:utc-time [mtime #false] #:permission [permission archive-stdin-permission] #:methods [methods null] #:options [options null] #:comment [comment #false]
           src [name #false]]
    (archive-entry (if (string? src) (string->bytes/utf-8 src) src)
                   (or name (symbol->immutable-string (gensym 'binary)))
                   #false methods options mtime permission
                   comment)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define make-archive-ignore-configure : (-> (U Regexp Byte-Regexp String Path (Listof (U Regexp Byte-Regexp String Path))) Archive-Directory-Configure)
  (lambda [ignores]
    (define match? (make-path-match-predicate ignores))

    (λ [fullpath basename config]
      (cond [(match? fullpath basename) #false]
            [else config]))))

(define make-archive-chained-configure : (-> Archive-Directory-Configure Archive-Directory-Configure * Archive-Directory-Configure)
  (lambda [c0 . cs]
    (cond [(null? cs) c0]
          [else (λ [fullpath basename config]
                  (let cfold ([?c : (Option Archive-Entry-Config) (c0 fullpath basename config)]
                              [cs : (Listof Archive-Directory-Configure) cs])
                    (and ?c
                         (cond [(null? cs) ?c]
                               [else (cfold ((car cs) fullpath basename ?c)
                                            (cdr cs))]))))])))

(define defualt-archive-ignore-configure : Archive-Directory-Configure
  (make-archive-ignore-configure (cons #px"/(compiled|[.]DS_Store|[.]git.*)/?$" (use-compiled-file-paths))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define archive-port-name : (-> Input-Port String)
  (lambda [/dev/zipin]
    (define name (object-name /dev/zipin))

    (cond [(path? name) (path->string name)]
          [(string? name) name]
          [(symbol? name) (symbol->immutable-string name)]
          [else (format "~a" name)])))

(define archive-entry-get-name : (-> Archive-Entry Path-String)
  (lambda [e]
    (or (archive-entry-alias e)
        (let ([src (archive-entry-source e)])
          (cond [(bytes? src) ""]
                [else src])))))

(define archive-path->path : (-> Archive-Path Path)
  (lambda [src]
    (simple-form-path
     (cond [(path? src) src]
           [(string? src) (string->path src)]
           [else (bytes->path src)]))))

(define archive-entry-reroot : (->* (Path-String (Option Path-String)) ((Option Path-String) (Option Symbol)) String)
  (lambda [name strip-root [zip-root #false] [gen-stdin-name #false]]
    (define stdin? : Boolean (equal? name ""))
    
    (cond [(and stdin? (not gen-stdin-name)) ""]
          [else (let* ([name (if (not stdin?) name (symbol->immutable-string (gensym gen-stdin-name)))]
                       [rpath (cond [(relative-path? name) name]
                                    [(not (path-string? strip-root)) (find-root-relative-path name)]
                                    [else (find-relative-path (simple-form-path strip-root) (simplify-path name)
                                                              #:more-than-root? #false ; relative to root
                                                              #:more-than-same? #false ; build "." path, docs seems to be wrong
                                                              #:normalize-case? #false)])])
                  (cond [(path-string? zip-root) (some-system-path->string (simplify-path (build-path (find-root-relative-path zip-root) rpath) #false))]
                        [(path-for-some-system? rpath) (some-system-path->string rpath)]
                        [else rpath]))])))

(define archive-suffix-regexp : (-> (Listof Symbol) Regexp)
  (lambda [suffixes]
    (regexp (string-join (map symbol->immutable-string (remove-duplicates suffixes)) "|"
                         #:before-first ".(" #:after-last ")$"))))
