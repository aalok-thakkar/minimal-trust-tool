;; @name neuman-stubblebine
;; @source tst/neuman-stubblebine.scm (defprotocol neuman-stubblebine), protocol text unchanged
;; @goal written: responder agreement with the initiator on (a, b, k)
;; @U non_ltk_aks (non (ltk a ks))
;; @U non_ltk_bks (non (ltk b ks))
;; @U uniq_ra (uniq ra)
;; @U uniq_rb (uniq rb)
;; @U uniq_tb (uniq tb)

(defprotocol neuman-stubblebine basic
  (defrole init (vars (a b ks name) (ra rb text) (k skey) (tb text))
    (trace
     (send (cat a ra))
     (recv (cat (enc b ra k tb (ltk a ks))
		(enc a k tb (ltk b ks)) rb))
     (send (cat (enc a k tb (ltk b ks)) (enc rb k)))))
  (defrole resp (vars (a b ks name) (ra rb text) (k skey) (tb text))
    (trace
     (recv (cat a ra))
     (send (cat b rb (enc a ra tb (ltk b ks))))
     (recv (cat (enc a k tb (ltk b ks)) (enc rb k)))))
  (defrole keyserver
    (vars (a b ks name) (ra rb text) (k skey) (tb text))
    (trace
     (recv (cat b rb (enc a ra tb (ltk b ks))))
     (send (cat (enc b ra k tb (ltk a ks))
		(enc a k tb (ltk b ks)) rb)))
    (uniq-orig k)))

(defgoal neuman-stubblebine
  (forall ((a b ks name) (ra rb tb text) (k skey) (z strd))
    (implies
      (and (p "resp" z 3) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "ks" z ks) (p "resp" "ra" z ra) (p "resp" "rb" z rb)
           (p "resp" "tb" z tb) (p "resp" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "k" z-0 k))))))
