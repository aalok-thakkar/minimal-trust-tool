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
