(defgoal blanchet
  (forall ((a b name) (s skey) (d data) (z z-0 strd))
    (implies
      (and (p "resp" z 2) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "s" z s) (p "resp" "d" z d)
           (p "" z-0 1) (p "" "x" z-0 d)
           @TRUST@)
      (false))))
