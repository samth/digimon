#lang typed/racket/base

(provide (all-defined-out))

(require racket/file)
(require racket/list)

(require digimon/spec)
(require digimon/archive)

(require digimon/digitama/bintext/lz77)
(require digimon/digitama/bintext/huffman)
(require digimon/digitama/bintext/table/huffman)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define tempdir : Path (find-system-path 'temp-dir))

(define pk.zip : Path (build-path tempdir "pk.zip"))
(define pktest : Path (build-path tempdir "pktest"))

(define rootdir : Path (simplify-path (collection-file-path "." "digimon")))
(define tamer:// : Path (collection-file-path "zip" "digimon" "tamer"))

(define memlevel : Positive-Byte 4)

(define random-symbol : (-> Index Byte Real Byte Natural)
  (lambda [i smax ratio base0]
    (define threshold (real->double-flonum (* smax ratio)))
    (define letter (random smax))
    
    (cond [(> letter threshold) (+ letter base0)]
          [(= (remainder letter 8) 0) (char->integer #\newline)]
          [else (+ (random smax) base0)])))

(define pktest-write : (-> Bytes (U String Symbol) Void)
  (lambda [raw filename]
    (define test.λsh (build-path pktest (format "~a" filename)))

    (unless (file-exists? test.λsh)
      (make-parent-directory* test.λsh)
    
      (call-with-output-file* #:exists 'truncate/replace
        test.λsh
        (λ [[/dev/zipout : Output-Port]]
          (void (write-bytes raw /dev/zipout)))))))

(define pktest-configure : Archive-Directory-Configure
  (lambda [path name config]
    (define ?dist (regexp-match-positions* #px"(?<=:)(\\d+)" name))

    (define options : (Listof Any)
      (or (and (pair? ?dist) (pair? (cdr ?dist))
               (let ([pos (cadr ?dist)])
                 (and (not (list? pos))
                      (let* ([bname (path->string name)]
                             [base (string->number (substring bname (car pos) (cdr pos)))])
                        (list (zip-run-preference (max 1 (assert base index?))) 'fixed)))))
          (let ([bname (string->symbol (path->string name))])
            (case bname
              [(block-aligned.λsh literals.λsh) (list 'huffman-only 'fixed)]
              [(window-sliding.λsh) (list 1 'fixed)]
              [(backref) (list 'run 'fixed)]
              [else (cadr config)]))))

    (list (car config) options (caddr config))))

(define gen-pktests : (-> Void)
  (lambda []
    (pktest-write (apply bytes (build-list (arithmetic-shift 1 (+ memlevel 6)) (λ [[i : Index]] (+ (remainder i 26) 65))))
                  'deflated/block-aligned.λsh)
    
    (pktest-write (apply bytes (build-list (arithmetic-shift 1 (add1 window-ibits)) (λ [[i : Index]] (random-symbol i 95 0.95 32))))
                  'deflated/window-sliding.λsh)
    
    (for ([base (in-vector huffman-backref-bases)]
          [extra (in-bytes huffman-backref-extra-bits)]
          [idx (in-naturals)])
      (pktest-write (apply bytes-append
                           (for/list : (Listof Bytes) ([offset (in-range 0 (expt 2 extra))])
                             (let ([size (+ base offset 1)])
                               (make-bytes size (+ 97 (remainder size 26))))))
                    (format "deflated/backref/~a:~a.λsh" (+ idx backref-span-offset) base)))
    
    (for ([base (in-vector huffman-distance-bases)]
          [extra (in-bytes huffman-distance-extra-bits)]
          [idx (in-naturals)])
      (pktest-write (make-bytes (+ base lz77-default-max-match extra) (+ 65 extra))
                    (format "deflated/backref/dist:~a:~a.λsh" idx base)))
    
    (for ([symbols (in-list (group-by (λ [[s : Index]] (bytes-ref huffman-fixed-literal-lengths s)) (range #x100)))])
      (pktest-write (apply bytes symbols)
                    (format "deflated/literals/~abits.λsh"
                      (bytes-ref huffman-fixed-literal-lengths (car symbols)))))))

(gen-pktests)
  
(define entries : Archive-Entries
  (list
   (list (list (make-archive-file-entry (build-path tamer:// "spec/pkzip.rkt") "stored/pkzip.rkt" #:methods '(stored))
               (make-archive-ascii-entry #"stored ascii" "stored/ascii.txt" #:methods '(stored))
               (make-archive-ascii-entry #"" "stored/empty.txt" #:methods '(stored))
               (make-archive-binary-entry #"data from stdin will be renamed randomly to stop `unzip` from reusing another entry's name" "" #:methods '(stored)))
         
         (list (make-archive-binary-entry #"" "deflated/blank.λsh" #:methods '(deflated) #:options '(0 fixed))
               (make-archive-binary-entry #"data hasn't been compressed by lz77 algorithm" "deflated/fixed/identity.λsh" #:methods '(deflated) #:options '(id fixed))
               (make-archive-binary-entry #"Fa-la-la-la-la (4 'la's)" "deflated/fixed/overlap.λsh" #:methods '(deflated) #:options '(6 fixed))))
   
   (make-archive-directory-entries pktest pktest #:configure pktest-configure #:keep-directory? #true #:methods '(deflated) #:options '(fixed))
   (make-archive-directory-entries rootdir rootdir #:configure defualt-archive-ignore-configure #:keep-directory? #false #:methods '(deflated))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-feature pkzip #:do
  (describe "create" #:do
            #:before (λ [] (call-with-output-file* pk.zip #:exists 'replace
                             (λ [[/dev/zipout : Output-Port]]
                               (write pk.zip /dev/zipout)
                               (zip-create #:root pktest #:zip-root "pkzip" #:memory-level memlevel #:force-zip64? #true #:disable-seeking? #false
                                           /dev/zipout entries))))
            #:do
            (it "should create the test archive" #:do
                (expect-file-exists pk.zip)))
  (describe "verify" #:do
            (for/spec ([entry (in-list (reverse (zip-extract pk.zip (make-archive-verification-reader) null)))])
              (it (car entry) #:do
                  (if (string? (cdr entry))
                      (expect-true (cdr entry) (cdr entry))
                      (expect-true (cdr entry)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(module+ main
  (void (spec-prove pkzip)))