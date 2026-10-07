"""Load a CPSA protocol template from ../protocols/<name>.scm.

Template format (see ../protocols/README.md):
  ;; @name <name>            header lines, each starting with ';; @'
  ;; @U <atom-id> <fact>     one line per generator, in order
  (defprotocol ...)          protocol text, passed to CPSA unchanged
  (defgoal ... @TRUST@ ...)  one goal; @TRUST@ sits inside the hypothesis conjunction
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
PROTO_DIR = os.path.join(os.path.dirname(HERE), 'protocols')
CAND_DIR = os.path.join(HERE, 'candidates')   # excluded candidates, reserve, diagnostics
PLACEHOLDER = '@TRUST@'


class Template:
    def __init__(self, path):
        text = open(path).read()
        self.path = path
        self.meta, self.U = {}, {}
        for line in text.splitlines():
            m = re.match(r';;\s*@(\w+)\s+(.*)$', line)
            if not m:
                continue
            key, val = m.groups()
            if key == 'U':
                atom, fact = val.split(None, 1)
                self.U[atom] = fact.strip()
            else:
                self.meta.setdefault(key, []).append(val.strip())
        self.name = self.meta['name'][0]
        body = '\n'.join(l for l in text.splitlines() if not l.startswith(';; @'))
        i = body.index('(defgoal')
        self.proto, self.goal_text = body[:i].strip() + '\n', body[i:].strip() + '\n'
        if self.goal_text.count(PLACEHOLDER) != 1 or PLACEHOLDER in self.proto:
            raise ValueError(f'{path}: need exactly one {PLACEHOLDER}, in the defgoal')

    def goal(self, facts):
        """defgoal text with the given hypothesis facts (list of fact strings)."""
        return self.goal_text.replace(PLACEHOLDER, '\n           '.join(facts))

    def source(self, facts):
        return f'(herald "{self.name} trust")\n' + self.proto + '\n' + self.goal(facts)


def load(name):
    for d in (PROTO_DIR, CAND_DIR):
        path = os.path.join(d, name + '.scm')
        if os.path.exists(path):
            return Template(path)
    raise FileNotFoundError(name)


def names():
    return sorted(f[:-4] for f in os.listdir(PROTO_DIR) if f.endswith('.scm'))
