/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2010-2021, Tarantool AUTHORS, please see AUTHORS file.
 */
#include "lua/uri.h"

#include "lua/utils.h"
#include "uri/uri.h"
#include "diag.h"

/**
 * Add or overwrite (depends on @a overwrite) URI query parameter to @a uri.
 * Parameter value is located at the top of the lua stack, parameter name is
 * in the position next to it. Allowed types for URI query parameter values
 * are LUA_TSTRING, LUA_TNUMBER and LUA_TTABLE. URI query parameter name should
 * be a string.
 */
static int
uri_add_param_from_lua(struct uri *uri, struct lua_State *L, bool overwrite)
{
	if (lua_type(L, -2) != LUA_TSTRING) {
		diag_set(IllegalParams, "Incorrect type for URI query "
			 "parameter name: should be a string");
		return -1;
	}
	const char *name = lua_tostring(L, -2);
	if (overwrite) {
		uri_remove_query_param(uri, name);
	} else if (uri_query_param_count(uri, name) != 0) {
		return 0;
	}
	int rc = 0;
	switch (lua_type(L, -1)) {
	case LUA_TSTRING:
	case LUA_TNUMBER:
		uri_add_query_param(uri, name, lua_tostring(L, -1));
		break;
	case LUA_TTABLE:
		for (unsigned i = 0; i < lua_objlen(L, -1) && rc == 0; i++) {
			lua_rawgeti(L, -1, i + 1);
			const char *value = lua_tostring(L, -1);
			if (value != NULL) {
				uri_add_query_param(uri, name, value);
			} else {
				diag_set(IllegalParams, "Incorrect type for "
					 "URI query parameter value: should "
					 "be string or number");
				rc = -1;
			}
			lua_pop(L, 1);
		}
		break;
	default:
		diag_set(IllegalParams, "Incorrect type for URI query "
			 "parameter: should be string, number or table");
		rc = -1;
	}
	return rc;
}

/**
 * Add or overwrite (depends on @a overwrite) URI query parameters in @a uri.
 * Table with parameters or nil value should be located at the top of the lua
 * stack.
 */
static int
uri_add_params_from_lua(struct uri *uri, struct lua_State *L, bool overwrite)
{
	if (lua_type(L, -1) == LUA_TNIL) {
		return 0;
	} else if (lua_type(L, -1) != LUA_TTABLE) {
		diag_set(IllegalParams, "Incorrect type for URI query "
			 "parameters: should be a table");
		return -1;
	}
	int rc = 0;
	lua_pushnil(L);
	while (lua_next(L, -2) != 0 && rc == 0) {
		rc = uri_add_param_from_lua(uri, L, overwrite);
		assert(rc == 0 || !diag_is_empty(diag_get()));
		lua_pop(L, 1);
	}
	return rc;
}

/**
 * Check if there is a field with the name @a name in the table,
 * which located which located at the given valid @a idx, which
 * should be positive value.
 */
static bool
is_field_present(struct lua_State *L, const char *name, int idx)
{
	assert(lua_type(L, idx) == LUA_TTABLE);
	lua_pushstring(L, name);
	lua_rawget(L, idx);
	bool field_is_present = (lua_type(L, -1) != LUA_TNIL);
	lua_pop(L, 1);
	return field_is_present;
}

/**
 * Create @a uri from the table, which located at the given valid @a idx,
 * which should be positive value.
 */
static int
uri_create_from_lua_table(struct uri *uri, struct lua_State *L, int idx)
{
	assert(lua_type(L, idx) == LUA_TTABLE);
	/* There should be exactly one URI in the table */
	int size = lua_objlen(L, idx);
	int uri_count = size + is_field_present(L, "uri", idx);
	if (uri_count != 1) {
		diag_set(IllegalParams, "Invalid URI table: "
			 "expected {uri = string, params = table} "
			 "or {string, params = table}");
		return -1;
	}
	/* Table "default_params" is not allowed for single URI */
	if (is_field_present(L, "default_params", idx)) {
		diag_set(IllegalParams, "Default URI query parameters are "
			 "not allowed for single URI");
		return -1;
	}
	int rc = 0;
	if (size == 1) {
		lua_rawgeti(L, idx, 1);
	} else {
		lua_pushstring(L, "uri");
		lua_rawget(L, idx);
	}
	const char *uristr = lua_tostring(L, -1);
	if (uristr != NULL) {
		rc = uri_create(uri, uristr);
		if (rc != 0) {
			diag_set(IllegalParams, "Incorrect URI: expected "
				 "host:service or /unix.socket");
		}
	} else {
		diag_set(IllegalParams, "Incorrect type for URI in nested "
			 "table: should be string, number");
		rc = -1;
	}
	lua_pop(L, 1);
	if (rc != 0)
		return rc;
	lua_pushstring(L, "params");
	lua_rawget(L, idx);
	rc = uri_add_params_from_lua(uri, L, true);
	lua_pop(L, 1);
	return rc;

}

/**
 * Create @a uri from the value at the given valid @a idx, which
 * should be positive value.
 */
