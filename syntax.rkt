#lang typed/racket/base

(provide (all-defined-out))

(provide (for-syntax (all-defined-out)))
(provide (for-syntax (all-from-out racket/base)))
(provide (for-syntax (all-from-out racket/syntax)))
(provide (for-syntax (all-from-out racket/symbol)))
(provide (for-syntax (all-from-out racket/sequence)))

(require (for-syntax racket/base))
(require (for-syntax racket/syntax))
(require (for-syntax racket/symbol))
(require (for-syntax racket/sequence))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(begin-for-syntax
  (define (make-identifier <id> fmt [-> values])
    (format-id <id> fmt (-> (syntax-e <id>))))
  
  (define (make-identifiers <id> <field>s [fmt "~a-~a"])
    (define id (syntax-e <id>))
    
    (for/list ([<field> (in-syntax <field>s)])
      (format-id <field> fmt id (syntax-e <field>))))

  (define (map-identifiers <id>s fmt [-> values])
    (for/list ([<id> (in-syntax <id>s)])
      (format-id <id> fmt (-> (syntax-e <id>)))))

  (define (make-identifier-indices <field>s [start-idx 0])
    (cons (datum->syntax <field>s (length (syntax->list <field>s)))
          (for/list ([<field> (in-syntax <field>s)]
                     [idx (in-naturals start-idx)])
            (datum->syntax <field> idx))))
  
  (define make-keyword-optional-arguments
    (case-lambda
      [(<field>s <DataType>s)
       (define-values (args reargs)
         (for/fold ([args null] [reargs null])
                   ([<field> (in-syntax <field>s)]
                    [<DataType> (in-syntax <DataType>s)])
           (let ([<kw-name> (datum->syntax <field> (string->keyword (symbol->immutable-string (syntax-e <field>))))]
                 [<Argument> #`[#,<field> : (Option #,<DataType>) #false]]
                 [<ReArgument> #`[#,<field> : (U Void False #,<DataType>) (void)]])
             (values (cons <kw-name> (cons <Argument> args))
                     (cons <kw-name> (cons <ReArgument> reargs))))))
       (list args reargs)]
      [(<self> <field>s <DataType>s <ref>s)
       (define-values (args reargs)
         (for/fold ([args null] [reargs null])
                   ([<field> (in-syntax <field>s)]
                    [<DataType> (in-syntax <DataType>s)]
                    [<ref> (in-syntax <ref>s)])
           (let ([<kw-name> (datum->syntax <field> (string->keyword (symbol->immutable-string (syntax-e <field>))))]
                 [<Argument> #`[#,<field> : (Option #,<DataType>) #false]]
                 [<ReArgument> #`[#,<field> : (Option #,<DataType>) (#,<ref> #,<self>)]])
             (values (cons <kw-name> (cons <Argument> args))
                     (cons <kw-name> (cons <ReArgument> reargs))))))
       (list args reargs)]))

  (define make-keyword-arguments
    (case-lambda
      [(<field>s <DataType>s <defval>s)
       (define-values (args reargs)
         (for/fold ([args null] [reargs null])
                   ([<field> (in-syntax <field>s)]
                    [<DataType> (in-syntax <DataType>s)]
                    [<defval> (in-syntax <defval>s)])
           (let ([<kw-name> (datum->syntax <field> (string->keyword (symbol->immutable-string (syntax-e <field>))))]
                 [<Argument> #`[#,<field> : #,<DataType> #,@<defval>]]
                 [<ReArgument> #`[#,<field> : (U Void #,<DataType>) (void)]])
             (values (cons <kw-name> (cons <Argument> args))
                     (cons <kw-name> (cons <ReArgument> reargs))))))
       (list args reargs)]
      [(<self> <field>s <DataType>s <defval>s <ref>s)
       (define-values (args reargs)
         (for/fold ([args null] [reargs null])
                   ([<field> (in-syntax <field>s)]
                    [<DataType> (in-syntax <DataType>s)]
                    [<defval> (in-syntax <defval>s)]
                    [<ref> (in-syntax <ref>s)])
           (let ([<kw-name> (datum->syntax <field> (string->keyword (symbol->immutable-string (syntax-e <field>))))]
                 [<Argument> #`[#,<field> : #,<DataType> #,@<defval>]]
                 [<ReArgument> #`[#,<field> : #,<DataType> (#,<ref> #,<self>)]])
             (values (cons <kw-name> (cons <Argument> args))
                     (cons <kw-name> (cons <ReArgument> reargs))))))
       (list args reargs)])))

(define-syntax (with-a-field-replaced stx)
    (syntax-case stx [:]
      [(_ (func pre-argl ... #:fields (field ...)) #:for field-name #:set sexpr)
       (with-syntax* ([(replaced-field ...)
                       (let ([name (syntax-e #'field-name)])
                         (for/list ([<field> (in-syntax #'(field ...))])
                           (if (eq? (syntax-e <field>) name)
                               #'sexpr <field>)))])
         (syntax/loc stx
           (func pre-argl ... replaced-field ...)))]
      [(_ (func pre-argl ... #:fields (field ...)) #:for field-name #:set sexpr #:if condition)
       (with-syntax* ([(replaced-field ...)
                       (let ([name (syntax-e #'field-name)])
                         (for/list ([<field> (in-syntax #'(field ...))])
                           (if (eq? (syntax-e <field>) name)
                               #`(if condition sexpr #,<field>) <field>)))])
         (syntax/loc stx
           (func pre-argl ... replaced-field ...)))]))