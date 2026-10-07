;; @name otway-rees-neq
;; @diagnostic not a row: otway-rees with a != b added to the situation (rule neq + fact in the hypothesis)
;; @source tst/or.scm (defprotocol or), protocol text unchanged
;; @goal written: responder agreement with the initiator on (a, b, s, m)
;; @U non_ltk_as (non (ltk a s))
;; @U non_ltk_bs (non (ltk b s))
;; @U uniq_m (uniq m)
;; @U uniq_nb (uniq nb)

(defprotocol or basic
  (defrole init (vars (a b s name) (na text) (k skey) (m text))
    (trace
     (send (cat m a b (enc na m a b (ltk a s))))
     (recv (cat m (enc na k (ltk a s))))))
  (defrole resp
    (vars (a b s name) (nb text) (k skey) (m text) (x y mesg))
    (trace
     (recv (cat m a b x))
     (send (cat m a b x (enc nb m a b (ltk b s))))
     (recv (cat m y (enc nb k (ltk b s))))
     (send y)))
  (defrole serv (vars (a b s name) (na nb text) (k skey) (m text))
    (trace
     (recv (cat m a b (enc na m a b (ltk a s))
		(enc nb m a b (ltk b s))))
     (send (cat m (enc na k (ltk a s)) (enc nb k (ltk b s)))))
    (uniq-orig k))
  (defrule neq
    (forall ((x mesg))
      (implies (fact neq x x) (false)))))

(defgoal or
  (forall ((a b s name) (m nb text) (k skey) (z strd))
    (implies
      (and (p "resp" z 4) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "s" z s) (p "resp" "m" z m) (p "resp" "nb" z nb)
           (p "resp" "k" z k) (fact neq a b)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 1) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "s" z-0 s) (p "init" "m" z-0 m))))))
