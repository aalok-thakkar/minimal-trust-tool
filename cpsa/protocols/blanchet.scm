;; @name blanchet
;; @source tst/blanchet.scm (defprotocol blanchet), protocol text unchanged (comments dropped)
;; @goal written: secrecy of d from the responder's point of view (the shipped skeleton 4 for this protocol, resp + deflistener d, as a goal)
;; @U non_privk_a (non (privk a))
;; @U non_privk_b (non (privk b))
;; @note secondary candidate (not on the preferred list); admitted for the secrecy goal class, see MANIFEST.md
;; @U uniq_s (uniq s)
;; @U uniq_d (uniq d)

(defprotocol blanchet basic
  (defrole init
    (vars (a b name) (s skey) (d data))
    (trace
     (send (enc (enc s (privk a)) (pubk b)))
     (recv (enc d s))))
  (defrole resp
    (vars (a b name) (s skey) (d data))
    (trace
     (recv (enc (enc s (privk a)) (pubk b)))
     (send (enc d s)))))

(defgoal blanchet
  (forall ((a b name) (s skey) (d data) (z z-0 strd))
    (implies
      (and (p "resp" z 2) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "s" z s) (p "resp" "d" z d)
           (p "" z-0 1) (p "" "x" z-0 d)
           @TRUST@)
      (false))))