static int
luaT_uri_create(struct lua_State *L, struct uri *uri, int idx)
{
	int rc = 0;
	uri_create(uri, NULL);
	if (lua_isstring(L, idx)) {
		rc = uri_create(uri, lua_tostring(L, idx));
		if (rc != 0) {
			diag_set(IllegalParams, "Incorrect URI: "
				 "expected host:service or "
				 "/unix.socket");
		}
	} else if (lua_istable(L, idx)) {
		rc = uri_create_from_lua_table(uri, L, idx);
	} else if (!lua_isnil(L, idx)) {
		diag_set(IllegalParams, "Incorrect type for URI: "
			 "should be string, number or table");
		rc = -1;
	}
	assert(rc == 0 || !diag_is_empty(diag_get()));
	return rc;
}

/**
 * Create @a uri_set from the table, which located at the given valid @a idx,
 * which should be positive value.
 */
static int
uri_set_create_from_lua_table(struct uri_set *uri_set, struct lua_State *L,
			      int idx)
{
	int rc = 0;;
	assert(lua_type(L, idx) == LUA_TTABLE);
	int size = lua_objlen(L, idx);
	int uri_count = size + is_field_present(L, "uri", idx);
	if (uri_count == 0)
		return 0;

	struct uri uri;
	/*
	 * If the number of numeric keys in the lua table is less
	 * than or equal to one, it means that there is no more than
	 * one URI in it.
	 */
	if (uri_count <= 1) {
		rc = luaT_uri_create(L, &uri, idx);
		if (rc == 0)
			uri_set_add(uri_set, &uri);
		return rc;
	}
	/*
	 * All numeric keys corresponds to URIs in string or table
	 * format.
	 */
	for (int i = 0; i < size && rc == 0; i++) {
		lua_rawgeti(L, idx, i + 1);
		rc = luaT_uri_create(L, &uri, lua_gettop(L));
		if (rc == 0)
			uri_set_add(uri_set, &uri);
		lua_pop(L, 1);
	}
	if (rc != 0)
		return rc;

	/*
	 * Here we are only in case when uri_count greater than one,
	 * so is shouldn't be "uri" and "params" field here.
	 */
	if (is_field_present(L, "uri", idx)) {
		diag_set(IllegalParams, "Invalid URI table: "
			 "expected {uri = string, params = table}, "
			 "{string, params = table} or "
			 "string, {uri, params = table}");
		return -1;
	}

	if (is_field_present(L, "params", idx)) {
		diag_set(IllegalParams, "URI query parameters are "
			 "not allowed for multiple URIs");
		return -1;
	}

	for (int i = 0; i < uri_set->uri_count && rc == 0; i++) {
		struct uri *uri = &uri_set->uris[i];
		lua_pushstring(L, "default_params");
		lua_rawget(L, idx);
		rc = uri_add_params_from_lua(uri, L, false);
		lua_pop(L, 1);
		assert(rc == 0 || !diag_is_empty(diag_get()));
	}
	return rc;
}

/**
 * Create @a uri_set from the value at the given valid @a idx, which should be
 * positive value.
 */
static int
luaT_uri_set_create(struct lua_State *L, struct uri_set *uri_set, int idx)
{
	int rc = 0;
	uri_set_create(uri_set, NULL);
	if (lua_isstring(L, idx)) {
		rc = uri_set_create(uri_set, lua_tostring(L, idx));
		if (rc != 0) {
			diag_set(IllegalParams, "Incorrect URI: "
				 "expected host:service or "
				 "/unix.socket");
		}
	} else if (lua_istable(L, idx)) {
		rc = uri_set_create_from_lua_table(uri_set, L, idx);
	} else if (!lua_isnil(L, idx)) {
		diag_set(IllegalParams, "Incorrect type for URI: "
			 "should be string, number or table");
		rc = -1;
	}
	assert(rc == 0 || !diag_is_empty(diag_get()));
	return rc;
}

static int
lbox_uri_create(lua_State *L)
{
	int rc = -1;
	struct uri *uri = (struct uri *)lua_topointer(L, 1);
	if (uri != NULL) {
		rc = luaT_uri_create(L, uri, 2);
		/**
		 * We don't call lua_error to maintain
		 * backward compatibility.
		 */
		if (rc != 0)
			diag_clear(diag_get());
	}
	lua_pushnumber(L, rc);
	return 1;
}

static int
lbox_uri_set_create(lua_State *L)
{
	int rc = -1;
	struct uri_set *uri_set = (struct uri_set *)lua_topointer(L, 1);
	if (uri_set != NULL) {
		rc = luaT_uri_set_create(L, uri_set, 2);
		/**
		 * We don't call lua_error to maintain
		 * backward compatibility.
		 */
		if (rc != 0)
			diag_clear(diag_get());
	}
	lua_pushnumber(L, rc);
	return 1;
}

void
tarantool_lua_uri_init(struct lua_State *L)
{
	static const struct luaL_Reg uri_methods[] = {
		{NULL, NULL}
	};
	luaL_register_module(L, "uri", uri_methods);

	/* internal table */
	lua_pushliteral(L, "internal");
	lua_newtable(L);
	static const struct luaL_Reg uri_internal_methods[] = {
		{"uri_create", lbox_uri_create},
		{"uri_set_create", lbox_uri_set_create},
		{NULL, NULL}
	};
	luaL_register(L, NULL, uri_internal_methods);
	lua_settable(L, -3);

	lua_pop(L, 1);
};
