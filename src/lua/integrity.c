/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2023-2023, Tarantool AUTHORS, please see AUTHORS file.
 */

#include <lua/integrity.h>

static struct lua_State *L = NULL;

bool integrity_verify_file(const char *path, const char *buffer, size_t size)
{
	printf("verify_file() called in C!\n");
	assert(L != NULL);

	lua_getglobal(L, "require");
	lua_pushstring(L, "integrity");
	lua_call(L, 1, 1);
	lua_getfield(L, -1, "verify_file");

	lua_pushstring(L, path);

	if (buffer == NULL || size == 0)
		lua_pushnil(L);
	else
		lua_pushlstring(L, buffer, size);


	lua_pcall(L, 2, 1, 0); // TODO: check for errors?

	bool result = lua_toboolean(L, -1);
	lua_pop(L, 1);

	return result;
}

// TODO: remove, for test only.
static int lbox_integrity_check_test(struct lua_State *L)
{
	printf("Hello integrity!\n");

	if (integrity_verify_file("test_file.txt", NULL, 5))
		printf("Success!\n");
	else
		printf("Failed!\n");

	if (integrity_verify_file("path/to/file", "hello", 5))
		printf("Success!\n");
	else
		printf("Failed!\n");

	if (integrity_verify_file("path/to/file2", "hello", 5))
		printf("Success!\n");
	else
		printf("Failed!\n");

	return 0;
}

// TODO: remove, for test only.
static const struct luaL_Reg internal_integrity[] = {
       {"test", lbox_integrity_check_test},
       {NULL, NULL},
};

int
tarantool_lua_integrity_init(struct lua_State *state)
{
	L = state;

	// TODO: remove, for test only.
	luaL_register(L, "integrity_test", internal_integrity);

	return 0;
}
