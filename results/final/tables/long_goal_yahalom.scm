(defgoal yahalom
  (forall ((a b c name) (n-a n-b text) (k skey) (z strd))
    (implies
      (and (p "resp" z 4) (p "resp" "a" z a) (p "resp" "b" z b) (p "resp" "c" z c)
           (p "resp" "n-a" z n-a) (p "resp" "n-b" z n-b) (p "resp" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "c" z-0 c) (p "init" "k" z-0 k))))))
