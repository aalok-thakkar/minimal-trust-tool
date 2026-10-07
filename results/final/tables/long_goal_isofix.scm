(defgoal isofix
  (forall ((a b name) (na nb nc text) (z strd))
    (implies
      (and (p "resp" z 3) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "na" z na) (p "resp" "nb" z nb) (p "resp" "nc" z nc)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "nb" z-0 nb))))))
