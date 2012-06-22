%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(fax_request).

-behaviour(gen_listener).

%% API
-export([start_link/2
         ,relay_event/2
         ,receive_fax/1
        ]).

%% gen_server callbacks
-export([init/1
         ,handle_call/3
         ,handle_cast/2
         ,handle_info/2
         ,handle_event/2
         ,terminate/2
         ,code_change/3
        ]).

-include("fax.hrl").

-record(state, {
          call :: whapps_call:call()
         ,action = 'receive' :: 'receive' | 'send'
         ,handler :: {pid(), reference()}
         }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Call, JObj) ->
    gen_server:start_link(?MODULE
                          ,[{bindings, [{call, [{callid, whapps_call:call_id(Call)}]}
                                        ,{self, []}
                                       ]}
                            ,{responders, [{{?MODULE, relay_event}, {<<"*">>, <<"*">>}}]}
                           ]
                          ,[Call, JObj]).

-spec relay_event/2 :: (wh_json:json_object(), proplist()) -> any().
relay_event(JObj, Props) ->
    case props:get_value(handler, Props) of
        undefined -> ignore;
        {Pid, _} -> whapps_call_command:relay_event(Pid, JObj)
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Call, JObj]) ->
    put(callid, whapps_call:call_id(Call)),

    gen_listener:cast(self(), start_action),

    {ok, #state{
       call = Call
       ,action = get_action(JObj)
      }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(start_action, #state{call=Call, action='receive'}=State) ->
    {_Pid, _Ref}=Recv = spawn_monitor(?MODULE, receive_fax, [Call]),
    lager:debug("receiving a fax in ~p(~p)", [_Pid, _Ref]),

    {noreply, State#state{handler=Recv}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    lager:debug("unhandled message: ~p", [_Info]),
    {noreply, State}.

-spec handle_event/2 :: (wh_json:json_object(), #state{}) -> {'reply', proplist()}.
handle_event(_JObj, #state{handler=Handler}) ->
    {reply, [{handler,Handler}]}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    lager:debug("fax request terminating: ~p", [_Reason]).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec get_action/1 :: (wh_json:json_object()) -> 'receive' | 'transmit'.
get_action(JObj) ->
    case wh_json:get_value(<<"Action">>, JObj) of
        <<"transmit">> -> 'transmit';
        _ -> 'receive'
    end.

-spec receive_fax/1 :: (whapps_call:call()) -> any().
receive_fax(Call) ->
    put(callid, whapps_call:call_id(Call)),

    whapps_call_command:answer(Call),
    case whapps_call_command:b_receive_fax(Call) of
        {ok, RecvJObj} ->
            lager:debug("rxfax resp: ~p", [RecvJObj]),

            %% store Fax in DB
            case store_fax(Call, RecvJObj) of
                {ok, StoreJObj, FaxId} ->
                    lager:debug("store fax resp: ~p", [StoreJObj]),

                    wapi_notifications:publish_fax([{<<"From-User">>, whapps_call:from_user(Call)}
                                                    ,{<<"From-Realm">>, whapps_call:from_realm(Call)}
                                                    ,{<<"To-User">>, whapps_call:to_user(Call)}
                                                    ,{<<"To-Realm">>, whapps_call:to_realm(Call)}
                                                    ,{<<"Account-DB">>, whapps_call:account_db(Call)}
                                                    ,{<<"Fax-ID">>, FaxId}
                                                    ,{<<"Caller-ID-Number">>, whapps_call:caller_id_number(Call)}
                                                    ,{<<"Caller-ID-Name">>, whapps_call:caller_id_name(Call)}
                                                    ,{<<"Call-ID">>, whapps_call:call_id(Call)}
                                                    | wh_api:default_headers(?APP_NAME, ?APP_VERSION)
                                                   ]);
                _E ->
                    lager:debug("store fax other resp: ~p", [_E])
            end;
        {error, channel_hungup} ->
            lager:debug("rxfax hungup prematurely");
        _Resp ->
            lager:debug("rxfax unhandled: ~p", [_Resp])
    end.

store_fax(Call, JObj) ->
    case should_store_fax(JObj) of
        false -> {error, unable_to_store_fax};
        true ->
            FaxFile = tmp_file(),
            FaxDocId = fax_doc(Call, JObj),
            FaxUrl = attachment_url(Call, FaxFile, FaxDocId),

            lager:debug("storing fax ~s to ~s", [FaxFile, FaxUrl]),

            case whapps_call_command:b_store_fax(FaxUrl, Call) of
                {ok, JObj} -> {ok, JObj, FaxDocId};
                E -> lager:debug("store_fax error: ~p", [E]), E
            end
    end.

should_store_fax(JObj) ->
    case wh_json:get_integer_value(<<"Fax-Result-Code">>, JObj, 0) of
        0 -> true;
        48 ->
            lager:debug("failed to receive fax(48): ~s", [wh_json:get_value(<<"Fax-Result-Text">>, JObj)]),
            false;
        _Code ->
            lager:debug("received fax(~b): ~s", [_Code, wh_json:get_value(<<"Fax-Result-Text">>, JObj)]),
            true
    end.

fax_doc(Call, JObj) ->
    AccountDb = whapps_call:account_db(Call),

    TStamp = wh_util:current_tstamp(),
    {{Y,M,D},{H,I,S}} = calendar:gregorian_seconds_to_datetime(TStamp),

    Name = list_to_binary(["fax message received at "
                           ,wh_util:to_binary(Y), "-", wh_util:to_binary(M), "-", wh_util:to_binary(D)
                           ," " , wh_util:to_binary(H), ":", wh_util:to_binary(I), ":", wh_util:to_binary(S)
                           ," UTC"
                          ]),

    Props = [{<<"name">>, Name}
             ,{<<"description">>, <<"fax document received">>}
             ,{<<"source_type">>, <<"incoming_fax">>}
             ,{<<"timestamp">>, wh_json:get_value(<<"Timestamp">>, JObj)}
             | fax_properties(JObj)
            ],

    Doc = wh_doc:update_pvt_parameters(wh_json:from_list(Props)
                                       ,AccountDb
                                       ,[{type, <<"private_media">>}]
                                      ),

    {ok, JObj} = couch_mgr:save_doc(AccountDb, Doc),
    wh_json:get_value(<<"_id">>, JObj).

-spec fax_properties/1 :: (wh_json:json_object()) -> proplist().
fax_properties(JObj) ->
    [{wh_json:normalize_key(K), V} || {<<"Fax-", K/binary>>, V} <- wh_json:to_proplist(JObj)].

attachment_url(Call, File, FaxDocId) ->
    AccountDb = whapps_call:account_db(Call),
    _ = case couch_mgr:open_doc(AccountDb, FaxDocId) of
            {ok, JObj} ->
                case wh_json:get_keys(wh_json:get_value(<<"_attachments">>, JObj, wh_json:new())) of
                    [] -> ok;
                    Existing -> [couch_mgr:delete_attachment(AccountDb, FaxDocId, Attach) || Attach <- Existing]
                end;
            {error, _} -> ok
        end,
    Rev = case couch_mgr:lookup_doc_rev(AccountDb, FaxDocId) of
              {ok, R} -> <<"?rev=", R/binary>>;
              _ -> <<>>
          end,
    list_to_binary([couch_mgr:get_url(), AccountDb, "/", FaxDocId, "/", File, Rev]).


-spec tmp_file/0 :: () -> ne_binary().
tmp_file() ->
     <<(wh_util:to_hex_binary(crypto:rand_bytes(16)))/binary, ".tiff">>.