;; @name woolam
;; @source tst/woolam.scm (defprotocol woolam), protocol text unchanged
;; @goal written: responder agreement with the initiator on (a, s, n)
;; @note role declarations non-orig (ltk a s) [init], non-orig (ltk b s) and uniq-orig n [resp] stay in sigma
;; @excluded |U| = 1 after removing role-declared atoms
;; @U non_ltk_as (non (ltk a s))

(defprotocol woolam basic
  (defrole init (vars (a s name) (n text))
    (trace
     (send a)
     (recv n)
     (send (enc n (ltk a s))))
    (non-orig (ltk a s)))
  (defrole resp (vars (a s b name) (n text))
    (trace
     (recv a)
     (send n)
     (recv (enc n (ltk a s)))
     (send (enc a (enc n (ltk a s)) (ltk b s)))
     (recv (enc a n (ltk b s))))
    (non-orig (ltk b s))
    (uniq-orig n))
  (defrole serv (vars (a s b name) (n text))
    (trace
     (recv (enc a (enc n (ltk a s)) (ltk b s)))
     (send (enc a n (ltk b s))))))

(defgoal woolam
  (forall ((a s b name) (n text) (z strd))
    (implies
      (and (p "resp" z 5) (p "resp" "a" z a) (p "resp" "s" z s)
           (p "resp" "b" z b) (p "resp" "n" z n)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "s" z-0 s)
             (p "init" "n" z-0 n))))))
