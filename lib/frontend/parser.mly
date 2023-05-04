%{
open Common
open Sugar_ast
open Common_types

let parse_error x = Errors.Parse_error x

let binary_op op_name x1 x2 = App { func = Primitive op_name; args = [x1; x2] }

%}
(* Tokens *)
%token <int> INT
%token <bool> BOOL
%token <string> STRING
%token <string> VARIABLE
%token <string> CONSTRUCTOR

(* %token NULL *)
%token LEFT_BRACE RIGHT_BRACE
%token LEFT_BRACK RIGHT_BRACK
%token LEFT_PAREN RIGHT_PAREN
%token SEMICOLON
%token COLON
%token COMMA
(*
These will be added in later
%token <string> CONSTRUCTOR
%token <float> FLOAT
*)
%token BANG
%token QUERY
%token DOT
%token STAR
%token EQ
%token EOF
%token RIGHTARROW
%token LOLLI
%token PLUS
%token DIV

(* Keyword tokens *)
%token LET
%token SPAWN
%token NEW
%token GUARD
%token RECEIVE
%token FREE
%token FAIL
%token IN
%token FUN
%token LINFUN
%token FROM
%token INTERFACE
%token DEF
%token IF
%token ELSE
%token MINUS
%token GEQ
%token LT
%token GT
%token LEQ
%token EQQ
%token NEQ
%token AND
%token OR

(* Start parsing *)
%start <expr> expr_main
%start <program> program

%%

message:
    | CONSTRUCTOR LEFT_PAREN separated_list(COMMA, expr) RIGHT_PAREN { ($1, $3) }

message_binder:
    | CONSTRUCTOR LEFT_PAREN separated_list(COMMA, VARIABLE) RIGHT_PAREN { ($1, $3) }

expr:
    (* Let *)
    | LET VARIABLE EQ expr IN expr { Let { binder = $2; term = $4; body = $6 } }
    | LET LEFT_PAREN VARIABLE COMMA VARIABLE RIGHT_PAREN EQ basic_expr IN expr
        { LetPair { binders = ($3, $5); term = $8; cont = $10 } }
    | basic_expr SEMICOLON expr { Seq ($1, $3) }
    | basic_expr COLON ty { Annotate ($1, $3) }
    | basic_expr { $1 }

expr_list:
    | separated_list(COMMA, expr) { $1 }

linearity:
    | FUN    { false }
    | LINFUN { true }

basic_expr:
    (* New *)
    | NEW LEFT_BRACK interface_name RIGHT_BRACK { New $3 }
    (* Spawn *)
    | SPAWN LEFT_BRACE expr RIGHT_BRACE { Spawn $3 }
    (* Sugared Free and Fail forms *)
    | FREE LEFT_PAREN expr RIGHT_PAREN { SugarFree $3 }
    | FAIL LEFT_PAREN expr RIGHT_PAREN LEFT_BRACK ty RIGHT_BRACK { SugarFail ($3, $6)}
    | LEFT_PAREN expr COMMA expr RIGHT_PAREN { Pair ($2, $4) }
    (* App *)
    | fact LEFT_PAREN expr_list RIGHT_PAREN
        { App { func = $1; args = $3 } }
    (* Lam *)
    | linearity LEFT_PAREN annotated_var_list RIGHT_PAREN COLON ty LEFT_BRACE expr RIGHT_BRACE
        { Lam { linear = $1; parameters = $3; result_type = $6; body = $8 } }
    (* Send *)
    | fact BANG message { Send { target = $1; message = $3; iname = None } }
    (* If-Then-Else *)
    | IF LEFT_PAREN expr RIGHT_PAREN LEFT_BRACE expr RIGHT_BRACE ELSE LEFT_BRACE expr RIGHT_BRACE
        { If { test = $3; then_expr = $6; else_expr = $10 } }
    (* Guard *)
    | GUARD basic_expr COLON pat LEFT_BRACE guard+ RIGHT_BRACE
        { Guard {
            target = $2;
            pattern = $4;
            guards = $6;
            iname = None
          }
        }
    | rel_op { $1 }

rel_op:
    | mult_op AND rel_op { binary_op "&&" $1 $3 }
    | mult_op OR rel_op { binary_op "||" $1 $3 }
    | mult_op EQQ rel_op { binary_op "==" $1 $3 }
    | mult_op NEQ rel_op { binary_op "!=" $1 $3 }
    | mult_op LT rel_op { binary_op "<" $1 $3 }
    | mult_op GT rel_op { binary_op ">" $1 $3 }
    | mult_op LEQ rel_op { binary_op "<=" $1 $3 }
    | mult_op GEQ rel_op { binary_op ">=" $1 $3 }
    | mult_op { $1 }

mult_op:
    | add_op STAR mult_op { binary_op "*" $1 $3 }
    | add_op DIV mult_op { binary_op "/" $1 $3 }
    | add_op { $1 }

