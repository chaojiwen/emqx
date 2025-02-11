%%--------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(emqx_conf).

-compile({no_auto_import, [get/1, get/2]}).
-include_lib("emqx/include/logger.hrl").
-include_lib("hocon/include/hoconsc.hrl").

-export([add_handler/2, remove_handler/1]).
-export([get/1, get/2, get_raw/2, get_all/1]).
-export([get_by_node/2, get_by_node/3]).
-export([update/3, update/4]).
-export([remove/2, remove/3]).
-export([reset/2, reset/3]).
-export([dump_schema/1, dump_schema/2]).

%% for rpc
-export([get_node_and_config/1]).

%% API
%% @doc Adds a new config handler to emqx_config_handler.
-spec add_handler(emqx_config:config_key_path(), module()) -> ok.
add_handler(ConfKeyPath, HandlerName) ->
    emqx_config_handler:add_handler(ConfKeyPath, HandlerName).

%% @doc remove config handler from emqx_config_handler.
-spec remove_handler(emqx_config:config_key_path()) -> ok.
remove_handler(ConfKeyPath) ->
    emqx_config_handler:remove_handler(ConfKeyPath).

-spec get(emqx_map_lib:config_key_path()) -> term().
get(KeyPath) ->
    emqx:get_config(KeyPath).

-spec get(emqx_map_lib:config_key_path(), term()) -> term().
get(KeyPath, Default) ->
    emqx:get_config(KeyPath, Default).

-spec get_raw(emqx_map_lib:config_key_path(), term()) -> term().
get_raw(KeyPath, Default) ->
    emqx_config:get_raw(KeyPath, Default).

%% @doc Returns all values in the cluster.
-spec get_all(emqx_map_lib:config_key_path()) -> #{node() => term()}.
get_all(KeyPath) ->
    {ResL, []} = emqx_conf_proto_v1:get_all(KeyPath),
    maps:from_list(ResL).

%% @doc Returns the specified node's KeyPath, or exception if not found
-spec get_by_node(node(), emqx_map_lib:config_key_path()) -> term().
get_by_node(Node, KeyPath) when Node =:= node() ->
    emqx:get_config(KeyPath);
get_by_node(Node, KeyPath) ->
    emqx_conf_proto_v1:get_config(Node, KeyPath).

%% @doc Returns the specified node's KeyPath, or the default value if not found
-spec get_by_node(node(), emqx_map_lib:config_key_path(), term()) -> term().
get_by_node(Node, KeyPath, Default) when Node =:= node() ->
    emqx:get_config(KeyPath, Default);
get_by_node(Node, KeyPath, Default) ->
    emqx_conf_proto_v1:get_config(Node, KeyPath, Default).

%% @doc Returns the specified node's KeyPath, or config_not_found if key path not found
-spec get_node_and_config(emqx_map_lib:config_key_path()) -> term().
get_node_and_config(KeyPath) ->
    {node(), emqx:get_config(KeyPath, config_not_found)}.

