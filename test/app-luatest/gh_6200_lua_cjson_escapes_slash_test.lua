local compat = require('compat')
local json = require('json')
local t = require('luatest')
local g = t.group()

g.test_json_encode = function()
    compat.json_escape_forward_slash = 'old'
    -- Test that '/' is escaped with 'old' setting.
    t.assert_equals(json.encode({url = "https://srv:7777"}), '{"url":"https:\\/\\/srv:7777"}')
    t.assert_equals(json.encode("/home/user/tarantool"), [["\/home\/user\/tarantool"]])
    -- Test that other escape symbols are not affected by the setting.
    t.assert_equals(json.encode("\t"), [["\t"]])
    t.assert_equals(json.encode("\\"), [["\\"]])

    compat.json_escape_forward_slash = 'new'
    -- Test that '/' is not escaped with 'new' setting.
    t.assert_equals(json.encode({url = "https://srv:7777"}), [[{"url":"https://srv:7777"}]])
    t.assert_equals(json.encode("/home/user/tarantool"), [["/home/user/tarantool"]])
    -- Test that other escape symbols are not affected by the setting.
    t.assert_equals(json.encode("\t"), [["\t"]])
    t.assert_equals(json.encode("\\"), [["\\"]])

    -- Restore options defaults.
    compat.json_escape_forward_slash = 'default'
end

g.test_json_new_encode = function()
    compat.json_escape_forward_slash = 'old'
    -- Test that '/' is escaped with 'old' setting.
    t.assert_equals(json.encode("/"), [["\/"]])

    -- Create new serializer and check that it has correct defaults and doesn't change behavior.
    local json_old = json.new()
    t.assert_equals(json_old.encode("/"), [["\/"]])
    compat.json_escape_forward_slash = 'new'
    t.assert_equals(json_old.encode("/"), [["\/"]])
    t.assert_equals(json.encode("/"), [["/"]])

    -- Create new serializer and check that it has correct defaults.
    local json_new = json.new()
    t.assert_equals(json_new.encode("/"), [["/"]])

    -- Restore options defaults.
    compat.json_escape_forward_slash = 'default'
end

--FIXME add msgpuck tests
