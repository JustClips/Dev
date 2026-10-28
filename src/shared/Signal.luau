--!strict
-- Minimal signal for module-to-module events (no Instances, no yielding between handlers).
export type Connection = { Disconnect: (Connection) -> () }
export type Signal<T...> = {
	Connect: (Signal<T...>, (T...) -> ()) -> Connection,
	Fire: (Signal<T...>, T...) -> (),
	_handlers: { (T...) -> () },
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _handlers = {} }, Signal) :: any
end

function Signal:Connect(fn)
	table.insert(self._handlers, fn)
	local handlers = self._handlers
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	} :: any
end

function Signal:Fire(...)
	-- Copy so handlers can disconnect while firing. Each runs in its own thread so
	-- one erroring or yielding handler can't break the others.
	for _, fn in table.clone(self._handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
