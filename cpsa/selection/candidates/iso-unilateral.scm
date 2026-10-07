;; @name iso-unilateral
;; @excluded t1, t2, t3 are the ISO Text fields, not nonces; under the rule U = {non_privk_b}, |U| = 1. This file keeps the first-pass U (sort rule).
;; @source tst/unilateral.scm (defprotocol iso-unilateral), protocol text unchanged
;; @goal shipped: first defgoal iso-unilateral in tst/unilateral.scm, hypothesis fact (non (privk b)) replaced by the trust placeholder
;; @note role declarations uniq-orig na [resp] and uniq-orig nb [init] stay in sigma
;; @U non_privk_b (non (privk b))
;; @U uniq_t1 (uniq t1)
;; @U uniq_t2 (uniq t2)
;; @U uniq_t3 (uniq t3)

(defprotocol iso-unilateral basic
  (defrole resp
    (vars (na nb t1 t2 t3 text) (b name))
    (trace
     (recv (cat nb t1))
     (send (cat na nb b t3 (enc na nb b t2 (privk b)))))
    (uniq-orig na))
  (defrole init
    (vars (na nb t1 t2 t3 text) (b name))
    (trace
     (send (cat nb t1))
     (recv (cat na nb b t3 (enc na nb b t2 (privk b)))))
    (uniq-orig nb))
  (comment "Two pass authentication"))

(defgoal iso-unilateral
  (forall ((b name) (t1 t2 t3 text) (z strd))
    (implies
     (and (p "init" z 2)
	  (p "init" "b" z b)
	  (p "init" "t1" z t1) (p "init" "t2" z t2) (p "init" "t3" z t3)
	  @TRUST@)
      (exists ((y strd))
	      (and (p "resp" y 2)
		   (p "resp" "b" y b))))))
