;; @name yahalom
;; @source tst/yahalom.scm (defprotocol yahalom), protocol text unchanged; re-derived from artifact/cpsa/protocols.py
;; @goal written (existing row): responder agreement with the initiator on (a, b, c, k)
;; @U non_ltk_ac (non (ltk a c))
;; @U non_ltk_bc (non (ltk b c))
;; @U uniq_na (uniq n-a)
;; @U uniq_nb (uniq n-b)

(defprotocol yahalom basic
  (defrole init
    (vars (a b c name) (n-a n-b text) (k skey))
    (trace (send (cat a n-a))
           (recv (enc b k n-a n-b (ltk a c)))
           (send (enc n-b k))))
  (defrole resp
    (vars (b a c name) (n-a n-b text) (k skey))
    (trace (recv (cat a n-a))
           (send (cat b (enc a n-a n-b (ltk b c))))
           (recv (enc a k (ltk b c)))
           (recv (enc n-b k))))
  (defrole serv
    (vars (c a b name) (n-a n-b text) (k skey))
    (trace (recv (cat b (enc a n-a n-b (ltk b c))))
           (send (enc b k n-a n-b (ltk a c)))
           (send (enc a k (ltk b c))))
    (uniq-orig k)))

(defgoal yahalom
  (forall ((a b c name) (n-a n-b text) (k skey) (z strd))
    (implies
      (and (p "resp" z 4) (p "resp" "a" z a) (p "resp" "b" z b) (p "resp" "c" z c)
           (p "resp" "n-a" z n-a) (p "resp" "n-b" z n-b) (p "resp" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "c" z-0 c) (p "init" "k" z-0 k))))))
