--// RBX-NET: https://rbxnet.australis.dev/docs/3.0/
--// OTHER MODULES: https://sleitnick.github.io/RbxUtil/
--// JANITORS: https://howmanysmall.github.io/Janitor/docs/Installation
--//

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = script.Parent
local Sensei = {}

Sensei._Providers = {}
Sensei._Extensions = {}
Sensei._Remotes = {}
Sensei._Starting = false
Sensei._Started = false
Sensei._Awaiting = {}
Sensei._RenderSteppedFunctions = {}
Sensei._HeartbeatFunctions = {}
Sensei._PlayerAddedFunctions = {}
Sensei._PlayerRemovingFunctions = {}

Sensei.Input = require(Packages.Input)
Sensei.Janitor = require(Packages.Janitor)
Sensei.Net = require(Packages.Net)
Sensei.Shake = require(Packages.Shake)
Sensei.Signal = require(Packages.Signal)
Sensei.Promise = require(Packages.Promise)

Sensei.ProfileService = require(Packages.ProfileService)

function Sensei:_RunExtensions(funcName, provider)
	local function Run(extension)
		local func = extension[funcName]
		if typeof(func) == "function" then
			func(provider)
		end
	end
	for _,extension: Extension in ipairs(self._Extensions) do
		Run(extension)
	end
	if provider.SenseiExtensions then
		for _,extension: Extension in ipairs(provider.SenseiExtensions) do
			Run(extension)
		end
	end
end

function Sensei:SetRemotes(Remotes)
	if self._Started or self._Starting then
		error("Cannot add remotes after Sensei has started", 2)
	end
	Sensei._Remotes = Remotes
end

function Sensei:AddExtension(extension: Extension): Extension
	if self._Started or self._Starting then
		error("Cannot add extensions after Sensei has started", 2)
	end
	table.insert(self._Extensions, extension)
	return extension
end

function Sensei:AddProvider(provider: Provider): Provider
	if self._Started or self._Starting then
		error("Cannot add providers after Sensei has started", 2)
	elseif table.find(self._Providers, provider) ~= nil then
		error("Provider already exists", 2)
	end
	table.insert(self._Providers, provider)
	return provider
end

function Sensei:GetProvider(name)
	-- Yield until Sensei is loaded and started
	if not self._Started then
		table.insert(self._Awaiting, coroutine.running())
		coroutine.yield()
	end
	-- After it is 100% loaded then get the provider
	for _, provider in pairs(self._Providers) do
		if provider.Name and provider.Name == name then
			return provider
		end
	end
end

function Sensei:Start() --// Yields, dont call more than once

	if self._Started or self._Starting then
		error("Sensei already started", 2)
	end
	self._Starting = true

	local numProviders = #self._Providers
	local prepareDone = 0

	-- Call all OnPrepare methods:
	local thread = coroutine.running()
	for _,provider: Provider in ipairs(self._Providers) do
		provider.Remotes = self._Remotes
		if typeof(provider.OnPrepare) == "function" then
			task.spawn(function()
				self:_RunExtensions("BeforePrepare", provider)
				if provider.Name then
					debug.setmemorycategory(provider.Name)
				end
				provider:OnPrepare()
				prepareDone += 1
				if prepareDone == numProviders then
					if coroutine.status(thread) == "suspended" then
						task.spawn(thread)
					end
				end
			end)
		end
		--// Add RenderStepped / Heartbeat / PlayerAdded / PlayerRemoving methods to a table
		if typeof(provider.RenderStepped) == "function" then
			table.insert(self._RenderSteppedFunctions, provider.RenderStepped)
		end

		if typeof(provider.Heartbeat) == "function" then
			table.insert(self._HeartbeatFunctions, provider.Heartbeat)
		end

		if typeof(provider.PlayerAdded) == "function" then
			table.insert(self._PlayerAddedFunctions, provider.PlayerAdded)
		end

		if typeof(provider.PlayerRemoving) == "function" then
			table.insert(self._PlayerRemovingFunctions, provider.PlayerRemoving)
		end
	end

	-- Await all OnPrepare methods to be completed:
	if numProviders ~= prepareDone then
		coroutine.yield(thread)
	end

	-- Call all OnStart methods:
	for _,provider: Provider in ipairs(self._Providers) do
		if typeof(provider.OnStart) == "function" then
			task.spawn(function()
				self:_RunExtensions("BeforeStarted", provider)
				if provider.Name then
					debug.setmemorycategory(provider.Name)
				end
				provider:OnStart()
			end)
		end
	end

	-- Resume awaiting threads:
	for _,awaitingThread in ipairs(self._Awaiting) do
		task.defer(awaitingThread)
	end

	self._Starting = false
	self._Started = true

	-- Setup unique functions
	--// RenderStepped:
	if RunService:IsClient() then
		RunService.RenderStepped:Connect(function(dt)
			for _, func in pairs(self._RenderSteppedFunctions) do
				func(dt)
			end
		end)
	end

	--// Heartbeat:
	RunService.Heartbeat:Connect(function(dt)
		for _, func in pairs(self._HeartbeatFunctions) do
			func(dt)
		end
	end)

	--// PlayerAdded:
	local already_joined = Players:GetPlayers()
	for _, func in pairs(self._PlayerAddedFunctions) do
		for _, player in pairs(already_joined) do
			func(player)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		for _, func in pairs(self._PlayerAddedFunctions) do
			func(player)
		end
	end)

	--// PlayerRemoving:
	Players.PlayerRemoving:Connect(function(player)
		for _, func in pairs(self._PlayerRemovingFunctions) do
			func(player)
		end
	end)

end

--[=[
	@yields
	Yields the current thread until Sensei has fully started. If Sensei
	has already been started, this function simply does nothing.
	```lua
	Sensei:AwaitStart()
	print("Sensei has started!")
	```
]=]
function Sensei:AwaitStart()
	if self._Started then return end
	table.insert(self._Awaiting, coroutine.running())
	coroutine.yield()
end

--[=[
	Calls the callback once Sensei has fully started. If Sensei has
	already been started, then the callback is immediately called.
	```lua
	Sensei:OnStart(function()
		print("Sensei has started!")
	end)
	```
]=]
function Sensei:OnStart(callback: () -> ())
	if not self._Started then
		task.spawn(callback)
		return
	end
	local thread = coroutine.create(callback)
	table.insert(self._Awaiting, thread)
end

return Sensei