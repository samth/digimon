#lang typed/racket/base

(provide (all-defined-out))

(require racket/path)
(require racket/match)

(require typed/racket/unsafe)
(require typed/setup/getinfo)

(require "parameter.rkt")

(require "../../echo.rkt")

(unsafe-require/typed
 raco/command-name
 [short-program+command-name (-> String)])

(unsafe-require/typed
 setup/option
 [setup-program-name (Parameterof String)]
 [make-launchers (Parameterof Boolean)]
 [make-info-domain (Parameterof Boolean)]
 [make-foreign-libs (Parameterof Boolean)]
 [call-install (Parameterof Boolean)]
 [call-post-install (Parameterof Boolean)])

(unsafe-require/typed
 setup/setup
 [setup (-> [#:collections (Option (Listof (Listof Path-String)))] [#:make-docs? Boolean] [#:fail-fast? Boolean] Boolean)])

(unsafe-require/typed
 compiler/cm
 [manager-trace-handler (Parameterof (-> String Any))])

(unsafe-require/typed
 compiler/compiler
 [compile-directory-zos (-> Path-String Info-Ref [#:verbose Boolean] [#:skip-doc-sources? Boolean] Void)])

(unsafe-require/typed
 racket/base
 [collection-file-path (->* (Path-String #:fail (-> String Boolean)) (#:check-compiled? Boolean) #:rest Path-String Path)])

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define wisemon-compile : (-> Path-String String Info-Ref Void)
  (lambda [pwd digimon info-ref]
    (if (and (collection-file-path "." digimon #:fail (λ [[errmsg : String]] #false)) (> (parallel-workers) 1))
        (compile-collection digimon)
        (compile-directory pwd info-ref))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define compile-collection : (->* (String) (Natural) Void)
  (lambda [digimon [round 1]]
    (define summary? : Boolean #false)
    (define (colorize-stdout [bstr : Bytes])
      (when (= round 1)
        (when (regexp-match? #px"--- summary of errors ---"  bstr) (set! summary? #true))
        (term-colorize 248 #false null (bytes->string/utf-8 bstr))))
    (define (colorize-stderr [bstr : Bytes])
      (term-colorize (if summary? 'red 224) #false null (bytes->string/utf-8 bstr)))
    (set!-values (again? compiling-round) (values #false round))
    (parameterize ([setup-program-name (short-program+command-name)]
                   [make-launchers #false]
                   [make-info-domain #false]
                   [make-foreign-libs #false]
                   [call-install #false]
                   [call-post-install #false]
                   [current-output-port (filter-write-output-port (current-output-port) colorize-stdout)]
                   [current-error-port (filter-write-output-port (current-error-port) colorize-stderr)])
      (or (setup #:collections (list (list digimon)) #:make-docs? #false #:fail-fast? #true)
          (error the-name "compiling failed.")))
    (when again? (compile-collection digimon (add1 round)))))

(define compile-directory : (->* (Path-String Info-Ref) (Natural) Void)
  (lambda [pwd info-ref [round 1]]
    (define px.in (pregexp (path->string (current-directory))))
    (define traceln (λ [[line : Any]] (printf "round[~a]: ~a~n" round line)))
    (set! again? #false)
    (define (filter-verbose [info : String])
      (match info
        [(pregexp #px"checking:") (when (and (make-print-checking) (regexp-match? px.in info)) (traceln info))]
        [(pregexp #px"compiling ") (set! again? #true)]
        [(pregexp #px"done:") (when (regexp-match? px.in info) (traceln info) (set! again? #true))]
        [(pregexp #px"maybe-compile-zo starting") (traceln info)]
        [(pregexp #px"(wrote|compiled|processing:|maybe-compile-zo finished)") '|Skip Task Endline|]
        [(pregexp #px"(newer|skipping:)") (when (make-print-reasons) (traceln info))]
        [_ (traceln info)]))
    (with-handlers ([exn:fail? (λ [[e : exn:fail]] (error the-name "[error] ~a" (exn-message e)))])
      (parameterize ([manager-trace-handler filter-verbose]
                     [error-display-handler (λ [s e] (eechof #:fgcolor 'red ">> ~a~n" s))])
        (compile-directory-zos pwd info-ref #:verbose #false #:skip-doc-sources? #true)))
    (when again? (compile-directory pwd info-ref (add1 round)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define racket-smart-dependencies : (->* (Path-String) ((Listof Path)) (Listof Path))
  (lambda [entry [memory null]]
    (foldl (λ [[subpath : Bytes] [memory : (Listof Path)]] : (Listof Path)
             (define subsrc (simplify-path (build-path (assert (path-only entry) path?) (bytes->string/utf-8 subpath))))
             (cond [(member subsrc memory) memory]
                   [else (racket-smart-dependencies subsrc memory)]))
           (append memory (list (if (string? entry) (string->path entry) entry)))
           (call-with-input-file* entry
             (λ [[rktin : Input-Port]]
               (regexp-match* #px"(?<=@(include-(section|extracted|previously-extracted|abstract)|require)[{[]((\\(submod \")|\")?).+?.(scrbl|rktl?)(?=[\"}])"
                              rktin))))))

(define filter-write-output-port : (->* (Output-Port (-> Bytes Any)) (Boolean) Output-Port)
  (lambda [/dev/stdout write-wrap [close? #false]]
    (make-output-port (object-name /dev/stdout)
                      /dev/stdout
                      (λ [[bytes : Bytes] [start : Natural] [end : Natural] [flush? : Boolean] [enable-break? : Boolean]]
                        (define transformed (write-wrap (subbytes bytes start end)))
                        (cond [(string? transformed) (write-string transformed /dev/stdout)]
                              [(bytes? transformed) (write-bytes-avail* transformed /dev/stdout)])
                        (- end start))
                      (λ [] (unless (not close?) (close-output-port /dev/stdout)))
                      #false #false #false)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; WARNING: parameters are thread specific.
(define again? : Boolean #false)
(define compiling-round : Natural 1)