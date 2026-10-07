(defgoal kerberos
  (forall ((a b ks name) (t t-prime l text) (k skey) (z strd))
    (implies
      (and (p "init" z 4) (p "init" "a" z a) (p "init" "b" z b)
           (p "init" "ks" z ks) (p "init" "t" z t) (p "init" "t-prime" z t-prime)
           (p "init" "l" z l) (p "init" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "resp" z-0 2) (p "resp" "a" z-0 a) (p "resp" "b" z-0 b)
             (p "resp" "k" z-0 k))))))
