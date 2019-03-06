(** Copyright (c) 2016-present, Facebook, Inc.

    This source code is licensed under the MIT license found in the
    LICENSE file in the root directory of this source tree. *)

open OUnit2

open Core

open Ast
open Expression
open Server
open Protocol
open Pyre
open Test


let test_parse_query context =
  let configuration = Configuration.Analysis.create ~local_root:(mock_path "") () in
  let assert_parses serialized query =
    assert_equal
      ~cmp:Request.equal
      ~printer:Request.show
      (Request.TypeQueryRequest query)
      (Commands.Query.parse_query ~configuration serialized)
  in

  let assert_fails_to_parse serialized =
    try
      Commands.Query.parse_query ~configuration serialized
      |> ignore;
      assert_unreached ()
    with Commands.Query.InvalidQuery _ ->
      ()
  in

  assert_parses
    "less_or_equal(int, bool)"
    (LessOrEqual (Access.create "int", Access.create "bool"));
  assert_parses
    "less_or_equal (int, bool)"
    (LessOrEqual (Access.create "int", Access.create "bool"));
  assert_parses
    "less_or_equal(  int, int)"
    (LessOrEqual (Access.create "int", Access.create "int"));
  assert_parses
    "Less_Or_Equal(  int, int)"
    (LessOrEqual (Access.create "int", Access.create "int"));

  assert_parses
    "meet(int, bool)"
    (Meet (Access.create "int", Access.create "bool"));
  assert_parses
    "join(int, bool)"
    (Join (Access.create "int", Access.create "bool"));

  assert_fails_to_parse "less_or_equal()";
  assert_fails_to_parse "less_or_equal(int, int, int)";
  assert_fails_to_parse "less_or_eq(int, bool)";

  assert_fails_to_parse "meet(int, int, int)";
  assert_fails_to_parse "meet(int)";

  assert_fails_to_parse "join(int)";
  assert_parses "superclasses(int)" (Superclasses (Access.create "int"));
  assert_fails_to_parse "superclasses()";
  assert_fails_to_parse "superclasses(int, bool)";

  assert_parses "normalize_type(int)" (NormalizeType (Access.create "int"));
  assert_fails_to_parse "normalizeType(int, str)";

  assert_equal
    (Commands.Query.parse_query ~configuration "type_check('derp/fiddle.py')")
    (Request.TypeCheckRequest
       (TypeCheckRequest.create
          ~check:[
            File.create (Path.create_relative ~root:(mock_path "") ~relative:"derp/fiddle.py");
          ]
          ()
       ));

  assert_parses "type(C)" (Type (!"C"));
  assert_parses "type((C,B))" (Type (+(Ast.Expression.Tuple [!"C"; !"B"])));
  assert_fails_to_parse "type(a.b, c.d)";

  assert_fails_to_parse "typecheck(1+2)";

  assert_parses
    "type_at_position('a.py', 1, 2)"
    (TypeAtPosition {
        file = File.create (Path.create_relative ~root:(mock_path "") ~relative:"a.py");
        position = { Ast.Location.line = 1; column = 2 };
      });
  assert_fails_to_parse "type_at_position(a.py:1:2)";
  assert_fails_to_parse "type_at_position('a.py', 1, 2, 3)";

  assert_parses
    "types_in_file('a.py')"
    (TypesInFile (File.create (Path.create_relative ~root:(mock_path "") ~relative:"a.py")));
  assert_fails_to_parse "types_in_file(a.py:1:2)";
  assert_fails_to_parse "types_in_file(a.py)";
  assert_fails_to_parse "types_in_file('a.py', 1, 2)";

  assert_parses "attributes(C)" (Attributes (Access.create "C"));
  assert_fails_to_parse "attributes(C, D)";

  assert_parses "signature(a.b)" (Signature (Access.create "a.b"));
  assert_fails_to_parse "signature(a.b, a.c)";

  assert_parses "save_server_state('state')"
    (SaveServerState
       (Path.create_absolute
          ~follow_symbolic_links:false
          "state"));
  assert_fails_to_parse "save_server_state(state)";

  assert_parses "dump_dependencies('quoted.py')"
    (DumpDependencies
       (File.create (Path.create_relative ~root:(mock_path "") ~relative:"quoted.py")));
  assert_fails_to_parse "dump_dependencies(unquoted)";

  assert_parses
    "dump_memory_to_sqlite()"
    (DumpMemoryToSqlite (Path.create_relative ~root:(mock_path "") ~relative:".pyre/memory.sqlite"));
  let memory_file, _ = bracket_tmpfile context in
  assert_parses
    (Format.sprintf "dump_memory_to_sqlite('%s')" memory_file)
    (DumpMemoryToSqlite (Path.create_absolute memory_file));
  assert_parses
    (Format.sprintf "dump_memory_to_sqlite('a.sqlite')")
    (DumpMemoryToSqlite
       (Path.create_relative
          ~root:(Path.current_working_directory ())
          ~relative:"a.sqlite"));

  assert_parses "path_of_module(a.b.c)" (PathOfModule (Expression.Access.create "a.b.c"));
  assert_fails_to_parse "path_of_module('a.b.c')";
  assert_fails_to_parse "path_of_module(a.b, b.c)"


let () =
  "query">:::[
    "parse_query">::test_parse_query;
  ]
  |> Test.run
