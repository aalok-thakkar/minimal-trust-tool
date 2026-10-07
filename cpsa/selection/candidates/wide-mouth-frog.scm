;; @name wide-mouth-frog
;; @source tst/wide-mouth-frog.lsp (defprotocol wide-mouth-frog), protocol text unchanged; the file's herald sets (bound 8), not used here (defaults only)
;; @goal written: responder agreement with the initiator on (a, b, t, k)
;; @excluded CPSA does not finish within 60 s at points containing both non atoms (the file itself notes infinitely many shapes)
;; @U non_ltk_at (non (ltk a t))
;; @U non_ltk_bt (non (ltk b t))
;; @U uniq_k (uniq k)
;; @U uniq_tb (uniq tb)

(defprotocol wide-mouth-frog basic
  (defrole init (vars (a b t name) (ta text) (k skey))
    (trace (send (cat a (enc ta b k (ltk a t))))))
  (defrole resp (vars (a b t name) (k skey) (tb text))
    (trace (recv (enc tb a k (ltk b t)))))
  (defrole ks (vars (a b t name) (k skey) (ta tb text))
    (trace (recv (cat a (enc ta b k (ltk a t))))
	   (send (enc tb a k (ltk b t))))))

(defgoal wide-mouth-frog
  (forall ((a b t name) (k skey) (tb text) (z strd))
    (implies
      (and (p "resp" z 1) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "t" z t) (p "resp" "k" z k) (p "resp" "tb" z tb)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 1) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "t" z-0 t) (p "init" "k" z-0 k))))))
