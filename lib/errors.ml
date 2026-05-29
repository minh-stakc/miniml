(** Diagnostics: render a message under the offending source span with a caret
    underline, like

    {v
    2 | let x = 1 + true
                    ^^^^
    this expression has type bool but type int was expected
    v} *)

let format_at ~(src : string) (span : Span.t) (msg : string) : string =
  let lineno = span.Span.lo.Span.line in
  if lineno < 1
  then msg
  else (
    let lines = String.split_on_char '\n' src in
    match List.nth_opt lines (lineno - 1) with
    | None -> msg
    | Some line ->
      let lo = span.Span.lo.Span.col in
      let hi =
        if span.Span.hi.Span.line = lineno
        then span.Span.hi.Span.col
        else String.length line
      in
      let width = max 1 (hi - lo) in
      let gutter = Printf.sprintf "%d | " lineno in
      let pad = String.make (String.length gutter + lo) ' ' in
      let caret = pad ^ String.make width '^' in
      Printf.sprintf "%s%s\n%s\n%s" gutter line caret msg)
;;
