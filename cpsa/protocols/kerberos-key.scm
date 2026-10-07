;; @name kerberos-key
;; @note row (author decision 2026-10-04): kerberos with the conclusion weakened to agreement on k alone
;; @source tst/kerberos.scm (defprotocol kerberos), protocol text unchanged
;; @goal written: initiator agreement with some responder strand on k (names not required to match)
;; @U non_ltk_aks (non (ltk a ks))
;; @U non_ltk_bks (non (ltk b ks))
;; @U uniq_t (uniq t)
;; @U uniq_tp (uniq t-prime)
;; @note l is the ticket lifetime, not a nonce or timestamp: no uniq atom (first pass had one, see selection/candidates/kerberos-sortrule.scm)

(defprotocol kerberos basic
  (defrole init
    (vars (a name) (b name) (ks name) (t text) (t-prime text) (l text) (k skey))
    (trace (send (cat a b))
      (recv
        (cat (enc (cat t l k b) (ltk a ks))
          (enc (cat t l k a) (ltk b ks))))
      (send (cat (enc (cat a t) k) (enc (cat t l k a) (ltk b ks))))
      (recv (enc t-prime k))))
  (defrole resp
    (vars (a name) (b name) (ks name) (t text) (t-prime text) (l text) (k skey))
    (trace (recv (cat (enc (cat a t) k) (enc (cat t l k a) (ltk b ks))))
      (send (enc t-prime k))))
  (defrole keyserver
    (vars (a name) (b name) (ks name) (t text) (l text) (k skey))
    (trace (recv (cat a b))
      (send
        (cat (enc (cat t l k b) (ltk a ks))
          (enc (cat t l k a) (ltk b ks))))) (uniq-orig k)))

(defgoal kerberos
  (forall ((a b ks name) (t t-prime l text) (k skey) (z strd))
    (implies
      (and (p "init" z 4) (p "init" "a" z a) (p "init" "b" z b)
           (p "init" "ks" z ks) (p "init" "t" z t) (p "init" "t-prime" z t-prime)
           (p "init" "l" z l) (p "init" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "resp" z-0 2) (p "resp" "k" z-0 k))))))
