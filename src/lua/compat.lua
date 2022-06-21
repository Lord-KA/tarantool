-- compat.lua -- internal module intended to solve compatibility problems in
-- different parts of Tarantool. Introduced in gh-7000, see also gh-6912.

local options_format = {
    old     = 'boolean',
    new     = 'boolean',
    default = 'boolean',
    frozen  = 'boolean',
    brief   = 'string',
    doc     = 'string'
}

local JSON_ESCAPE_BRIEF = [[
Whether to escape the forward slash symbol '/' using a backslash in a json.encode()
result. The old and the new behaviour produce a result, which is compatible
with the JSON specification. However most of other JSON encoders don't escape
the forward slash, so we consider the new behaviour as more safe one.
]]

-- Contains static options descriptions in format specified by `options_format`.
local options = {
    json_escape_forward_slash = {
        old = true,
        new = false,
        default = 'old',
        frozen = false,
        brief = JSON_ESCAPE_BRIEF,
        doc  = "https://github.com/tarantool/tarantool/wiki/compat_json_escape_forward_slash"
    },
}

-- Contains postaction functions for each unfrozen option from `options`.
local postaction = {
    json_escape_forward_slash = function(value)
        require('json').cfg{encode_esc_slash = value}
        local ffi = require('ffi')
        ffi.cdef[[
                extern void json_esc_slash_toggle(bool value);
        ]]
        ffi.C.json_esc_slash_toggle(value);
        tarantool_lua_msgpuck_esc_slash_toggle(value);
    end,
}

-- Contains dynamic values: current state of an option and is it selected.
local cfg = { }

local help = [[

This is Tarantool compatibility module.
To get help, see the Tarantool manual at https://tarantool.io/en/doc/.
Available commands:

    candidates()                    -- list all unselected options
    get_setup()                     -- get Lua command that sets up different compat with same options as current
    help()                          -- show this help
    reset()                         -- set all options to default
    add_options()                   -- add new options by providing name, option table and postaction for each one
    restore{'option_name'}          -- set to default specified options
    {option_name = true}            -- set listed options to desired values (true, false, 'old', 'new', 'default')
    option_name                     -- list option info
    option_name = true              -- set desired value to option, could be true, false, 'old', 'new', 'default'
]]

-- Returns table with combined info on option from `options` and `cfg`.
local function serialize_policy(key, policy)
    assert(key    ~= nil)
    assert(policy ~= nil)
    local result = table.deepcopy(policy)
    result.value = cfg[key].value
    return result
end

-- FIXME should it list frozen options?
-- Returns info on all unfrozen options from `options`.
local function serialize_compat()
    local result = { }
    for key, val in pairs(options) do
        result[key] = serialize_policy(key, val)
    end
    return result
end

-- Checks options correctness and sets `option.default` to boolean value if needed.
local function verify_option(name, option)
    if type(name) ~= 'string' then
        error(('Option name must be a string (%s provided)'):format(type(name)))
    end
    if option.default == 'new' then
        option.default = option.new
    elseif option.default == 'old' then
        option.default = option.old
    end
    for p, t in pairs(options_format) do
        if type(option[p]) ~= t then
            error(('Invalid option table for %s, bad %s (%s is expected)'):format(name, p, t))
        end
    end
    if option.frozen and not option.default == option.new then
        error(('Frozen option %s default is wrong'):format(name))
    end
    if option.new == option.old then
        error(('In option %s old and new contain the same value'):format(name))
    end
end

-- Checks if operation is valid, sets value to an option and runs postaction.
local function set_option(name, val)
    local option = options[name]
    if not option then
        error(('Invalid option %s'):format(name))
    end
    if val == 'new' then
        val = option.new
    end
    if val == 'old' then
        val = option.old
    end
    local default = false;
    if val == 'default' then
        val = option.default
        default = true
    end
    if type(val) ~= 'boolean' then
        error(('Invalid argument %s'):format(val))
    end
    local log = require('log')          -- Log can't be required at the beginning, as it isn't initialized by then.
    if not option.frozen then
        if option.default == option.new and val == option.old then
            log.warn('Chosen option in %s provides outdated behavior and will soon get frozen', name)
            log.warn('For more info, see the Tarantool manual at %s', option.doc)
        end
        postaction[name](val)
    elseif not default then
        if val == option.new then
            log.warn('Chosen option in %s is the only available', name)
        else
            error('Chosen option is no longer available')
        end
    end
    cfg[name].value = val
    cfg[name].selected = true
end

local compat = setmetatable({
    candidates = function()
        local result = { }
        for key, val in pairs(options) do
            if not cfg[key].selected and not options[key].frozen then
                result[key] = serialize_policy(key, val)
            end
        end
        return result
    end,
    get_setup = function()
        local result = 'require("tarantool").compat({'
        local is_first = true
        for key, _ in pairs(options) do
            if cfg[key].selected then
                if not is_first then
                    result = result .. ', '
                end
                result = result .. key ..  ' = ' .. tostring(cfg[key].value)
                is_first = false
            end
        end
        return result .. '})'
    end,
    reset = function()
        for key, _ in pairs(options) do
            set_option(key, 'default')
            cfg[key].selected = false
        end
    end,
    restore = function(list)
        if type(list) ~= 'table' then
            error(('Invalid argument %s (table is expected)'):format(list))
        end
        for _, name in pairs(list) do
            set_option(name, 'default')
            cfg[name].selected = false
        end
    end,
    add_options = function(list)
        if type(list) ~= 'table' then
            error(('Invalid argument %s (table is expected)'):format(list))
        end
        for _, val in pairs(list) do
            local name, option, action = unpack(val)
            if options[name] ~= nil then
                error(('Option %s already exists'):format(name))
            end
            verify_option(name, option)
            if not option.frozen and type(action) ~= 'function' then
                error(('Invalid postaction for %s'):format(name))
            end
            options[name] = option
            postaction[name] = action
            cfg[name] = {value = option.default, selected = false}
            if not option.frozen then
                action(option.default)
            end
        end
    end,
    preload = function()
        for key, elem in pairs(options) do
            verify_option(key, elem)
            cfg[key] = {value = elem.default, selected = false}
        end
    end,
    postload = function()
        for key, _ in pairs(options) do
            if not options[key].frozen then
                postaction[key](cfg[key].value)
            end
        end
    end,
    help = function()
        print(help)
    end
}, {
    __call = function(_, list)
        if type(list) ~= 'table' then
            error(('Invalid argument %s (table is expected)'):format(list))
        end
        for key, val in pairs(list) do
            set_option(key, val)
        end
    end,
    __newindex = function(_, key, val)
        set_option(key, val)
    end,
    __index = function(_, key)
        local policy = options[key]
        if not policy then
            error(('Invalid option %s'):format(key))
        end
        return serialize_policy(key, policy);
    end,
    __serialize = serialize_compat,
    __tostring  = function()
        return require('yaml').encode(serialize_compat())
    end,
    __autocomplete = function()
        local res = { }
        for key, _ in pairs(options) do
            if not options[key].frozen then
                res[key] = true
            end
        end
        return res
    end
})

-- This functions are to be run only once, thus we remove them not to confuse users.
compat.preload()
compat.preload = nil
--FIXME when should we perform postload?
compat.postload()
compat.postload = nil

return compat
