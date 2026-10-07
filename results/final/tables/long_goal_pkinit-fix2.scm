(defgoal pkinit-fix2
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
