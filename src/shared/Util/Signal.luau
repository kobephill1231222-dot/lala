--!strict
-- Minimal signal used by client controllers.

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

function Signal.new()
	return setmetatable({ _handlers = {} :: { [any]: (...any) -> () } }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local key = {}
	self._handlers[key] = handler
	local signal = self
	local connection = { Connected = true }
	function connection.Disconnect(conn)
		conn.Connected = false
		signal._handlers[key] = nil
	end
	return connection :: any
end

function Signal:Fire(...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
