;; @name denning-sacco
;; @source tst/denning-sacco.scm (defprotocol denning-sacco), protocol text unchanged
;; @goal written: responder agreement with the initiator on (a, b, k)
;; @U non_privk_a (non (privk a))
;; @U non_privk_b (non (privk b))
;; @U non_privk_ks (non (privk ks))
;; @U uniq_k (uniq k)
;; @U uniq_ta (uniq ta)

(defprotocol denning-sacco basic
  (defrole init (vars (a b ks name) (k skey) (ta text))
    (trace
     (send (cat a b))
     (recv (cat (enc b (pubk b) (privk ks))
		(enc a (pubk a) (privk ks))))
     (send (enc (enc a b k ta (privk a))
		(enc b (pubk b) (privk ks))
		(enc a (pubk a) (privk ks)) (pubk b)))))
  (defrole resp (vars (a b ks name) (k skey) (ta text))
    (trace
     (recv (enc (enc a b k ta (privk a))
		(enc b (pubk b) (privk ks))
		(enc a (pubk a) (privk ks)) (pubk b)))))
  (defrole keyserver (vars (a b ks name))
    (trace
     (recv (cat a b))
     (send (cat (enc b (pubk b) (privk ks))
		(enc a (pubk a) (privk ks)))))))

(defgoal denning-sacco
  (forall ((a b ks name) (k skey) (ta text) (z strd))
    (implies
      (and (p "resp" z 1) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "ks" z ks) (p "resp" "k" z k) (p "resp" "ta" z ta)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "k" z-0 k))))))
