#lang typed/racket/base

(provide (all-defined-out))
(provide (rename-out [write-muintptr write-msize]
                     [write-luintptr write-lsize]))

(require "port.rkt")

(require "digitama/ioexn.rkt")
(require "digitama/stdio.rkt")

(require "digitama/unsafe/number.rkt")

(require (for-syntax racket/base))
(require (for-syntax racket/syntax))
(require (for-syntax racket/sequence))
(require (for-syntax syntax/parse))
(require (for-syntax racket/symbol))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-type Subbytes (List Bytes Index Index))
(define-type Octets (U Bytes Subbytes))

(define-for-syntax (stdio-integer-type datatype)
  (case datatype
    [(Byte Octet)                (list #'Byte    1 #'read-luint8  #'write-msintptr #'stdio-fixed-size)]
    [(Short MShort Int16 MInt16) (list #'Fixnum  2 #'read-msint16 #'write-msintptr #'stdio-fixed-size)]
    [(UInt16 MUInt16)            (list #'Index   2 #'read-muint16 #'write-muintptr #'stdio-fixed-size)]
    [(LShort LInt16)             (list #'Fixnum  2 #'read-lsint16 #'write-lsintptr #'stdio-fixed-size)]
    [(LUInt16)                   (list #'Index   2 #'read-luint16 #'write-luintptr #'stdio-fixed-size)]
    [(Int MInt Int32 MInt32)     (list #'Fixnum  4 #'read-msint32 #'write-msintptr #'stdio-fixed-size)]
    [(UInt32 MUInt32)            (list #'Index   4 #'read-muint32 #'write-muintptr #'stdio-fixed-size)]
    [(LInt LInt32)               (list #'Fixnum  4 #'read-lsint32 #'write-lsintptr #'stdio-fixed-size)]
    [(LUInt32)                   (list #'Index   4 #'read-luint32 #'write-luintptr #'stdio-fixed-size)]
    [(Long MLong Int64 MInt64)   (list #'Integer 8 #'read-msint64 #'write-msintptr #'stdio-fixed-size)]
    [(UInt64 MUInt64)            (list #'Natural 8 #'read-muint64 #'write-muintptr #'stdio-fixed-size)]
    [(LLong LInt64)              (list #'Integer 8 #'read-lsint64 #'write-lsintptr #'stdio-fixed-size)]
    [(LUInt64)                   (list #'Natural 8 #'read-luint64 #'write-luintptr #'stdio-fixed-size)]
    [else #false]))

(define-for-syntax (stdio-float-type datatype)
  (case datatype
    ;[(Float MFloat)              (list #'flonum 4)]
    ;[(LFloat)                    (list #'flonum 4)]
    ;[(Double MDouble)            (list #'flonum 8)]
    ;[(LDouble)                   (list #'flonum 8)]
    [else #false]))

(define-for-syntax (stdio-bytes-type datatype <fields>)
  (case (syntax-e (car datatype))
    [(Bytesof)          (list #'Bytes  (stdio-target-field (cadr datatype) <fields>) #'read-nbytes      #'write-nbytes     #'bytes-length)]
    [(Stringof)         (list #'String (stdio-target-field (cadr datatype) <fields>) #'read-nbstring    #'write-nbstring   #'string-utf-8-length)]
    [(Localeof)         (list #'String (stdio-target-field (cadr datatype) <fields>) #'read-nlcstring   #'write-nbstring   #'string-utf-8-length)]

    [(NBytes MNBytes)   (list #'Bytes  (stdio-word-size (cadr datatype))             #'read-mn:bytes    #'write-mn:bytes   #'bytes-length)]
    [(LNBytes)          (list #'Bytes  (stdio-word-size (cadr datatype))             #'read-ln:bytes    #'write-ln:bytes   #'bytes-length)]

    [(NString MNString) (list #'String (stdio-word-size (cadr datatype))             #'read-mn:bstring  #'write-mn:bstring #'string-utf-8-length)]
    [(LNString)         (list #'String (stdio-word-size (cadr datatype))             #'read-ln:bstring  #'write-ln:bstring #'string-utf-8-length)]
    
    [(NLocale MNLocale) (list #'String (stdio-word-size (cadr datatype))             #'read-mn:lcstring #'write-mn:bstring #'string-utf-8-length)]
    [(LNLocale)         (list #'String (stdio-word-size (cadr datatype))             #'read-ln:lcstring #'write-ln:bstring #'string-utf-8-length)]

    [else #false]))

(define-for-syntax (stdio-integer-type/read->peek <read-int>)
  (case (syntax-e <read-int>)
    [(read-luint8)  #'peek-luint8]
    [(read-msint16) #'peek-msint16]
    [(read-muint16) #'peek-muint16]
    [(read-lsint16) #'peek-lsint16]
    [(read-luint16) #'peek-luint16]
    [(read-msint32) #'peek-msint32]
    [(read-muint32) #'peek-muint32]
    [(read-lsint32) #'peek-lsint32]
    [(read-luint32) #'peek-luint32]
    [(read-msint64) #'peek-msint64]
    [(read-muint64) #'peek-muint64]
    [(read-lsint64) #'peek-lsint64]
    [(read-luint64) #'peek-luint64]
    [else <read-int>]))

(define-for-syntax (stdio-datum-type <DataType> <layout> <field>)
  (syntax-parse <DataType> #:datum-literals []
    [(#:enum type datum->raw raw->datum (~alt (~optional (~seq #:-> Type) #:defaults ([Type #'Symbol]))
                                              (~optional (~seq #:fallback enum) #:defaults ([enum #'throw-range-error*]))) ...)
     (let ([bintype (stdio-integer-type (syntax-e #'type))])
       (and (list? bintype)
            (append (cons #'Type (cdr bintype))
                    (list (list #'datum->raw #'enum) (list #'raw->datum #'enum)))))]
    [(#:enum type datum-identity (~optional (~seq #:fallback enum) #:defaults ([enum #'throw-range-error*])))
     (let ([bintype (stdio-integer-type (syntax-e #'type))])
       (and (list? bintype)
            (append bintype
                    (list null (list #'datum-identity #'enum)))))]
    [(#:subint type subint? (~alt (~optional (~seq #:-> Type) #:defaults ([Type #'#false]))
                                  (~optional (~seq #:throw throw) #:defaults ([throw #'throw-range-error]))) ...)
     (let ([bintype (stdio-integer-type (syntax-e #'type))])
       (and (list? bintype)
            (append (if (syntax-e #'Type) (cons #'Type (cdr bintype)) bintype)
                    (list null
                          (list (list #'subint?)
                                (format-id #'subint? "~a-~a" (syntax-e <layout>) (syntax-e <field>))
                                #'throw)))))]
    [_ #false]))

(define-for-syntax (stdio-typeinfo-standardize typeinfo)
  (case (length typeinfo)
    [(5) (append typeinfo (list null null))]
    [else typeinfo]))

(define-for-syntax (stdio-signature-field <field> <signature?> <defval>)
  (and (syntax-e <signature?>)
       (list <field> (car (syntax-e <defval>)))))

(define-for-syntax (stdio-auto-field <field> <DataType>)
  (define datatype (syntax-e <DataType>))

  (and (pair? datatype)
       (case (syntax-e (car datatype))
         [(Bytesof)           (list (cadr datatype) <field> #'bytes-length)]
         [(Stringof Localeof) (list (cadr datatype) <field> #'string-utf-8-length)]
         [else #false])))

(define-for-syntax (stdio-field-metainfo <read> <meta>)
  (syntax-case <meta> []
    [(#:signature defval) (list (list #'defval) #'#true #'#false <read>)]
    [(#:omittable-signature defval) (list (list #'defval) #'#true #'#true (stdio-integer-type/read->peek <read>))]
    [(#:default defval) (list (list #'defval) #'#false #'#false <read>)]
    [(meta0 metan ...) (raise-syntax-error 'define-binary-struct "unrecognized field info" #'meta0 #false (syntax->list #'(metan ...)))]
    [_ (list null #'#false #'#false <read>)]))

(define-syntax (define-binary-struct stx)
  (syntax-case stx [:]
    [(_ layout+super : Layout ([field : DataType metainfo ...] ...) options ...)
     (with-syntax* ([(layout super ...) (let ([id+super (syntax-e #'layout+super)]) (if (symbol? id+super) (list #'layout+super) id+super))]
                    [constructor (format-id #'layout "~a" (gensym (format "~a:" (syntax-e #'layout))))]
                    [make-layout (format-id #'layout "make-~a" (syntax-e #'layout))]
                    [remake-layout (format-id #'layout "remake-~a" (syntax-e #'layout))]
                    [sizeof-layout (format-id #'layout "sizeof-~a" (syntax-e #'layout))]
                    [read-layout (format-id #'layout "read-~a" (syntax-e #'layout))]
                    [write-layout (format-id #'layout "write-~a" (syntax-e #'layout))]
                    [([FieldType integer-size read-field write-field field-size [datum->raw ...] [raw->datum ...]] ...)
                     (let ([<fields> #'(field ...)])
                       (for/list ([<DataType> (in-syntax #'(DataType ...))]
                                  [<field> (in-syntax #'(field ...))])
                         (define datatype (syntax-e <DataType>))
                         (stdio-typeinfo-standardize
                          (or (stdio-integer-type datatype)
                              (stdio-float-type datatype)
                              (and (pair? datatype)
                                   (or (stdio-bytes-type datatype <fields>)
                                       (stdio-datum-type <DataType> #'layout <field>)))
                              (raise-syntax-error 'define-binary-struct "unrecognized data type" <DataType>)))))]
                    [([[defval ...] signature? omittable? peek-field] ...)
                     (for/list ([<metainfo> (in-syntax #'([metainfo ...] ...))]
                                [<read> (in-syntax #'(read-field ...))])
                       (stdio-field-metainfo <read> <metainfo>))]
                    [([sig-field magic-number] ...)
                     (filter list?
                             (for/list ([<field> (in-syntax #'(field ...))]
                                        [<signature?> (in-syntax #'(signature? ...))]
                                        [<defval> (in-syntax #'([defval ...] ...))])
                               (stdio-signature-field <field> <signature?> <defval>)))]
                    [([auto-field target-field field->value] ...)
                     (filter list?
                             (for/list ([<field> (in-syntax #'(field ...))]
                                        [<DataType> (in-syntax #'(DataType ...))])
                               (stdio-auto-field <field> <DataType>)))]
                    [([field-ref auto?] ...)
                     (let ([autofields (syntax->datum #'(auto-field ...))])
                       (for/list ([<field> (in-syntax #'(field ...))])
                         (define field (syntax-e <field>))
                         (list (format-id <field> "~a-~a" (syntax-e #'layout) field)
                               (and (memq field autofields) #true))))]
                    [([kw-args ...] [kw-reargs ...] [(man-field man-ref) ...])
                     (let*-values ([(auto-fields) (append (syntax->datum #'(sig-field ...)) (syntax->datum #'(auto-field ...)))]
                                   [(args reargs sdleif)
                                    (for/fold ([args null] [reargs null] [sdleif null])
                                              ([<field> (in-syntax #'(field ...))]
                                               [<ref> (in-syntax #'(field-ref ...))]
                                               [<Argument> (in-syntax #'([field : FieldType defval ...] ...))]
                                               [<ReArgument> (in-syntax #'([field : (Option FieldType) #false] ...))])
                                      (define field (syntax-e <field>))
                                      (cond [(memq field auto-fields) (values args reargs sdleif)]
                                            [else (let ([<kw-name> (datum->syntax <field> (string->keyword (symbol->immutable-string field)))])
                                                    (values (cons <kw-name> (cons <Argument> args))
                                                            (cons <kw-name> (cons <ReArgument> reargs))
                                                            (cons (list <field> <ref>) sdleif)))]))])
                       (list args reargs (reverse sdleif)))])
       (syntax/loc stx
         (begin (struct layout super ... ([field : FieldType] ...)
                  #:constructor-name constructor
                  #:type-name Layout
                  #:transparent
                  options ...)

                (define (make-layout kw-args ...) : Layout
                  (let ([sig-field magic-number] ...
                        [auto-field (field->value target-field)] ...)
                    (constructor field ...)))

                (define (remake-layout [src : Layout] kw-reargs ...) : Layout
                  (let* ([sig-field magic-number] ...
                         [man-field (or man-field (man-ref src))] ...
                         [auto-field (field->value target-field)] ...)
                    (constructor field ...)))

                (define sizeof-layout : (->* () ((Option Layout)) Natural)
                  (let ([size0 (apply + (map abs (filter exact-integer? '(integer-size ...))))])
                    (lambda [[instance #false]]
                      (cond [(not instance) size0]
                            [else (apply + size0
                                         (list (field-size (field-ref instance))
                                               ...))]))))

                (define read-layout : (->* () (Input-Port (Option Integer)) Layout)
                  (let ([sizes : (HashTable Symbol Index) (make-hasheq)])
                    (lambda [[/dev/stdin (current-input-port)] [posoff #false]]
                      (unless (not posoff)
                        (port-seek /dev/stdin posoff))

                      (let* ([field (call-datum-reader* [signature? omittable? peek-field /dev/stdin read-layout defval ...]
                                                        [raw->datum ...]
                                                        read-field integer-size /dev/stdin 'field sizes auto?)] ...)
                        (constructor field ...)))))

                (define write-layout : (->* (Layout) (Output-Port (Option Natural) #:write-all-fields? Boolean) Natural)
                  (lambda [src [/dev/stdout (current-output-port)] [posoff #false] #:write-all-fields? [force? #true]]
                    (when (exact-nonnegative-integer? posoff)
                      (file-position /dev/stdout posoff))

                    (+ (call-datum-writer* omittable? force? [datum->raw ...] write-field (field-ref src) integer-size /dev/stdout)
                       ...))))))]))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define try-read-signature : (-> Input-Port Bytes Boolean)
  (lambda [/dev/stdin signature]
    (define siglength : Index (bytes-length signature))
    
    (and (equal? signature (peek-nbytes /dev/stdin siglength))
         (read-bytes siglength /dev/stdin)
         #true)))

(define read-signature : (-> Input-Port Bytes Symbol Any * Void)
  (lambda [/dev/stdin signature who . errmsg]
    (unless (try-read-signature /dev/stdin signature)
      (apply throw-signature-error /dev/stdin who errmsg))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define read-mn:bytes : (-> Input-Port Natural Bytes)
  (lambda [/dev/stdin size]
    (read-nbytes /dev/stdin (read-msize /dev/stdin size))))

(define read-mn:bstring : (-> Input-Port Natural String)
  (lambda [/dev/stdin bsize]
    (bytes->string/utf-8 (read-mn:bytes /dev/stdin bsize))))

(define read-mn:lcstring : (-> Input-Port Natural String)
  (lambda [/dev/stdin bsize]
    (read-nlcstring /dev/stdin (read-msize /dev/stdin bsize))))

(define read-ln:bytes : (-> Input-Port Natural Bytes)
  (lambda [/dev/stdin size]
    (read-nbytes /dev/stdin (read-lsize /dev/stdin size))))

(define read-ln:bstring : (-> Input-Port Natural String)
  (lambda [/dev/stdin bsize]
    (bytes->string/utf-8 (read-ln:bytes /dev/stdin bsize))))

(define read-ln:lcstring : (-> Input-Port Natural String)
  (lambda [/dev/stdin bsize]
    (read-nlcstring /dev/stdin (read-lsize /dev/stdin bsize))))

(define-read-integer*
  [msb-bytes->octet 1 [read-msint8  #:-> Fixnum]  [read-muint8  #:-> Byte]]
  [msb-bytes->short 2 [read-msint16 #:-> Fixnum]  [read-muint16 #:-> Index]]
  [msb-bytes->int   4 [read-msint32 #:-> Fixnum]  [read-muint32 #:-> Index]]
  [msb-bytes->long  8 [read-msint64 #:-> Integer] [read-muint64 #:-> Natural]])

(define-read-integer*
  [lsb-bytes->octet 1 [read-lsint8  #:-> Fixnum]  [read-luint8  #:-> Byte]]
  [lsb-bytes->short 2 [read-lsint16 #:-> Fixnum]  [read-luint16 #:-> Index]]
  [lsb-bytes->int   4 [read-lsint32 #:-> Fixnum]  [read-luint32 #:-> Index]]
  [lsb-bytes->long  8 [read-lsint64 #:-> Integer] [read-luint64 #:-> Natural]])

(define-read-integer read-msize msb-bytes->index #:-> Index)
(define-read-integer read-lsize lsb-bytes->index #:-> Index)

(define-peek-integer*
  [msb-bytes->octet 1 [peek-msint8  #:-> Fixnum]  [peek-muint8  #:-> Byte]]
  [msb-bytes->short 2 [peek-msint16 #:-> Fixnum]  [peek-muint16 #:-> Index]]
  [msb-bytes->int   4 [peek-msint32 #:-> Fixnum]  [peek-muint32 #:-> Index]]
  [msb-bytes->long  8 [peek-msint64 #:-> Integer] [peek-muint64 #:-> Natural]])

(define-peek-integer*
  [lsb-bytes->octet 1 [peek-lsint8  #:-> Fixnum]  [peek-luint8  #:-> Byte]]
  [lsb-bytes->short 2 [peek-lsint16 #:-> Fixnum]  [peek-luint16 #:-> Index]]
  [lsb-bytes->int   4 [peek-lsint32 #:-> Fixnum]  [peek-luint32 #:-> Index]]
  [lsb-bytes->long  8 [peek-lsint64 #:-> Integer] [peek-luint64 #:-> Natural]])

(define-peek-integer peek-msize msb-bytes->index #:-> Index)
(define-peek-integer peek-lsize lsb-bytes->index #:-> Index)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define default-stdin-locale : (Parameterof (U Symbol String)) (make-parameter 'utf-8))

(define read-bytes* : (-> Input-Port Natural Bytes)
  (lambda [/dev/stdin size]
    (define bs : (U Bytes EOF) (read-bytes size /dev/stdin))
    (cond [(bytes? bs) bs]
          [(raise (throw-eof-error /dev/stdin 'read-bytes*))])))

(define read-nbytes : (-> Input-Port Natural Bytes)
  (lambda [/dev/stdin size]
    (define bs : (U Bytes EOF) (read-bytes size /dev/stdin))
    (cond [(and (bytes? bs) (= (bytes-length bs) size)) bs]
          [else (throw-eof-error /dev/stdin 'read-nbytes)])))

(define read-nbstring : (-> Input-Port Natural String)
  (lambda [/dev/stdin bsize]
    (bytes->string/utf-8 (read-nbytes /dev/stdin bsize)
                         #false 0 bsize)))

(define read-nlcstring : (-> Input-Port Natural String)
  (lambda [/dev/stdin bsize]
    (define raw : Bytes (read-nbytes /dev/stdin bsize))
    (define lc-all : (U String Symbol) (default-stdin-locale))

    (case lc-all
      [(utf-8) (bytes->string/utf-8 raw #false 0 bsize)]
      [(locale) (bytes->string/locale raw #false 0 bsize)]
      [(latin-1) (bytes->string/latin-1 raw #false 0 bsize)]
      [else (let ([->utf-8 (bytes-open-converter (if (symbol? lc-all) (symbol->string lc-all) lc-all) "UTF-8")])
              (cond [(not ->utf-8) (bytes->string/utf-8 raw #false 0 bsize)]
                    [else (let-values ([(raw/utf-8 n status) (bytes-convert ->utf-8 raw)])
                            (bytes-close-converter ->utf-8)
                            (bytes->string/utf-8 raw/utf-8 #false 0 n))]))])))

(define peek-bytes* : (->* (Input-Port Natural) (Natural) Bytes)
  (lambda [/dev/stdin size [skip 0]]
    (define bs : (U Bytes EOF) (peek-bytes size skip /dev/stdin))
    (if (bytes? bs) bs (throw-eof-error /dev/stdin 'peek-bytes*))))

(define peek-nbytes : (->* (Input-Port Natural) (Natural) Bytes)
  (lambda [/dev/stdin size [skip 0]]
    (define bs : (U Bytes EOF) (peek-bytes size skip /dev/stdin))
    (cond [(and (bytes? bs) (= (bytes-length bs) size)) bs]
          [else (throw-eof-error /dev/stdin 'peek-nbytes)])))

(define peek-nbstring : (-> Input-Port Natural String)
  (lambda [/dev/stdin size]
    (bytes->string/utf-8 (peek-nbytes /dev/stdin size)
                         #false 0 size)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-write-integer* write-fixed-integer #true
  [1 [write-msint8]  [write-muint8]]
  [2 [write-msint16] [write-muint16]]
  [4 [write-msint32] [write-muint32]]
  [8 [write-msint64] [write-muint64]])

(define-write-integer* write-fixed-integer #false
  [1 [write-lsint8]  [write-luint8]]
  [2 [write-lsint16] [write-luint16]]
  [4 [write-lsint32] [write-luint32]]
  [8 [write-lsint64] [write-luint64]])

(define write-mn:bytes : (->* (Bytes Natural) (Output-Port) Nonnegative-Fixnum)
  (lambda [bs nsize [/dev/stdout (current-output-port)]]
    (define bsize : Index (bytes-length bs))
    
    (+ (write-muintptr bsize nsize /dev/stdout)
       (write-nbytes bs bsize /dev/stdout))))

(define write-mn:bstring : (->* (String Natural) (Output-Port) Nonnegative-Fixnum)
  (lambda [s nsize [/dev/stdout (current-output-port)]]
    (define bsize : Index (string-utf-8-length s))
    
    (+ (write-muintptr bsize nsize /dev/stdout)
       (write-nbstring s 0 /dev/stdout))))

(define write-ln:bstring : (->* (String Natural) (Output-Port) Nonnegative-Fixnum)
  (lambda [s nsize [/dev/stdout (current-output-port)]]
    (define bsize : Index (string-utf-8-length s))
    
    (+ (write-luintptr bsize nsize /dev/stdout)
       (write-nbstring s 0 /dev/stdout))))

(define write-msintptr : (->* (Integer Integer) (Output-Port) Byte)
  (lambda [n size [/dev/stdout (current-output-port)]]
    (write-fixed-integer /dev/stdout n size #true #true)))

(define write-lsintptr : (->* (Integer Integer) (Output-Port) Byte)
  (lambda [n size [/dev/stdout (current-output-port)]]
    (write-fixed-integer /dev/stdout n size #true #false)))

(define write-muintptr : (->* (Integer Integer) (Output-Port) Byte)
  (lambda [n size [/dev/stdout (current-output-port)]]
    (write-fixed-integer /dev/stdout n size #false #true)))

(define write-luintptr : (->* (Integer Integer) (Output-Port) Byte)
  (lambda [n size [/dev/stdout (current-output-port)]]
    (write-fixed-integer /dev/stdout n size #false #false)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define write-nbytes : (->* (Bytes Index) (Output-Port) Index)
  (lambda [bs size [/dev/stdout (current-output-port)]]
    (cond [(= size 0) (write-bytes bs /dev/stdout 0 (bytes-length bs))]
          [else (write-bytes bs /dev/stdout 0 size)])))

(define write-nbstring : (->* (String Index) (Output-Port) Index)
  (lambda [s bsize [/dev/stdout (current-output-port)]]
    (cond [(> bsize 0) (write-bytes (string->bytes/utf-8 s) /dev/stdout 0 bsize)]
          [else (let ([ch-size (write-string s /dev/stdout)])
                  (string-utf-8-length s 0 ch-size))])))
