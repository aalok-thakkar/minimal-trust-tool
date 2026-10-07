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
