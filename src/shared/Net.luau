--!strict
-- Remote definitions. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.FolderName = "Remotes"

local DEFINITIONS = {
	Request = "RemoteFunction", -- client -> server: (action, payload) -> { ok, message?, data? }
	State = "RemoteEvent", -- server -> owner: profile snapshot
	Notify = "RemoteEvent", -- server -> client: (kind, payload) toasts, rewards
	Effect = "RemoteEvent", -- server -> clients: (name, payload) world effects
	Ability = "RemoteEvent", -- client -> server: (abilityId, aimDirection)
}

export type Remotes = {
	Request: RemoteFunction,
	State: RemoteEvent,
	Notify: RemoteEvent,
	Effect: RemoteEvent,
	Ability: RemoteEvent,
}

function Net.createServer(): Remotes
	local folder = ReplicatedStorage:FindFirstChild(Net.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FolderName
		folder.Parent = ReplicatedStorage
	end
	local remotes = {}
	for name: string, className: string in DEFINITIONS :: { [string]: string } do
		local remote = folder:FindFirstChild(name)
		if not remote then
			local created = Instance.new(className)
			created.Name = name
			created.Parent = folder
			remote = created
		end
		remotes[name] = remote
	end
	return remotes :: any
end

function Net.waitClient(): Remotes
	local folder = ReplicatedStorage:WaitForChild(Net.FolderName)
	local remotes = {}
	for name in DEFINITIONS do
		remotes[name] = folder:WaitForChild(name)
	end
	return remotes :: any
end

return Net
