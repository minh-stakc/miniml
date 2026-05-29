(** Test runner: aggregates the per-layer suites. Each [Test_*] module exposes a
    [suites] value; this is the single entry point that runs them all. *)

let () =
  Alcotest.run
    "miniml"
    (Test_parser.suites
     @ Test_infer.suites
     @ Test_exhaust.suites
     @ Test_eval.suites
     @ Test_vm.suites
     @ Test_soundness.suites
     @ Test_driver.suites
     @ Test_refs.suites)
;;
