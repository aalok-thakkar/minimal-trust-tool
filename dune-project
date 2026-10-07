(lang dune 3.0)

(name minimal-trust-tool)

(generate_opam_files true)

(source
 (github aalok-thakkar/minimal-trust-tool))

(authors "Bhumika Mittal" "Aalok Thakkar")

(maintainers "Aalok Thakkar")

(license MIT)

(homepage "https://github.com/aalok-thakkar/minimal-trust-tool")

(bug_reports "https://github.com/aalok-thakkar/minimal-trust-tool/issues")

(package
 (name minimal-trust-tool)
 (synopsis "Weakest trust assumptions a security protocol needs for a goal")
 (description
  "Computes the minimal sets of trust assumptions (uncompromised keys, fresh values, authentic or confidential channels) under which a protocol achieves a security goal, by a counterexample-guided loop over a protocol verifier. Includes a bounded Dolev-Yao analyser, a CPSA 4 oracle, and the experiment drivers for the paper 'Trust a Few: The Weakest Assumptions a Protocol Needs'.")
 (depends
  (ocaml
   (>= 5.1))))
