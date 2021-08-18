-- This test checks streams iplementation in iproto (gh-5860).
net_box = require('net.box')
fiber = require('fiber')
test_run = require('test_run').new()

test_run:cmd("create server test with script='box/iproto_streams.lua'")

test_run:cmd("setopt delimiter ';'")
function get_current_connection_count()
    local total_net_stat_table =
        test_run:cmd(string.format("eval test 'return box.stat.net()'"))[1]
    assert(total_net_stat_table)
    local connection_stat_table = total_net_stat_table.CONNECTIONS
    assert(connection_stat_table)
    return connection_stat_table.current
end;
function connection_send_async_requests(count, addr)
    local conn = net_box.connect(addr)
    local space = conn.space.test
    for i = 1, count do space:replace({i}, {is_async = true}) end
    conn:close()
end;
function stream_send_async_requests(count, addr)
    local conn = net_box.connect(addr)
    local stream = conn:new_stream()
    local space = stream.space.test
    stream:begin()
    for i = 1, count do space:replace({i}, {is_async = true}) end
    stream:commit({is_async = true})
    conn:close()
end;
test_run:cmd("setopt delimiter ''");

-- Some simple checks for new object - stream
test_run:cmd("start server test with args='10, true'")
test_run:switch("test")
test_run:cmd("setopt delimiter ';'")
function create_space_with_engine(engine)
    local s = box.schema.space.create('test', { engine = engine })
    local _ = s:create_index('primary')
    return s
end;
function check_requests_result_and_drop_space(space, count)
    local errinj = box.error.injection
    test_run:wait_cond(function ()
        return errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0
    end)
    test_run:wait_cond(function ()
        return errinj.get('ERRINJ_IPROTO_STREAM_MSG_COUNT') == 0
    end)
    local rc = space:select()
    space:drop()
    return (#rc == count)
end;
test_run:cmd("setopt delimiter ''");
test_run:switch("default")

server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
net_msg_max = test_run:cmd("eval test 'return box.cfg.net_msg_max'")[1]
test_run:switch("test")
s = create_space_with_engine("memtx")
test_run:switch('default')
connection_send_async_requests(net_msg_max - 1, server_addr)
test_run:switch("test")
assert(check_requests_result_and_drop_space(s, box.cfg.net_msg_max - 1))
s = create_space_with_engine("vinyl")
test_run:switch("default")
connection_send_async_requests(net_msg_max - 1, server_addr)
test_run:switch("test")
assert(check_requests_result_and_drop_space(s, box.cfg.net_msg_max - 1))
s = create_space_with_engine("memtx")
test_run:switch("default")
stream_send_async_requests(net_msg_max - 1, server_addr)
test_run:switch("test")
assert(check_requests_result_and_drop_space(s, box.cfg.net_msg_max - 1))
s = create_space_with_engine("vinyl")
test_run:switch("default")
stream_send_async_requests(net_msg_max - 1, server_addr)
test_run:switch("test")
assert(check_requests_result_and_drop_space(s, box.cfg.net_msg_max - 1))
test_run:switch("default")
test_run:wait_cond(function () return get_current_connection_count() == 0 end)

test_run:cmd("stop server test")
test_run:cmd("cleanup server test")
test_run:cmd("delete server test")
