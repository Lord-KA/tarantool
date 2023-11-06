/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2023-2023, Tarantool AUTHORS, please see AUTHORS file.
 */

#pragma once

#include "lua/utils.h"

#if defined(__cplusplus)
extern "C" {
#endif

struct lua_State;

int tarantool_lua_integrity_init(struct lua_State *L);

bool integrity_verify_file(const char *path, const char *buffer, size_t size);

#if defined(__cplusplus)
}
#endif
