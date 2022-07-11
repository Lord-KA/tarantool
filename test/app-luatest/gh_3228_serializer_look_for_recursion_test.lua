local t = require('luatest')
local g = t.group()

local function check_serialize(table, serialize, res)
    assert(type(serialize) == 'function')
    setmetatable(table, {__serialize = serialize})
    t.assert_equals(getmetatable(table).__serialize(table), res)
end

g.test_recursive_serialize = function()
    --
    -- Check that recursive structures are serialized properly.
    --
    check_serialize({}, function(a) return {a} end,         {{}})
    check_serialize({}, function(a) return {a, a} end,      {{}, {}})
    check_serialize({}, function(a) return {a, a, a} end,   {{}, {}, {}})
    check_serialize({}, function(a) return {{a, a}, a} end, {{{}, {}}, {}})
    check_serialize({}, function(a) return {a, 1} end,      {{}, 1})
    check_serialize({}, function(a) return {{{{{a}}}}} end, {{{{{{}}}}}})

    local b = {}
    check_serialize({b}, function(a) return {a_1 = a, a_2 = a, b_1 = b, b_2 = b} end, {a_1 = {b}, a_2 = {}, b_1 = b, b_2 = b})
    check_serialize({b}, function(a) return {a_1 = a, a_2 = {a, b}, b = b} end, {a_1 = {{}}, a_2 = {{}, {}}, b = b} )

    local a = {}
    a[a] = a
    local recf = function(_) return setmetatable({}, {__serialize = recf}) end
    check_serialize(a, recf, {a_1 = {{}}, a_2 = {{}, {}}})
end

g.test_pure_serialize = function()
    --
    -- __serialize function is pure, i.e. always returns identical
    -- value for identical argument. Otherwise, the behavior is
    -- undefined. So that, we ignore the side effects and just use the
    -- value after the first serialization.
    --
    local a = {}
    local b = {}
    b[a] = a
    local show_a = true
    local serialize = function()
        show_a = not show_a
        if show_a then
            return "a"
        else
            return "b" end
    end;
    setmetatable(a, {__serialize = serialize})

    do
        local a = {}
        local b = {}
        b[a] = a
        local reta
        local retb
        local function swap_ser(o)
            local newf
            local f = getmetatable(o).__serialize
            if f == reta then
                newf = retb
            else
                newf = reta
            end
            getmetatable(o).__serialize = newf
        end
        reta = function(o) swap_ser(o) return "a" end
        retb = function(o) swap_ser(o) return "b" end
        setmetatable(a, {__serialize = reta})
        return b
    end
end

g.test_nil_serialize = function()
    --
    -- Check the case, when "__serialize" returns nil.
    --
    check_serialize({}, function(_) return nil end, nil)
end
