/*  Part of ClioPatria

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@uva.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2010, University of Amsterdam,
			 VU University Amsterdam.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(server_statistics,
	  [ rdf_call_statistics_table//0,
	    http_session_table//0,
	    http_server_statistics//0,
	    http_server_pool_table//0
	  ]).
:- use_module(library(option)).
:- use_module(library(pairs)).
:- use_module(library(semweb/rdf_db)).
:- use_module(library(http/http_session)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/html_write)).
:- use_module(library(http/html_head)).
:- use_module(user(user_db)).
:- use_module(components(basics)).

/** <module> Server statistics components

*/


%%	rdf_call_statistics_table//
%
%	Display table with RDF-call statistics

rdf_call_statistics_table -->
	{ rdf_call_stats(Lookup),
	  (   Lookup = [rdf(_,_,_)-_|_]
	  ->  Cols = 3
	  ;   Cols = 4
	  )
	},
	html(table([ class(block)
		   ],
		   [ tr([ th(colspan(Cols), 'Indexed (SOPG)'),
			  th('Calls')
			]),
		     \lookup_statistics(Lookup)
		   ])).

rdf_call_stats(Lookup) :-
	findall(Index-Count,
		rdf_statistics(lookup(Index, Count)),
		Lookup).

lookup_statistics([H|T]) -->
	html(tr(\lookup_row(H))),
	lookup_statistics(T).
lookup_statistics([], _) --> [].

lookup_row(rdf(S,P,O)-Count) -->
	html([ \i(S), \i(P), \i(O), \nc(human, Count)]).
lookup_row(rdf(S,P,O,G)-Count) -->
	html([\i(S), \i(P), \i(O), \i(G), \nc(human, Count)]).

i(I) --> html(td(class(instantiated), I)).


%%	http_session_table//
%
%	HTML component that writes a table of currently logged on users.

http_session_table -->
	{ findall(S, session(S), Sessions0),
	  sort(Sessions0, Sessions),
	  Sessions \== [], !
	},
	html([ table([ class(block)
		     ],
		     [ tr([th('User'), th('Real Name'),
			   th('On since'), th('Idle'), th('From')])
		     | \sessions(Sessions)
		     ])
	     ]).
http_session_table -->
	html(p('No users logged in')).

%%	session(-Session:s(Idle, User, SessionID, Peer)) is nondet.
%
%	Enumerate all current HTTP sessions.

session(s(Idle, User, SessionID, Peer)) :-
	http_current_session(SessionID, peer(Peer)),
	http_current_session(SessionID, idle(Idle)),
	(   user_property(User, session(SessionID))
	->  true
	;   User = (-)
	).

sessions([H|T]) -->
	html(tr(\session(H))),
	sessions(T).
sessions([]) --> [].

session(s(Idle, -, _SessionID, Peer)) -->
	html([td(-), td(-), td(-), td(\idle(Idle)), td(\ip(Peer))]).
session(s(Idle, User, _SessionID, Peer)) -->
	{  (   user_property(User, realname(RealName))
	   ->  true
	   ;   RealName = '?'
	   ),
	   (   user_property(User, connection(OnSince, _Idle))
	   ->  true
	   ;   OnSince = 0
	   )
	},
	html([td(User), td(RealName), td(\date(OnSince)), td(\idle(Idle)), td(\ip(Peer))]).

idle(Time) -->
	{ Secs is round(Time),
	  Min is Secs // 60,
	  Sec is Secs mod 60
	},
	html('~`0t~d~2|:~`0t~d~5|'-[Min, Sec]).

date(Date) -->
	{ format_time(string(S), '%+', Date)
	},
	html(S).

ip(ip(A,B,C,D)) --> !,
	html('~d.~d.~d.~d'-[A,B,C,D]).
ip(IP) -->
	html('~w'-[IP]).


%%	http_server_statistics//
%
%	HTML component showing statistics on the HTTP server

