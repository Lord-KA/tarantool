local t = require('luatest')
local g = t.group()
local compat = require('compat')

g.before_all(compat.reset)
g.after_all(compat.reset)

local option_1_called = false
local option_2_called = false

local policies = {
    option_1_policy = {
        'option_1', {
            old = false,
            new = true,
            default = 'new',
            brief = "option_1",
            doc = "https://tarantool.io",
            frozen = false
        },
        function()
            option_1_called = true
        end
    },
    option_2_policy = {
        'option_2', {
            old = true,
            new = false,
            default = 'old',
            brief = "option_2",
            doc = "https://tarantool.io",
            frozen = false
        },
        function()
            option_2_called = true
        end
  },
}

local frozen_policy = {
    'frozen_option', {
        old = true,
        new = false,
        default = false,
        brief = "frozen_option",
        doc = "https://tarantool.io",
        frozen = true
    },
    nil
  }

local test_options_calls = function()
    t.assert(option_1_called)
    t.assert(option_2_called)
    option_1_called = false
    option_2_called = false
end

g.test_add_options = function()
    for _, elem in pairs(policies) do
        compat.add_options({elem})
    end
    t.assert_equals(type(compat.option_1), "table")
    t.assert_equals(type(compat.option_2), "table")
    test_options_calls()

    local bad_policy = {                        -- Frozen option with default == old.
        'bad_option_1', {
            old = true,
            new = false,
            default = true,
            frozen = true,
            brief = 'bad_option',
            doc = 'https://tarantool.io',
        },
        nil
    }

    t.assert_error(compat.add_options, bad_policy)

    bad_policy = {                              -- Unfrozen option with bad action.
        'bad_option_2', {
            old = true,
            new = false,
            default = false,
            frozen = false,
            brief = 'bad_option',
            doc = 'https://tarantool.io',
        },
        "function"
    }

    t.assert_error(compat.add_options, bad_policy)

    bad_policy = {                              -- Wrong name type.
        {}, {
            old = true,
            new = false,
            default = false,
            frozen = false,
            brief = 'bad_option',
            doc = 'https://tarantool.io',
        },
        function()
            print("bad_option called!")
        end
    }

    t.assert_error(compat.add_options, bad_policy)

    bad_policy = {                              -- Name already in use.
        "option_2", {
            old = true,
            new = false,
            default = false,
            frozen = false,
            brief = 'bad_option',
            doc = 'https://tarantool.io',
        },
        function()
            print("bad_option called!")
        end
    }

    t.assert_error(compat.add_options, bad_policy)

end

-- All values should be defaults as if right after add_options().
g.test_index = function()
    for _, policy in pairs(policies) do
        local name, option = unpack(policy)
        for param, val in pairs(option) do
            t.assert_equals(compat[name][param], val)
        end
        t.assert_equals(compat[name].value, option.default)
    end
end

-- There should be no frozen options in policies.
g.test_new_index = function()
    for _, policy in pairs(policies) do
        local name, option = unpack(policy)
        compat[name] = false
        compat[name] = true
        compat[name] = 'default'
        compat[name] = 'old'
        compat[name] = 'new'
        t.assert_equals(compat[name].value, option.new)
    end
    test_options_calls()
    t.assert_error(getmetatable(compat).__newindex, compat, 'option_1', 'invalid_value')
    t.assert_error(getmetatable(compat).__newindex, compat, 'no_such_option', 'old')
end

g.test_reset = function()
    compat.reset()
    for _, policy in pairs(policies) do
        local name, option = unpack(policy)
        t.assert_equals(compat[name].value, option.default)
    end
    test_options_calls()
end

-- There should be no frozen options in policies.
g.test_call = function()
    local arg = { }
    for _, policy in pairs(policies) do
        local name = unpack(policy)
        arg[name] = 'old'
    end
    compat(arg)
    for _, policy in pairs(policies) do
        local name, option = unpack(policy)
        t.assert_equals(compat[name].value, option.old)
    end
    test_options_calls()
end

g.test_frozen = function()
    compat.add_options{frozen_policy}
    t.assert_error(getmetatable(compat).__newindex, compat, 'frozen_option', 'old')
end

-- At this point, all options have 'old' values, compat should not contain any
-- options besides ones in policies and the frozen one.
g.test_serialize = function()
    local res = { }
    for _, policy in pairs(policies) do
        local name, option = unpack(policy)
        res[name] = option
        res[name].value = option.old
    end
    local name, option = unpack(frozen_policy)
    res[name] = option
    res[name].value = option.new

    t.assert_items_include(getmetatable(compat).__serialize(compat), res)
end

-- Only option_1 is restored.
g.test_restore = function()
    compat.restore{'option_1'}
    t.assert_equals(compat.option_1.value, compat.option_1.default)
    t.assert_equals(compat.option_2.value, compat.option_2.old)
    option_1_called = false
end

-- At this point, option_1 should be default and other options from policies
-- have 'old' values.
g.test_get_setup = function()
    local res = 'require("tarantool").compat({'
    local isFirst  = true
    local isSecond = true
    for _, policy in pairs(policies) do
        local name, option = unpack(policy)
        if not isFirst then
            if not isSecond then
                res = res .. ", "
            end
            res = res .. name .. " = " .. tostring(option.old)
            isSecond = false
        end
        isFirst = false
    end
    res = res .. "})"
    t.assert_equals(res, compat.get_setup())
end

-- Compat should not contain any options besides ones in policies and the frozen one.
g.test_candidates = function()
    compat.reset()
    compat.option_1 = 'new'
    local isFirst = true
    local res = { }
    for _, policy in pairs(policies) do
        local name = unpack(policy)
        if not isFirst then
            res[name] = policy[2]
            res[name].value = policy[2].old
        end
        isFirst = false
    end
    t.assert_items_include(compat.candidates(), res)
end

g.test_help = function()
    compat.help()
end

-- Autocomplete tests.

local console = require('console')
local server  = require('test.luatest_helpers.server')

local function tabcomplete(s)
    return console.completion_handler(s, 0, #s)
end

-- Compat should not contain any options besides ones in policies and the frozen one.
g.test_autocomplete = function()
    g.server = server:new({alias = 'master'})
    g.server:start()
    g.server:exec(function()
        box.schema.create_space('space1'):create_index('primary')
    end)
    rawset(_G, 'compat', compat)

    local res = {
        "compat.",
        "compat.get_setup(",
        "compat.reset(",
        "compat.help(",
        "compat.restore(",
        "compat.candidates(",
        "compat.add_options("
    }
    local cnt = 7
    for name, option in pairs(getmetatable(compat).__serialize(compat)) do
        if not option.frozen then
            cnt = cnt + 1
            res[cnt] = "compat." .. name
        end
    end

    t.assert_items_equals(res, tabcomplete('compat.'))

    g.server:stop()
end
