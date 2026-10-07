(herald "pkinit mintrust")

(defprotocol pkinit-flawed basic
  (defrole client
    (vars (c t as name) (n2 n1 text) (tc tk tgt data) (k ak skey))
    (trace (send (cat (enc tc n2 (privk c)) c t n1))
      (recv (cat (enc (enc k n2 (privk as)) (pubk c)) c tgt (enc ak n1 tk t k))))
    (uniq-orig n1 n2))
  (defrole auth
    (vars (c t as name) (n2 n1 text) (tc tk tgt data) (k ak skey))
    (trace (recv (cat (enc tc n2 (privk c)) c t n1))
      (send (cat (enc (enc k n2 (privk as)) (pubk c)) c tgt (enc ak n1 tk t k))))
    (uniq-orig k ak)))

(defgoal pkinit-flawed
  (forall ((c as name) (k skey) (z strd))
    (implies
      (and (p "client" z 2)
           (p "client" "c" z c)
           (p "client" "as" z as)
           (p "client" "k" z k)
                (non (privk as))
                (non (privk c)))
      (exists ((z-0 strd))
        (and (p "auth" z-0 1) (p "auth" "as" z-0 as)
             (p "auth" "k" z-0 k) (p "auth" "c" z-0 c))))))
