local crypto = require('crypto')
local json = require('json')
local log = require('log')
local fio = require('fio')

local integrity = { }

local hashes = { }
local known_hash_types = {
    sha256 = true,
}

local hashes_cwd

-- The following values are allowed:
-- * 'Unchecked'
-- * 'Running'
-- * 'Blocked'
--
-- The instance may change the state by the following rules:
-- * 'Unchecked' -> 'Running' - with enable_integrity_check() call
-- * 'Running'   -> 'Blocked' - on verify_file() failure or 
--                              on block_instance() call
-- * 'Blocked'   -> 'Running' - on load_hashes() success
--
local integrity_state = 'Unchecked'

function integrity.block_instance()
    if integrity_state ~= 'Running' then
        return
    end

    integrity_state = 'Blocked'
    log.error("integrity: instance is blocked")
    -- TODO: add actual IPROTO block.
    -- TODO: add critical log warning/error.
end

-- It doesn't seem safe to leave unblock in the API.
-- To unblock the instance call `load_hashes()`, that
-- gets new hashes and unblocks on success.
local function unblock_instance()
    if integrity_state ~= 'Blocked' then
        return
    end

    integrity_state = 'Running'
    log.warn("integrity: instance is unblocked")
    -- TODO: add actual IPROTO unblock.
end

local function internal_verify_file(path, buffer)
    if buffer == nil then
        local file = io.open(path, "r")
        if file == nil then
            return false
        end
        buffer = file:read("*a")
    end

    if buffer == nil or #buffer == 0 then
        return false
    end

    if hashes[path] == nil then
        return false
    end

    local hash_type = hashes[path].hash_type
    local expected_hash = hashes[path].hash

    local hash = crypto.digest[hash_type](buffer)
    local hex_hash = ''
    for i = 1, #hash do
        local byte = string.byte(hash, i)
        hex_hash = hex_hash .. string.format("%02x", byte)
    end

    -- XXX: remove debug prints.
    print("$"..buffer.."$")
    print(hex_hash)
    print(expected_hash)

    if hex_hash ~= expected_hash then
        return false
    end

    return true
end

function integrity.verify_file(path, buffer)
    local res = internal_verify_file(path, buffer)
    if not res then
        integrity.block_instance()
    end
    return res
end

function integrity.load_hashes(hashes_path)
    print("integrity_init() called!")
    hashes = { }

    -- TODO: verify hashes.json with signature.
    local hashes_file = io.open(hashes_path, "r")
    if not hashes_file then
        -- TODO: better error msgs?
        error("integrity: failed to read hashes.json")
    end

    local hashes_file_contents = hashes_file:read("*a")
    if hashes_file_contents == nil then
        error("integrity: failed to read hashes.json")
    end

    local success, res = pcall(json.decode, hashes_file_contents)
    if (not success) then
        error(res)
    end
    if (type(res) ~= "table") then
        error("integrity: bad hashes.json format")
    end

    hashes_cwd = fio.abspath(hashes_path):match("(.*[/\\])")

    for _, file in ipairs(res.files or {}) do
        local path
        local hash_type
        local hash
        for k, v in pairs(file) do
            if k == "path" then
                path = v
            elseif hash_type == nil and known_hash_types[k] then
                hash_type = k
                hash = v
            else
                error("integrity: bad hashes.json format")
            end
        end

        if type(path) ~= "string" or type(hash) ~= "string" then
            error("integrity: bad hashes.json format")
        end

        path = fio.abspath(fio.pathjoin(hashes_cwd, path))

        -- The hash comes in hex and it can include upper-case letters.
        -- For the future comparison, lets lower the string.
        hash = string.lower(hash)

        hashes[path] = {
            hash_type = hash_type,
            hash = hash,
        }

        -- Check the hash correctness.
        -- It is ok, if there isn't such file at this moment.
        local checked_file = io.open(path, "r")
        if checked_file ~= nil then
            checked_file:close()
            if not integrity.verify_file(path) then
                return
            end
        end
    end

    unblock_instance()
end

function integrity.enable_integrity_check(hashes_path, sig_path)
    if integrity_state ~= "Unchecked" then
        return
    end

    print("integrity control enabled!")

    integrity_state = "Running"


    -- Note that signature unlike hashes.json file should be read only on
    -- instance startup, so do it outside load_hashes().

    -- TODO: read the signature file.

    integrity.load_hashes(hashes_path)
end

return integrity