%% @doc Update all value of key path in cluster-override.conf or local-override.conf.
-spec update(emqx_map_lib:config_key_path(), emqx_config:update_request(),
    emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
update(KeyPath, UpdateReq, Opts) ->
    check_cluster_rpc_result(emqx_conf_proto_v1:update(KeyPath, UpdateReq, Opts)).

%% @doc Update the specified node's key path in local-override.conf.
-spec update(node(), emqx_map_lib:config_key_path(), emqx_config:update_request(),
    emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()} | emqx_rpc:badrpc().
update(Node, KeyPath, UpdateReq, Opts0) when Node =:= node() ->
    emqx:update_config(KeyPath, UpdateReq, Opts0#{override_to => local});
update(Node, KeyPath, UpdateReq, Opts) ->
    emqx_conf_proto_v1:update(Node, KeyPath, UpdateReq, Opts).

%% @doc remove all value of key path in cluster-override.conf or local-override.conf.
-spec remove(emqx_map_lib:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
remove(KeyPath, Opts) ->
    check_cluster_rpc_result(emqx_conf_proto_v1:remove_config(KeyPath, Opts)).

%% @doc remove the specified node's key path in local-override.conf.
-spec remove(node(), emqx_map_lib:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
remove(Node, KeyPath, Opts) when Node =:= node() ->
    emqx:remove_config(KeyPath, Opts#{override_to => local});
remove(Node, KeyPath, Opts) ->
    emqx_conf_proto_v1:remove_config(Node, KeyPath, Opts).

%% @doc reset all value of key path in cluster-override.conf or local-override.conf.
-spec reset(emqx_map_lib:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
reset(KeyPath, Opts) ->
    check_cluster_rpc_result(emqx_conf_proto_v1:reset(KeyPath, Opts)).

%% @doc reset the specified node's key path in local-override.conf.
-spec reset(node(), emqx_map_lib:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
reset(Node, KeyPath, Opts) when Node =:= node() ->
    emqx:reset_config(KeyPath, Opts#{override_to => local});
reset(Node, KeyPath, Opts) ->
    emqx_conf_proto_v1:reset(Node, KeyPath, Opts).

%% @doc Called from build script.
-spec dump_schema(file:name_all()) -> ok.
dump_schema(Dir) ->
    dump_schema(Dir, emqx_conf_schema).

dump_schema(Dir, SchemaModule) ->
    SchemaMdFile = filename:join([Dir, "config.md"]),
    io:format(user, "===< Generating: ~s~n", [SchemaMdFile ]),
    ok = gen_doc(SchemaMdFile, SchemaModule),

    %% for scripts/spellcheck.
    SchemaJsonFile = filename:join([Dir, "schema.json"]),
    io:format(user, "===< Generating: ~s~n", [SchemaJsonFile]),
    JsonMap = hocon_schema_json:gen(SchemaModule),
    IoData = jsx:encode(JsonMap, [space, {indent, 4}]),
    ok = file:write_file(SchemaJsonFile, IoData),

    %% hot-update configuration schema
    HotConfigSchemaFile = filename:join([Dir, "hot-config-schema.json"]),
    io:format(user, "===< Generating: ~s~n", [HotConfigSchemaFile]),
    ok = gen_hot_conf_schema(HotConfigSchemaFile),
    ok.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

-spec gen_doc(file:name_all(), module()) -> ok.
gen_doc(File, SchemaModule) ->
    Version = emqx_release:version(),
    Title = "# " ++ emqx_release:description() ++ " " ++ Version ++ " Configuration",
    BodyFile = filename:join([code:lib_dir(emqx_conf), "etc", "emqx_conf.md"]),
    {ok, Body} = file:read_file(BodyFile),
    Doc = hocon_schema_md:gen(SchemaModule, #{title => Title, body => Body}),
    file:write_file(File, Doc).

check_cluster_rpc_result(Result) ->
    case Result of
        {ok, _TnxId, Res} -> Res;
        {retry, TnxId, Res, Nodes} ->
            %% The init MFA return ok, but other nodes failed.
            %% We return ok and alert an alarm.
            ?SLOG(error, #{msg => "failed_to_update_config_in_cluster", nodes => Nodes,
                           tnx_id => TnxId}),
            Res;
        {error, Error} -> %% all MFA return not ok or {ok, term()}.
            Error
    end.

%% Only gen hot_conf schema, not all configuration fields.
gen_hot_conf_schema(File) ->
    {ApiSpec0, Components0} = emqx_dashboard_swagger:spec(emqx_mgmt_api_configs,
        #{schema_converter => fun hocon_schema_to_spec/2}),
    ApiSpec = lists:foldl(fun({Path, Spec, _, _}, Acc) ->
        NewSpec = maps:fold(fun(Method, #{responses := Responses}, SubAcc) ->
            case Responses of
                #{<<"200">> :=
                    #{<<"content">> := #{<<"application/json">> := #{<<"schema">> := Schema}}}} ->
                    SubAcc#{Method => Schema};
                _ -> SubAcc
            end
                            end, #{}, Spec),
        Acc#{list_to_atom(Path) => NewSpec} end, #{}, ApiSpec0),
    Components = lists:foldl(fun(M, Acc) -> maps:merge(M, Acc) end, #{}, Components0),
    IoData = jsx:encode(#{
        info => #{title => <<"EMQX Hot Conf Schema">>, version => <<"0.1.0">>},
        paths => ApiSpec,
        components => #{schemas => Components}
    }, [space, {indent, 4}]),
    file:write_file(File, IoData).

-define(INIT_SCHEMA, #{fields => #{}, translations => #{},
    validations => [], namespace => undefined}).

-define(TO_REF(_N_, _F_), iolist_to_binary([to_bin(_N_), ".", to_bin(_F_)])).
-define(TO_COMPONENTS_SCHEMA(_M_, _F_), iolist_to_binary([<<"#/components/schemas/">>,
    ?TO_REF(emqx_dashboard_swagger:namespace(_M_), _F_)])).

hocon_schema_to_spec(?R_REF(Module, StructName), _LocalModule) ->
    {#{<<"$ref">> => ?TO_COMPONENTS_SCHEMA(Module, StructName)},
        [{Module, StructName}]};
hocon_schema_to_spec(?REF(StructName), LocalModule) ->
    {#{<<"$ref">> => ?TO_COMPONENTS_SCHEMA(LocalModule, StructName)},
        [{LocalModule, StructName}]};
hocon_schema_to_spec(Type, LocalModule) when ?IS_TYPEREFL(Type) ->
    {typename_to_spec(typerefl:name(Type), LocalModule), []};
hocon_schema_to_spec(?ARRAY(Item), LocalModule) ->
    {Schema, Refs} = hocon_schema_to_spec(Item, LocalModule),
    {#{type => array, items => Schema}, Refs};
hocon_schema_to_spec(?LAZY(Item), LocalModule) ->
    hocon_schema_to_spec(Item, LocalModule);
hocon_schema_to_spec(?ENUM(Items), _LocalModule) ->
    {#{type => enum, symbols => Items}, []};
hocon_schema_to_spec(?MAP(Name, Type), LocalModule) ->
    {Schema, SubRefs} = hocon_schema_to_spec(Type, LocalModule),
    {#{<<"type">> => object,
        <<"properties">> => #{<<"$", (to_bin(Name))/binary>> => Schema}},
        SubRefs};
hocon_schema_to_spec(?UNION(Types), LocalModule) ->
    {OneOf, Refs} = lists:foldl(fun(Type, {Acc, RefsAcc}) ->
        {Schema, SubRefs} = hocon_schema_to_spec(Type, LocalModule),
        {[Schema | Acc], SubRefs ++ RefsAcc}
                                end, {[], []}, Types),
    {#{<<"oneOf">> => OneOf}, Refs};
hocon_schema_to_spec(Atom, _LocalModule) when is_atom(Atom) ->
    {#{type => enum, symbols => [Atom]}, []}.

typename_to_spec("user_id_type()", _Mod) -> #{type => enum, symbols => [clientid, username]};
typename_to_spec("term()", _Mod) -> #{type => string};
typename_to_spec("boolean()", _Mod) -> #{type => boolean};
typename_to_spec("binary()", _Mod) -> #{type => string};
typename_to_spec("float()", _Mod) -> #{type => number};
typename_to_spec("integer()", _Mod) -> #{type => number};
typename_to_spec("non_neg_integer()", _Mod) -> #{type => number, minimum => 1};
typename_to_spec("number()", _Mod) -> #{type => number};
typename_to_spec("string()", _Mod) -> #{type => string};
typename_to_spec("atom()", _Mod) -> #{type => string};

typename_to_spec("duration()", _Mod) -> #{type => duration};
typename_to_spec("duration_s()", _Mod) -> #{type => duration};
typename_to_spec("duration_ms()", _Mod) -> #{type => duration};
typename_to_spec("percent()", _Mod) -> #{type => percent};
typename_to_spec("file()", _Mod) -> #{type => string};
typename_to_spec("ip_port()", _Mod) -> #{type => ip_port};
typename_to_spec("url()", _Mod) -> #{type => url};
typename_to_spec("bytesize()", _Mod) -> #{type => byteSize};
typename_to_spec("wordsize()", _Mod) -> #{type => byteSize};
typename_to_spec("qos()", _Mod) -> #{type => enum, symbols => [0, 1, 2]};
typename_to_spec("comma_separated_list()", _Mod) -> #{type => comma_separated_string};
typename_to_spec("comma_separated_atoms()", _Mod) -> #{type => comma_separated_string};
typename_to_spec("pool_type()", _Mod) -> #{type => enum, symbols => [random, hash]};
typename_to_spec("log_level()", _Mod) ->
    #{type => enum, symbols => [debug, info, notice, warning, error, critical, alert, emergency, all]};
typename_to_spec("rate()", _Mod) -> #{type => string};
typename_to_spec("capacity()", _Mod) -> #{type => string};
typename_to_spec("burst_rate()", _Mod) -> #{type => string};
typename_to_spec("failure_strategy()", _Mod) -> #{type => enum, symbols => [force, drop, throw]};
typename_to_spec("initial()", _Mod) -> #{type => string};
typename_to_spec(Name, Mod) ->
    Spec = range(Name),
    Spec1 = remote_module_type(Spec, Name, Mod),
    Spec2 = typerefl_array(Spec1, Name, Mod),
    Spec3 = integer(Spec2, Name),
    default_type(Spec3).

default_type(nomatch) -> #{type => string};
default_type(Type) -> Type.

range(Name) ->
    case string:split(Name, "..") of
        [MinStr, MaxStr] -> %% 1..10 1..inf -inf..10
            Schema = #{type => number},
            Schema1 = add_integer_prop(Schema, minimum, MinStr),
            add_integer_prop(Schema1, maximum, MaxStr);
        _ -> nomatch
    end.

%% Module:Type
remote_module_type(nomatch, Name, Mod) ->
    case string:split(Name, ":") of
        [_Module, Type] -> typename_to_spec(Type, Mod);
        _ -> nomatch
    end;
remote_module_type(Spec, _Name, _Mod) -> Spec.

%% [string()] or [integer()] or [xxx].
typerefl_array(nomatch, Name, Mod) ->
    case string:trim(Name, leading, "[") of
        Name -> nomatch;
        Name1 ->
            case string:trim(Name1, trailing, "]") of
                Name1 -> notmatch;
                Name2 ->
                    Schema = typename_to_spec(Name2, Mod),
                    #{type => array, items => Schema}
            end
    end;
typerefl_array(Spec, _Name, _Mod) -> Spec.

%% integer(1)
integer(nomatch, Name) ->
    case string:to_integer(Name) of
        {Int, []} -> #{type => enum, symbols => [Int], default => Int};
        _ -> nomatch
    end;
integer(Spec, _Name) -> Spec.

add_integer_prop(Schema, Key, Value) ->
    case string:to_integer(Value) of
        {error, no_integer} -> Schema;
        {Int, []}when Key =:= minimum -> Schema#{Key => Int};
        {Int, []} -> Schema#{Key => Int}
    end.

to_bin(List) when is_list(List) ->
    case io_lib:printable_list(List) of
        true -> unicode:characters_to_binary(List);
        false -> List
    end;
to_bin(Boolean) when is_boolean(Boolean) -> Boolean;
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(X) -> X.