http_server_statistics -->
	{ findall(Port-ID, http_current_worker(Port, ID), Workers),
	  group_pairs_by_key(Workers, Servers)
	},
	html([ table([ class(block)
		     ],
		     [ \servers_stats(Servers)
		     ])
	     ]).

servers_stats([]) --> [].
servers_stats([H|T]) -->
	server_stats(H), servers_stats(T).

:- if(catch(statistics(process_cputime, _),_,fail)).
cputime(CPU) :- statistics(process_cputime, CPU).
:- else.
cputime(CPU) :- statistics(cputime, CPU).
:- endif.

server_stats(Port-Workers) -->
	{ length(Workers, NWorkers),
	  http_server_property(Port, start_time(StartTime)),
	  format_time(string(ST), '%+', StartTime),
	  cputime(CPU)
	},
	html([ \server_stat('Port:', Port),
	       \server_stat('Started:', ST),
	       \server_stat('Total CPU usage:', [\n('~2f',CPU), ' seconds']),
	       \request_statistics,
	       \server_stat('# worker threads:', NWorkers),
	       tr(th(colspan(6), 'Statistics by worker')),
	       tr([ th('Thread'),
		    th('CPU'),
		    th(''),
		    th('Local'),
		    th('Global'),
		    th('Trail')
		  ]),
	       \http_workers(Workers)
	     ]).

server_stat(Name, Value) -->
	html(tr([ th([class(p_name), colspan(3)], Name),
		  td([class(value),  colspan(3)], Value)
		])).


:- if(source_exports(library(http/http_stream), cgi_statistics/1)).
:- use_module(library(http/http_stream)).
request_statistics -->
	{ cgi_statistics(requests(Count)),
	  cgi_statistics(bytes_sent(Sent))
	},
	server_stat('Requests processed:', \n(human, Count)),
	server_stat('Bytes sent:', \n(human, Sent)).
:- else.
request_statistics --> [].
:- endif.


http_workers([], _) -->
	[].
http_workers([H|T]) -->
	http_worker(H),
	http_workers(T).

http_worker(H) -->
	{ thread_statistics(H, locallimit, LL),
	  thread_statistics(H, globallimit, GL),
	  thread_statistics(H, traillimit, TL),
	  thread_statistics(H, localused, LU),
	  thread_statistics(H, globalused, GU),
	  thread_statistics(H, trailused, TU),
	  thread_statistics(H, cputime, CPU)
	},
	html([ tr([ td(rowspan(2), H),
		    \nc('~3f', CPU, [rowspan(2)]),
		    th('In use'),
		    \nc(human, LU),
		    \nc(human, GU),
		    \nc(human, TU)
		  ]),
	       tr([ th('Limit'),
		    \nc(human, LL),
		    \nc(human, GL),
		    \nc(human, TL)
		  ])
	     ]).



		 /*******************************
		 *	      POOLS		*
		 *******************************/

%%	http_server_pool_table//
%
%	Display table with statistics on thread-pools.

http_server_pool_table -->
	{ findall(Pool, current_thread_pool(Pool), Pools),
	  sort(Pools, Sorted)
	},
	html(table([ id('http-server-pool'),
		     class(block)
		   ],
		   [ tr([th('Name'), th('Running'), th('Size'), th('Waiting'), th('Backlog')])
		   | \server_pools(Sorted)
		   ])).

server_pools([H|T]) -->
	html(tr(\server_pool(H))),
	server_pools(T).
server_pools([], _) --> [].

server_pool(Pool) -->
	{ findall(P, thread_pool_property(Pool, P), List),
	  memberchk(size(Size), List),
	  memberchk(running(Running), List),
	  memberchk(backlog(Waiting), List),
	  memberchk(options(Options), List),
	  option(backlog(MaxBackLog), Options, infinite)
	},
	html([ th(class(p_name), Pool),
	       \nc(human, Running),
	       \nc(human, Size),
	       \nc(human, Waiting),
	       \nc(human, MaxBackLog)
	     ]).


