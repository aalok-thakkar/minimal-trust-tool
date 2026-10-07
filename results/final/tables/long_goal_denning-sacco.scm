(defgoal denning-sacco
  (forall ((a b ks name) (k skey) (ta text) (z strd))
    (implies
      (and (p "resp" z 1) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "ks" z ks) (p "resp" "k" z k) (p "resp" "ta" z ta)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "k" z-0 k))))))
