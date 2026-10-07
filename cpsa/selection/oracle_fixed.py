"""reference/python/cpsa/cpsa_oracle.py with one correction to the replay check (survives).

The reference survives(x, M) adds M to shape x, runs cpsa4, and reads x as surviving iff
CPSA's first output skeleton (label 0) carries (realized). When an added (uniq-orig v)
names a value that x originates on two strands, CPSA does not reject the input: it
prints label 0 as a (preskeleton) with (comment "Not a skeleton"), still marked
(realized), and then collapses the two strands into a different skeleton (label 1).
In other cases it prints label 0 as (realized) (dead) with (comment "Input cannot be
made into a skeleton--nothing to do"). The reference reads both as "x survives", so
stops(x) can miss uniq atoms and the loop can return a wrong (too strong) answer. Found on otway-rees-neq, see ../protocols/MANIFEST.md.

Correction: x survives only if label 0 is realized and has neither a (preskeleton) nor a
(dead) field. x violates the added uniq atom otherwise, which is what
reference/python/cpsa/notes_stops.md intends
("If CPSA rejects the skeleton as ill-formed ... x does not survive").
The file in reference/python/ is not modified; this class overrides the one method.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'reference', 'python')
sys.path.insert(0, os.path.join(ART, 'cpsa'))

import cpsa_oracle as co


class FixedOracle(co.CPSAOracle):
    def survives(self, shape, binding, atoms):
        env = {}
        for b in binding[1:]:
            if isinstance(b, list) and len(b) == 2 and isinstance(b[0], str):
                env[b[0]] = b[1]
        extra = {}
        for atom in atoms:
            fact = co.subst(co.parse_all(self.U[atom])[0], env)
            slot = {'non': 'non-orig', 'uniq': 'uniq-orig'}[fact[0]]
            extra.setdefault(slot, []).append(fact[1])
        keep = ('vars', 'defstrand', 'deflistener', 'defstrandmax', 'precedes', 'leadsto',
                'non-orig', 'pen-non-orig', 'uniq-orig', 'uniq-gen', 'absent', 'conf',
                'auth', 'facts', 'priority')
        sk = ['defskeleton', shape[1]]
        for x in shape[2:]:
            if isinstance(x, list) and x and x[0] in keep:
                if x[0] in extra:
                    x = x + [t for t in extra.pop(x[0]) if t not in x[1:]]
                sk.append(x)
        for slot, terms in extra.items():
            sk.append([slot] + terms)
        src = '(herald "stops check")\n' + self.proto + '\n' + co.show(sk) + '\n'
        out, err, dt = co.run_cpsa(src)
        self.stats.check_calls += 1; self.stats.check_time += dt
        if err.strip():
            return False, 'ill-formed: ' + err.strip().splitlines()[-1]
        sks = co.skeletons(out)
        first = sks[0] if sks else None
        # the correction: an input CPSA could not take as a skeleton is not x
        for flag in ('preskeleton', 'dead'):
            if first is not None and co.field(first, flag):
                return False, flag
        realized = first is not None and bool(co.field(first, 'realized'))
        if realized and not co.field(first, 'shape'):
            self.stats.log.append('  note: label 0 realized skeleton not marked (shape)')
        return realized, ('realized' if realized else 'unrealized')
