%%%-------------------------------------------------------------------
%%% @copyright (C) 2011, VoIP INC
%%% @doc
%%% NoAuthN module
%%%
%%% Authenticates everyone! PARTY TIME!
%%%
%%% @end
%%% @contributors
%%%   Karl Anderson
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(cb_noauthn).

-export([init/0
         ,authenticate/1
        ]).

-include("include/crossbar.hrl").

%%%===================================================================
%%% API
%%%===================================================================
init() ->
    crossbar_bindings:bind(<<"v1_resource.authenticate">>, ?MODULE, authenticate).

authenticate(#cb_context{}) ->
    lager:debug("noauthn authenticating request"),
    true.
