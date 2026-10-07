;; @name isofix
;; @source tst/isoreject-corrected.scm (defprotocol isofix), protocol text unchanged
;; @goal written: responder agreement with the initiator on (a, b, nb) (same goal as isoreject)
;; @U non_privk_a (non (privk a))
;; @U non_privk_b (non (privk b))
;; @U uniq_na (uniq na)
;; @U uniq_nc (uniq nc)

(defprotocol isofix basic
  (defrole init (vars (a b name) (na nb nc text))
    (trace
     (send (cat a na))
     (recv (enc "first" nb na a (privk b)))
     (send (enc "second" nc nb b (privk a)))))
  (defrole resp (vars (a b name) (na nb nc text))
    (trace
     (recv (cat a na))
     (send (enc "first" nb na a (privk b)))
     (recv (enc "second" nc nb b (privk a))))
    (uniq-orig nb)))

(defgoal isofix
  (forall ((a b name) (na nb nc text) (z strd))
    (implies
      (and (p "resp" z 3) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "na" z na) (p "resp" "nb" z nb) (p "resp" "nc" z nc)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "nb" z-0 nb))))))
