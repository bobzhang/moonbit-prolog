% A small Prolog knowledge base + queries to run through the interpreter:
%   ./_build/native/debug/build/cmd/main/main.exe < examples/family.pl

% --- Facts ---------------------------------------------------------------
parent(john, mary).
parent(john, peter).
parent(mary, ann).
male(john).
male(peter).
female(mary).
female(ann).

% --- Rules ---------------------------------------------------------------
grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
sibling(X, Y) :- parent(P, X), parent(P, Y), X \= Y.
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).

% --- Queries -------------------------------------------------------------
?- sibling(S1, S2).
?- ancestor(john, Desc).
?- grandparent(G, ann).
?- member(X, [a, b, c]).
?- append([1,2], [3,4], L).
?- reverse([a,b,c], R).
?- length([a,b,c], N).
?- length(X, 2).
?- N is 3 + 4 * 2.
?- (X = 1 ; X = 2).
?- member(X, [1,2,3]), X > 1.
?- \+ member(4, [1,2,3]).
?- findall(X, member(X, [a,b,c]), L).
?- findall(X-Y, member(X, [a,b]), L).
?- append(X, Y, [1,2]).
?- write('Hello, '), write(world), nl.
?- X = f(A, A), X = f(1, 2).
