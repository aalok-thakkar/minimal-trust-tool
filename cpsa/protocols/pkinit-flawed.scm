;; @name pkinit-flawed
;; @source tst/pkinit.scm (defprotocol pkinit), renamed pkinit-flawed; otherwise identical to the shipped text; re-derived from artifact/pkinit_mintrust.py
;; @goal written (existing row): client authenticates the server, agreement with an auth strand on (c, as, k)
;; @note role declarations uniq-orig n1 n2 [client] and uniq-orig k ak [auth] stay in sigma
;; @U non_as (non (privk as))
;; @U non_c (non (privk c))

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
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "auth" z-0 1) (p "auth" "as" z-0 as)
             (p "auth" "k" z-0 k) (p "auth" "c" z-0 c))))))
