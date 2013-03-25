( Search-Order words. )

: forth-wordlist   ['] forth ;
: get-current      current @ ;
: ord ( n addr )   @+ ?dup if >r under 1+ recurse r> swap
                   else drop then ;
: get-order        0 context ord ;
: set-current      current ! ;
: definitions      context @ set-current ;
: wordlist         :noname 0 , 0 , postpone ; ;

( Search-Order extension words. )

: forth        forth-wordlist context ! ;
: set-order    dup 0 = if ( todo ) abort then
               dup -1 = if ( todo ) abort else
               dup 4 > abort" Max 4 context allowed"
               n>r 0 nr> 1+
               context swap cells bounds
               do i ! /cell +loop then ;
: only         forth-wordlist forth-wordlist 2 set-order ;
re: also       get-order 1+ over swap set-order ;
re: previous   get-order 1- nip set-order ;
: order        ." Order:"
               context begin dup @ ?dup while
                  space id. cell+
               repeat drop cr
               ." Current: " current @ id. cr ;

( Traditional vocabulary words. )

: body>xt      [ 0 >body ] literal - ;
: vocabulary   create 0 , 0 ,  does> body>xt context ! ;
