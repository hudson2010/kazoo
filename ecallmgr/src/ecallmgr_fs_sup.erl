%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP INC
%%% @doc
%%% Manage starting fs_auth, fs_route, and fs_node handlers
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(ecallmgr_fs_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([start_handlers/2]).
-export([stop_handlers/1]).
-export([node_handlers/0]).
-export([notify_handlers/0]).
-export([get_handler_pids/1]).
-export([init/1]).

-include("ecallmgr.hrl").

-define(SERVER, ?MODULE).
-define(CHILD(Name, Type), {Name, {Name, start_link, []}, permanent, 5000, Type, [Name]}).
-define(CHILD(Name, Mod, Args), {Name, {Mod, start_link, Args}, transient, 5000, worker, [Mod]}).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

-spec start_handlers/2 :: (atom(), proplist()) -> [startlink_ret(),...].
start_handlers(Node, Options) when is_atom(Node) ->
    NodeB = wh_util:to_binary(Node),
    [ begin
          Name = wh_util:to_atom(<<NodeB/binary, H/binary>>, true),
          Mod = wh_util:to_atom(<<"ecallmgr_fs", H/binary>>),
          lager:debug("starting handler ~s", [Name]),
          supervisor:start_child(?SERVER, ?CHILD(Name, Mod, [Node, Options]))
      end
      || H <- [<<"_node">>, <<"_auth">>, <<"_route">>, <<"_config">>, <<"_resource">>, <<"_notify">>] ].

-spec stop_handlers/1 :: (atom()) -> ['ok' | {'error', 'running' | 'not_found' | 'simple_one_for_one'},...].
stop_handlers(Node) when is_atom(Node) ->
    NodeB = wh_util:to_binary(Node),
    [ begin
          ok = supervisor:terminate_child(?SERVER, Name),
          supervisor:delete_child(?SERVER, Name)
      end || {Name, _, _, [_]} <- supervisor:which_children(?SERVER)
                 ,node_matches(NodeB, wh_util:to_binary(Name))
    ].

-spec node_handlers/0 :: () -> [pid(),...] | [].
node_handlers() ->
    [ Pid || {_, Pid, worker, [HandlerMod]} <- supervisor:which_children(?SERVER),
             HandlerMod =:= ecallmgr_fs_node].

-spec notify_handlers/0 :: () -> [pid(),...] | [].
notify_handlers() ->
    [ Pid || {_, Pid, worker, [HandlerMod]} <- supervisor:which_children(?SERVER),
             HandlerMod =:= ecallmgr_fs_notify].

-spec get_handler_pids/1 :: (atom()) -> {pid() | 'error', pid() | 'error', pid() | 'error', pid() | 'error'}.
get_handler_pids(Node) when is_atom(Node) ->
    NodeB = wh_util:to_binary(Node),
    NodePids = [ {HandlerMod, Pid} || {Name, Pid, worker, [HandlerMod]} <- supervisor:which_children(?SERVER)
                                          ,node_matches(NodeB, wh_util:to_binary(Name))],
    {props:get_value(ecallmgr_fs_auth, NodePids, error)
     ,props:get_value(ecallmgr_fs_route, NodePids, error)
     ,props:get_value(ecallmgr_fs_node, NodePids, error)
     ,props:get_value(ecallmgr_fs_config, NodePids, error)
    }.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 1,
    MaxSecondsBetweenRestarts = 5,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    {ok, {SupFlags, []}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec node_matches/2 :: (ne_binary(), ne_binary()) -> boolean().
node_matches(NodeB, Name) ->
    Size = byte_size(NodeB),
    case binary:match(Name, NodeB) of
        {_, End} -> Size =:= End;
        nomatch -> false
    end.
