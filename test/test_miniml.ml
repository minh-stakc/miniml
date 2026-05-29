(** Test runner: aggregates the per-layer suites. Each [Test_*] module exposes a
    [suites] value; this is the single entry point that runs them all. *)

let () = Alcotest.run "miniml" (Test_parser.suites @ Test_infer.suites)
