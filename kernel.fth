\ -*- forth -*- Copyright 2004, 2013 Lars Brinkhoff

\ This kernel needs, at a minimum, these 17 primitives:
\
\ Definitions:		enter dodoes exit
\ Control flow:		0branch
\ Literals:		(literal)
\ Memory access:	! @ c! c@
\ Aritmetic/logic:	+ nand
\ Return stack:		>r r>
\ I/O:			emit open-file read-file close-file

: warm
   ." lbForth" cr
   ['] nop dup is backtrace is also
   ['] dummy-catch is catch
   ['] (number) is number
   ['] lastxt dup lastxt ! forth !
   ['] forth current !
   0 compiler-words !
   0 included-files !
   10 base !
   s" core.fth" included
   s" core-ext.fth" included
   s" string.fth" included
   s" tools.fth" included
   s" file.fth" included
   ." ok" cr
   quit ;

create data_stack     110 cells allot
create return_stack   256 cells allot
create jmpbuf         jmp_buf allot

variable dp
variable end_of_dictionary

variable SP
variable RP

: sp@   SP @ cell + ;
: sp!   SP ! ;
: rp@   RP @ cell + ;
: rp!   postpone (literal) RP , postpone ! ; immediate

: cabs ( char -- |char| )   dup 127 > if 256 swap - then ;

: >name    count cabs ;
: >lfa     TO_NEXT + ;
: >nextxt   >lfa @ ;

: branch    r> @ >r ;
: (+loop)   r> swap r> + r@ over >r < invert swap >r ;

: ?stack   data_stack 99 cells + sp@ < abort" Stack underflow" ;

defer number

\ Sorry about the long definition, but I didn't want to leave many
\ useless factors lying around.
: (number) ( a u -- )
   over c@ [char] - = dup >r if swap 1+ swap 1 - then
   0 rot rot
   begin dup while
      over c@ [char] 0 - dup -1 > while dup 10 < while
      2>r 1+ swap dup dup + dup + + dup +  r> + swap r> 1 -
   repeat then drop then
   ?dup if ." Undefined: " type cr abort then
   drop r> if negate then
   postpone literal ;

defer catch
: dummy-catch   execute 0 ;

create interpreters   ' compile, ,  ' number ,  ' execute ,

: interpret-xt   1+ cells  interpreters + @ catch
                 if ." Exception" cr then ;

: interpret  begin parse-name dup while
   find-name interpret-xt ?stack repeat 2drop ;

: bounds    over + swap ;
: count     dup 1+ swap c@ ;

: c,   here c!  1 allot ;
: string, ( addr n -- )    here over allot align  swap cmove ;
: #name   NAME_LENGTH 1 - ;

: chain, ( nt wid -- )  >body dup @ , ! ;
: link, ( nt -- )       lastxt ! current @ >body @ , ;
: reveal                lastxt @ current @ >body ! ;
: name, ( a u -- )      #name min c,  #name string, ;
: header, ( code -- )   align here  parse-name name,  link, ( code ) , 0 , ;

\ ----------------------------------------------------------------------

( Core words. )

: +!   swap over @ + swap ! ;
: ,    here !  cell allot ;
: -    negate + ;
: 0=   if 0 else -1 then ;
: 1+   1 + ;

variable  sink
: drop    sink ! ;
: 2drop   drop drop ;
: 3drop   2drop drop ;

: swap   >r >r rp@ cell+ @ r> r> drop ;
: over   >r >r r@ 2r> ;
: rot    >r swap r> swap ;

: dup    sp@ @ ;
: 2dup   over over ;
: 3dup   >r >r r@ over 2r> over >r rot swap r> ;
: ?dup   dup if dup then ;

: nip    swap drop ;
: 2nip   2>r 2drop 2r> ;

variable csp

: .latest   lastxt @ >name type ;
: !csp   csp @ if ." Nested definition: " .latest cr abort then  sp@ csp ! ;
: ?csp   sp@ csp @ <> if ." Unbalanced definition: " .latest cr abort then
   0 csp ! ;

: :   [ ' enter >code @ ] literal header, ] !csp ;
: ;   reveal postpone exit postpone [ ?csp ; immediate

: =   - if 0 else -1 then ;
\ TODO: This is wrong if "-" overflows.
\ : <   - [ 0 invert 1 rshift invert ] literal nand invert if -1 else 0 then ;
: 0<   [ 0 invert 1 rshift invert ] literal nand invert if -1 else 0 then ;
: xor   2dup nand >r r@ nand swap r> nand nand ;
: <   2dup xor 0< if drop 0< else - 0< then ;
\ If d=x-y and sX is the sign bit, this computes "less than":
\ ((~y)&(x^d)) ^ (d&x);
\ : <   2dup - >r invert over r@ xor and swap r> and xor 0< ;
: >   swap < ;

: >code   TO_CODE + ;
: >does   TO_DOES + ;
: >body   TO_BODY + ;

variable >in

: r@   rp@ cell+ @ ;
: i    r> r@ swap >r ;

: abort   data_stack 100 cells + sp!  quit ;

: align     dp @ aligned dp ! ;
: aligned   cell + 1 - cell negate nand invert ;
: allot     dp +! ;

variable base

: bl   32 ;
: cr   10 emit ;

: cell    cell ; \ Metacompiler knows what to do.
: cell+   cell + ;
cell 4 = [if] : cells   dup + dup + ; [then]
cell 8 = [if] : cells   dup + dup + dup + ; [then]

: unex   2r> r> 3drop ;
\ Put xt and 'unex on return stack, then jump to that.
: execute   ['] unex >r >r rp@ >r ;

variable forth
variable compiler-words
variable included-files

create context   ' forth , ' forth , 0 , 0 , 0 , 0 , 0 , 0 , 0 ,
variable current

: lowercase? ( c -- flag )   dup [char] a < if drop 0 exit then [char] z 1+ < ;
: upcase ( c1 -- c2 )   dup lowercase? if [ char A char a - ] literal + then ;
: c<> ( c1 c2 -- flag )   upcase swap upcase <> ;

: name= ( ca1 u1 ca2 u2 -- flag )
   2>r r@ <> 2r> rot if 3drop 0 exit then
   bounds do
      dup c@ i c@ c<> if drop unloop 0 exit then
      1+
  loop drop -1 ;
: nt= ( ca u nt -- flag )   >name name= ;

: immediate?   c@ 127 > if 1 else -1 then ;

\ TODO: nt>string nt>interpret nt>compile
\ Forth83: >name >link body> name> link> n>link l>name

: traverse-wordlist ( wid xt -- ) ( xt: nt -- continue? )
   >r >body @ begin dup while
      r@ over >r execute r> swap
      while >nextxt
   repeat then r> 2drop ;

: ?nt>xt ( -1 ca u nt -- 0 xt i? 0 | -1 ca u -1 )
   3dup nt= if >r 3drop 0 r> dup immediate? 0
   else drop -1 then ;
: search-wordlist ( ca u wl -- 0 | xt 1 | xt -1 )
   2>r -1 swap 2r> ['] ?nt>xt traverse-wordlist
   rot if 2drop 0 then ;

: find-name ( a u -- a u 0 | xt ? )
   #name min context >r begin r> dup cell+ >r @ ?dup while
      >r 2dup r> search-wordlist ?dup
      if 2nip r> drop exit then
   repeat r> drop 0 ;

: here   dp @ ;

: invert   -1 nand ;
: negate   invert 1+ ;

: key   here dup 1 0 read-file 0 = 1 = nand 0= abort" Read error"  c@ ;

: literal   state @ if postpone (literal) , then ; immediate

: min   2dup < if drop else nip then ;

: or   invert swap invert nand ;

defer quit

variable state

: type   ?dup if bounds do i c@ emit loop else drop then ;

: unloop   r> 2r> 2drop >r ;

create src  2 cells allot
: source   src dup cell+ @ swap @ ;
: source? ( -- flag )   >in @ source nip < ;
: <source ( -- char|-1 )   source >in @ dup rot = if
   2drop -1 else + c@  1 >in +! then ;

: blank?   dup bl =  over 8 = or  over 9 = or  over 10 = or  over 13 = or nip ;
: skip ( "<blanks>" -- )   begin source? while
   <source blank? 0= until -1 >in +! then ;
: parse-name ( "<blanks>name<blank>" -- a u )   skip  source drop >in @ +
   0 begin source? while 1+ <source blank? until 1 - then ;

: previous   ['] forth context ! ;

defer also

: [   0 state !  previous ; immediate
: ]   1 state !  also ['] compiler-words context ! ;

\ ----------------------------------------------------------------------

( Core extension words. )

: <>   = 0= ;

: 2>r   r> swap rot >r >r >r ;
: 2r>   r> r> r> rot >r swap ;

: compile,   state @ if , else execute then ;

defer refill

create fib   256 allot

: file-refill ( -- flag )   0 >in !  0 src !  -1
   fib 256 bounds do
      i 1 source-id read-file abort" Read error."
      dup 0=  i c@ 10 =  or  if src @ or 0= if drop 0 then leave then
      drop  1 src +!
   loop ;

variable 'source-id
: source-id   'source-id @ ;
: restore-input   drop  is refill  src !  src cell+ !  'source-id !  >in !  0 ;
: save-input   >in @  source-id  source  ['] refill >body @  5 ;

: nop ;

defer backtrace

: sigint   cr backtrace abort ;

\ ----------------------------------------------------------------------

( String words. )

: cmove ( addr1 addr2 n -- )   bounds do  dup c@  i c!  1+  loop drop ;

\ ----------------------------------------------------------------------

( File Access words. )

: n>r   r> over >r swap begin ?dup while rot r> 2>r 1 - repeat >r ;
: nr>   r> r@ begin ?dup while 2r> >r rot rot 1 - repeat r> swap >r ;

: interpret-loop   >r begin ['] refill catch if ." Exception" cr -1 then while
   interpret r@ execute repeat r> drop ;

: file-input ( fileid -- )    'source-id !  fib src cell+ !
   ( 0 blk ! )  ['] file-refill is refill ;

: include-file ( fileid -- )   save-input n>r  file-input
   ['] nop interpret-loop  source-id close-file drop
   nr> restore-input abort" Bad restore-input" ;

: included   2dup align here >r  name,  r> ['] included-files chain, 0 , 0 ,
   r/o open-file abort" Read error." include-file ;

: r/o   s" r" drop ;

: (defer)   @ execute ;

\ NOTE: THIS HAS TO BE THE LAST WORD IN THE FILE!
variable lastxt