add_op:
    | fact PLUS add_op { binary_op "+" $1 $3 }
    | fact MINUS add_op { binary_op "-" $1 $3 }
    | fact { $1 }

fact:
    (* Unit *)
    | LEFT_PAREN RIGHT_PAREN { Constant Constant.unit }
    | BOOL   { Constant (Constant.wrap_bool $1) }
    (* Var *)
    | VARIABLE {
        if List.mem_assoc $1 (Lib_types.signatures) then
            Primitive $1
        else
            Var $1
    }
    (* Constant *)
    | INT    { Constant (Constant.wrap_int $1) }
    | STRING { Constant (Constant.wrap_string $1) }
    | LEFT_PAREN expr RIGHT_PAREN { $2 }


guard:
    | FAIL COLON ty { Fail $3 }
    | FREE RIGHTARROW expr { Free $3 }
    | RECEIVE message_binder FROM VARIABLE RIGHTARROW expr
            { let (tag, bnds) = $2 in
              Receive { tag; payload_binders = bnds;
                        mailbox_binder = $4; cont = $6 }
            }

(* Type parser *)

ty_list:
    | separated_nonempty_list(COMMA, ty) { $1 }

parenthesised_datatypes:
    | LEFT_PAREN RIGHT_PAREN { [] }
    | LEFT_PAREN ty_list RIGHT_PAREN { $2 }

ty:
    | parenthesised_datatypes RIGHTARROW simple_ty  { Type.Fun { linear = false; args = $1; result = $3} }
    | parenthesised_datatypes LOLLI simple_ty       { Type.Fun { linear = true;  args = $1; result = $3} }
    | simple_ty { $1 }

interface_name:
    | CONSTRUCTOR { $1 }

pat:
    | star_pat PLUS pat { Type.Pattern.Plus ($1, $3) }
    | star_pat DOT pat  { Type.Pattern.Concat ($1, $3) }
    | star_pat          { $1 }

star_pat:
    | STAR simple_pat   { Type.Pattern.Many $2 }
    | simple_pat        { $1 }

simple_pat:
    | CONSTRUCTOR { Type.Pattern.Message $1 }
    | INT {
            match $1 with
                | 0 -> Type.Pattern.Zero
                | 1 -> Type.Pattern.One
                | _ -> raise (parse_error "Invalid pattern: expected 0 or 1.")
        }
    | LEFT_PAREN pat RIGHT_PAREN { $2 }

ql:
    | LEFT_BRACK CONSTRUCTOR RIGHT_BRACK {
        match $2 with
            | "R" -> Type.Quasilinearity.Returnable
            | "U" -> Type.Quasilinearity.Usable
            | _ -> raise (parse_error "Invalid usage: expected U or R.")
    }

mailbox_ty:
    | CONSTRUCTOR BANG pat? ql? {
        let quasilinearity =
            Option.value $4 ~default:(Type.Quasilinearity.Usable)
        in
        Type.(Mailbox {
            capability = Capability.Out;
            interface = $1;
            pattern = $3;
            quasilinearity
        })
    }
    | CONSTRUCTOR QUERY pat? ql? {
        let quasilinearity =
            Option.value $4 ~default:(Type.Quasilinearity.Returnable)
        in
        Type.(Mailbox {
            capability = Capability.In;
            interface = $1;
            pattern = $3;
            quasilinearity
        })
    }

simple_ty:
    | base_ty { Type.Base $1 }
    | mailbox_ty { $1 }

base_ty:
    | CONSTRUCTOR {
        match $1 with
            | "Unit" -> Base.Unit
            | "Int" -> Base.Int
            | "Bool" -> Base.Bool
            | "String" -> Base.String
            | _ -> raise (parse_error "Expected Unit, Int, Bool, or String")
    }

message_ty:
    | CONSTRUCTOR LEFT_PAREN separated_list(COMMA, ty) RIGHT_PAREN { ($1, $3) }

message_list:
    | separated_list(COMMA, message_ty) { $1 }

annotated_var:
    | VARIABLE COLON ty { ($1, $3) }

annotated_var_list:
    | separated_list(COMMA, annotated_var)  { $1 }

interface:
    | INTERFACE interface_name LEFT_BRACE message_list RIGHT_BRACE { Interface.make $2 $4  }

decl:
    | DEF VARIABLE LEFT_PAREN annotated_var_list RIGHT_PAREN COLON ty LEFT_BRACE expr
    RIGHT_BRACE {
        {
          decl_name = $2;
          decl_parameters = $4;
          decl_return_type = $7;
          decl_body = $9
        }
    }

expr_main:
    | expr EOF { $1 }

program:
    | interface* decl* expr? EOF { { prog_interfaces = $1; prog_decls = $2; prog_body = $3 } }