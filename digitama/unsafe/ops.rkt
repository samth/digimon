#lang typed/racket/base

(provide (all-defined-out))
(provide unsafe-vector*-ref unsafe-vector*-set!)
(provide unsafe-bytes-ref unsafe-bytes-set! unsafe-bytes-copy!)
(provide unsafe-fx+ unsafe-fx- unsafe-fx* unsafe-fxquotient unsafe-fxremainder)
(provide unsafe-fxand unsafe-fxior unsafe-fxlshift unsafe-fxrshift)
(provide unsafe-idx+ unsafe-idx- unsafe-idx* unsafe-idxxor unsafe-idxlshift unsafe-idxrshift unsafe-brshift)
(provide unsafe-fl->fx unsafe-fx->fl unsafe-flfloor unsafe-flceiling unsafe-flround unsafe-fltruncate)

(require racket/unsafe/ops)
(require typed/racket/unsafe)

(unsafe-require/typed
 racket/unsafe/ops
 [(unsafe-fx* unsafe-idx*) (-> Natural Natural Index)]
 [(unsafe-fx+ unsafe-idx+) (-> Natural Natural Index)]
 [(unsafe-fx- unsafe-idx-) (case-> [Byte Byte -> Byte]
                                   [Zero Negative-Fixnum -> Index]
                                   [Natural Natural -> Index])]
 [(unsafe-fxxor unsafe-idxxor) (-> Integer Natural Index)]
 [(unsafe-fxlshift unsafe-idxlshift) (case-> [Positive-Integer Fixnum -> Positive-Index]
                                             [Natural Fixnum -> Index])]
 [(unsafe-fxrshift unsafe-idxrshift) (case-> [Byte Byte -> Byte]
                                             [Natural Byte -> Index]
                                             [Natural Natural -> Index])]
 [(unsafe-fxrshift unsafe-brshift) (case-> [Index Byte -> Byte])])

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Racket `bitwise-not` always returns a negative number for natural.
; The safe version would be `(~n) & #xFFFF` or `(n & #xFFFF) ^ #xFFFF`

(define unsafe-uint16-not : (-> Integer Index)
  (lambda [n]
    (unsafe-idxxor n #xFFFF)))

(define unsafe-uint32-not : (-> Integer Index)
  (lambda [n]
    (unsafe-idxxor n #xFFFFFFFF)))