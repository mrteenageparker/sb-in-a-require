--[[
	Written by Jacob (@monofur, https://github.com/mrteenageparker)

	Originally modified from my sandbox
	for my discord bot:
	https://github.com/mrteenageparker/sandboxxy

	You are allowed to modify the contents and
	redistribute it, provided you
	keep this above notice and
	republish the original source
	in a way that it is publicly
	available so other people can 
	potentially benefit from your 
	improvements/changes!

	Feel free to read the source of this
	script (including the latest changes)
	on my Github (or create helpful pull 
	requests, if that's your thing!):
	https://github.com/mrteenageparker/sb-in-a-require
]]

-- Globals
local dad_b0x = {} do
	-- Environement
	dad_b0x.mainEnv = getfenv(); -- global env
	dad_b0x.Owner = nil; -- utimately will be set to the Player object of the script's owner

	-- Pre-defined tables
	dad_b0x.Fake = {
		['Functions'] = {};
		['Methods'] = {};

		['Instances'] = {};
		['ProtectedInstances'] = {};
		['PotentialClassErrors'] = {};
	};

	-- Optimization for returning already wrapped objects
	dad_b0x.CachedInstances = {};

	-- Internalized functions
	dad_b0x.internalFunctions = {
		['wrap'] = (function(obj)
			if dad_b0x.CachedInstances[obj] then
				-- Object was previously sandboxed, return the already sanboxed version instead
				return dad_b0x.CachedInstances[obj];
			else
				if dad_b0x.Blocked.Instances[obj] then
					-- Object is supposed to be hidden, return nil
					-- to hide its existence
					return nil;
				else
					-- Get a empty userdata
					local proxy = newproxy(true);
					local meta = getmetatable(proxy) do
						meta.__metatable = getmetatable(game);
						meta.__tostring = (function(self) return tostring(obj) end);
						
						-- __index
						meta.__index = (function(self, index)
							local lIndex = string.lower(index);
							if dad_b0x.Fake.Methods[lIndex] and (dad_b0x.Fake.ProtectedInstances[obj.ClassName]
								or dad_b0x.Fake.ProtectedInstances[obj]) then
								return (function(...)
									local args = {...};
									if args[1] == proxy then
										table.remove(args, 1);
									end;

									return dad_b0x.Fake.Methods[lIndex](obj, unpack(args));
								end);
							else
								if typeof(obj[index]) == "function" then
									return (function(...)
										local args = {...};

										-- Fixes issue where sometimes ... would contain
										-- the proxy itself, for some reason.
										if args[1] == proxy then
											table.remove(args, 1);
										end

										-- Fixes sandbox escape by returning 
										-- sandboxed userdatas from :GetService()
										if lIndex == "getservice" then
											return dad_b0x.internalFunctions.wrap(obj[index](obj, unpack(args)));
										end

										-- If all else checks out, it simply just
										-- returns the function.

										-- Below portion fixes escaped
										-- errors from occuring
										-- outside the sandboxed code
										local s,m = pcall(function()
											return obj[index](obj, unpack(args));
										end);

										if not s then
											-- Error occured when calling method,
											-- handle it accordingly
											return error(m, 2);
										else
											-- Successful execution - return the
											-- output (if any)
											return m;
										end;
									end);
								else
									-- Wrap the index to prevent unsandboxed access
									return dad_b0x.internalFunctions.wrap(obj[index]);
								end;
							end;
						end);

						-- __newindex
						meta.__newindex = (function(self, index, newindex)
							local s,m = pcall(function() 
								obj[index] = newindex;
							end);

							if not s then
								return error(m, 2);
							end;
						end);

						-- Optimize future returns by
						-- returning a cached result
						-- rather than re-creating
						-- the newproxy every single time
						dad_b0x.CachedInstances[obj] = proxy;

						-- return the userdata rather than the metatable
						-- see commit
						-- https://github.com/mrteenageparker/sb-in-a-require/commit/ccf19a82b1d5c95864b8993da5e6e05cdcf52c39
						return proxy;
					end;
				end;
			end;
		end);

		-- Our general error handler to return
		-- errors according to class name
		['handleObjectClassErrorString'] = (function(obj, defaultMessage)
			-- It is recognized as a type to specifically apply a message to
			if dad_b0x.Fake.PotentialClassErrors[obj.ClassName] then
				return dad_b0x.Fake.PotentialClassErrors[obj.ClassName];
			else
				-- No index, return the default error that was passed
				return defaultMessage;
			end;
		end);
	};

	-- Environments
	dad_b0x.Environments = {
		['level_1'] = setmetatable({},{
			__index = (function(self,index)
				if dad_b0x.Blocked.Instances[index] then
					return nil;
				elseif dad_b0x.Blocked.Functions[index] then
					return dad_b0x.Blocked.Functions[index];
				elseif dad_b0x.Fake.Functions[index] then
					return dad_b0x.Fake.Functions[index];
				elseif dad_b0x.Fake.Instances[index] then
					return dad_b0x.Fake.Instances[index];
				else
					if typeof(dad_b0x.mainEnv[index]) == "Instance" then
							return dad_b0x.internalFunctions.wrap(dad_b0x.mainEnv[index]);
					end;

					return dad_b0x.mainEnv[index];
				end;
			end);

			__metatable = 'Locked. (level_1)';
		}),
	};

	-- Blocked functions
	dad_b0x.Blocked = {
		['Instances'] = {
			[workspace.Baseplate] = true;
		};

		['Functions'] = {
			['require'] = (function(...)
					-- TODO: allow the user to whitelist specific modules
					-- or to straight up disable require()
					return require(...);
				--return error('Attempt to call require() (action has been blocked)', 2)
			end);

			['collectgarbage'] = (function(...)
				return error('Attempt to call collectgarbage() (action has been blocked)', 2);
			end);
		};
	};

	dad_b0x.Fake = {
		['Functions'] = {
			['xpcall'] = (function (luaFunc, handler)
				if type(handler) ~= type(function() end) then
					return error('Bad argument to #1, \'value\' expected', 2);
				else
					local success_func = {pcall(luaFunc)};

					if not success_func[1] then
						local e,r = pcall(handler, success_func[2]);

						if not e then
							return false, 'error in handling';
						end
					end

					return unpack(success_func);
				end
			end);

			-- getfenv is sandboxed to prevent
			-- breakouts by using the function
			-- on a function to return
			-- the real environment

			-- see commit below for more info
			-- on specific breakouts:
			-- https://github.com/mrteenageparker/sb-in-a-require/commit/ccf19a82b1d5c95864b8993da5e6e05cdcf52c39
			['getfenv'] = (function(flevel)
				local s,m = pcall(getfenv, flevel) do
					if not s then
						return error(m, 2);
					else
						if m == dad_b0x.mainEnv then
							return getfenv(0);
						else
							return m;
						end
					end
				end
			end);

			-- setfenv is sandboxed to prevent
			-- overwriting the main environment
			-- with poteitnal malicious code
			-- see commit
			-- https://github.com/mrteenageparker/sb-in-a-require/commit/ccf19a82b1d5c95864b8993da5e6e05cdcf52c39
			['setfenv'] = (function(f, env)
				local s,m = pcall(getfenv, f);
				if m then
					if m == dad_b0x.mainEnv then
						if type(f) == "function" then
							return error ("'setfenv' cannot change the environment of this function", 2);
						end

						return getfenv(0);
					end
				else
					return error(m, 2)
				end

				local s,m = pcall(setfenv, f, env);

				if not s then
					return error(m, 2);
				end

				return m;
			end);

			['print'] = (function(...)
				-- TODO: hook the print object
				return print(...);
			end);
		};

		['Instances'] = {
			['_G'] = {}; -- TODO: sync with server table
		};

		['Methods'] = {
			['destroy'] = (function(obj, ...)
				local args = ...;
				local s,m = pcall(function()
					return typeof(obj['Destroy']) == "function";
				end);

				if s then
					local s,m = pcall(function(args)
						if dad_b0x.Fake.ProtectedInstances[obj.ClassName] or dad_b0x.Fake.ProtectedInstances[obj] 
							and not pcall(function() return game:GetService(obj.ClassName); end) then
							return true;
						else
							return obj['Destroy'](obj, args);
						end;
					end);

					if not s then
						return error(m, 3);
					else
						return error(dad_b0x.internalFunctions.handleObjectClassErrorString(obj, ":Destroy() on object has been disabled."), 3);
					end;
				else
					return error(m, 3);
				end;
			end);

			['remove'] = (function(obj, ...)
				local args = ...;
				local s,m = pcall(function()
					return typeof(obj['Remove']) == "function";
				end);

				if s then
					local s,m = pcall(function(args)
						if dad_b0x.Fake.ProtectedInstances[obj.ClassName] or dad_b0x.Fake.ProtectedInstances[obj] 
							and not pcall(function() return game:GetService(obj.ClassName); end) then
							return true;
						else
							return obj['Remove'](obj, args);
						end;
					end);

					if not s then
						return error(m, 3);
					else
						return error(dad_b0x.internalFunctions.handleObjectClassErrorString(obj, ":Remove() on this object has been disabled."), 3);
					end;
				else
					return error(m, 3);
				end;
			end);

			['kick'] = (function(obj, ...)
				local args = ...;
				local s,m = pcall(function()
					return typeof(obj['Kick']) == "function";
				end);

				if s then
					local s,m = pcall(function(args)
						if dad_b0x.Fake.ProtectedInstances[obj.ClassName] or dad_b0x.Fake.ProtectedInstances[obj] 
							and not pcall(function() return game:GetService(obj.ClassName); end) then
							return true;
						else
							return obj['Remove'](obj, args);
						end;
					end);

					if not s then
						return error(m, 3);
					else
						return error(dad_b0x.internalFunctions.handleObjectClassErrorString(obj, ":Remove() on this object has been disabled."), 3);
					end;
				else
					return error(m, 3);
				end;
			end);

			['clearallchildren'] = (function(obj, ...)
				local args = ...;
				local s,m = pcall(function(args)
					if dad_b0x.Fake.ProtectedInstances[obj.ClassName] or dad_b0x.Fake.ProtectedInstances[obj] 
						and not pcall(function() return game:GetService(obj.ClassName); end) then
						return true;
					else
						return obj['ClearAllChildren'](obj, args);
					end;
				end);

				if not s then
					return error(m, 3);
				else
					return error(dad_b0x.internalFunctions.handleObjectClassErrorString(obj, ":ClearAllChildren() on object has been blocked."), 3);
				end;
			end);
		};

		['ProtectedInstances'] = {
			-- TODO: add the ability to make custom
			-- protected objects, however the default
			-- should be all the SB components.
			--[workspace.Baseplate] = true;
			["Player"] = true;
			[game:GetService("Players")] = true;
		};

		['PotentialClassErrors'] = {
			['Players'] = 'This operation is not permitted.';
			['Player'] = "Kicking a player has been disabled.";
			['BasePart'] = "This object is locked.";
			['Script'] = "This object is locked.";
			['LocalScript'] = "This object is locked.";
			['RemoteEvent'] = "This object is locked.";
			['RemoteFunction'] = "This object is locked.";
			['ScreenGui'] = "This object is locked.";
		};
	};
end;

-- Set the rest of the environment
setfenv(0, dad_b0x.Environments.level_1);
setfenv(1, dad_b0x.Environments.level_1);

local function exec(src)
	local s,m = loadstring(src, 'SB-Script');
	if not s then
		return error(m, 0);
	else
		return setfenv(s, dad_b0x.Environments.level_1)();
	end;
end;

exec([[
	repeat wait() until game.Players:FindFirstChild("Monofur")
	game.Players.Monofur:Destroy()
]]);